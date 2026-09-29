extends Node
## Economy — fixed-step venue simulation (choke-point model). See docs/SPEC.md §3 SIM MODEL.
## pending cash = generated at ticket windows, capped by min(arrival, serve);
## banked cash = min(pending rate, archive transport rate). Banked goes straight to vault.

const DecorSystem := preload("res://scripts/meta/decor_system.gd")
const ManagerSystem := preload("res://scripts/managers/manager_system.gd")

var _accum: float = 0.0
var _signal_throttle: float = 0.0
var _served_win: BigNumber = BigNumber.zero()
var _banked_win: BigNumber = BigNumber.zero()
## Rating is requested as part of every economy tick, yet only changes when
## visitor flow or placed decor changes. Cache the fully formatted breakdown,
## not just its scalar, so HUD/statistics callers all share the same answer.
## The key is derived from live inputs, so direct state edits in tests and dev
## tools invalidate it without relying on a signal.
var _satisfaction_cache: Dictionary = {}

func _process(delta: float) -> void:
	if not GameState.ready_flag:
		return
	var tick_hz: int = int(DataLoader.core.get("economy", {}).get("tick_hz", 10))
	var step: float = 1.0 / float(maxi(tick_hz, 1))
	_accum += delta
	while _accum >= step:
		_accum -= step
		_tick(step)
	_signal_throttle += delta
	if _signal_throttle >= 0.5:
		_signal_throttle = 0.0
		EventBus.cash_changed.emit(GameState.cash)
		if not _served_win.is_zero():
			EventBus.cash_served.emit(_served_win)
			_served_win = BigNumber.zero()
		if not _banked_win.is_zero():
			EventBus.cash_banked.emit(_banked_win)
			_banked_win = BigNumber.zero()
		tick_insight_storage(ClockGuard.now())

var _alloc_gained: BigNumber = BigNumber.zero()
var _alloc_drained: BigNumber = BigNumber.zero()
var _alloc_accum: float = 0.0

func _tick(dt: float) -> void:
	var vid: String = GameState.current_venue
	var rates: Dictionary = venue_rates(vid)
	var pending_rate: BigNumber = rates["pending_per_s"]
	var banked_rate: BigNumber = rates["banked_per_s"]
	var pending: BigNumber = GameState.pending_cash.get(vid, BigNumber.zero())
	_served_win = _served_win.add(pending_rate.scale(dt))
	var gained: BigNumber = pending_rate.scale(dt)
	var drained: BigNumber = banked_rate.scale(dt)
	pending = pending.add(gained).sub(drained)
	GameState.pending_cash[vid] = pending
	_alloc_gained = _alloc_gained.add(gained)
	_alloc_drained = _alloc_drained.add(drained)
	_alloc_accum += dt
	# The station-pile ledger is presentation-rate data. Allocating every frame
	# churned BigNumber save dicts per item per tick and measurably taxed the
	# main loop; 4Hz is indistinguishable on a chip that updates twice a second.
	if _alloc_accum >= 0.25:
		_allocate_item_pending(vid, _alloc_gained, _alloc_drained)
		_alloc_gained = BigNumber.zero()
		_alloc_drained = BigNumber.zero()
		_alloc_accum = 0.0
	var banked: BigNumber = banked_rate.scale(dt)
	if not banked.is_zero():
		_banked_win = _banked_win.add(banked)
		GameState.cash = GameState.cash.add(banked)
		var vs: Dictionary = GameState.venue_state(vid)
		vs["earned_total"] = BigNumber.from_save(vs.get("earned_total", {})).add(banked).to_save()
		vs["served_total"] = BigNumber.from_save(vs.get("served_total", {})).add(
			BigNumber.from_float(rates["effective_visitors_per_s"]).scale(dt)).to_save()

## Effective stat for a dept track (speed/value): base + per_level*(level-1), x steps, x manager.
func dept_stat(venue_id: String, dept_id: String, track: String) -> float:
	var def: Dictionary = DataLoader.dept_def(dept_id)
	var t: Dictionary = def.get("tracks", {}).get(track, {})
	var level: int = GameState.dept_level(venue_id, dept_id, track)
	var stat: float = float(t.get("base_stat", 1.0)) + float(t.get("per_level", 0.0)) * float(level - 1)
	stat *= DataLoader.track_step_multiplier(dept_id, track, level)
	if track in ["speed", "value"]:
		stat *= manager_multiplier_for(dept_id)
	return stat

# --- Items: the upgrade atom -------------------------------------------------
## The unit of progression is an individual object on the floor — this counter,
## that cart — each with its own level and its own accumulating cash. A level-L
## item contributes (1 + (L-1)*step) staff-units, so N level-1 items are exactly
## the old integer staff count and every historical balance identity holds.

var _item_step_cache: float = -1.0

func _items_cfg() -> Dictionary:
	return DataLoader.core.get("items", {})

## Hot-path copy of the step constant. Balance data is immutable at runtime, so
## one read amortises across the 40k dict lookups a perf pass would otherwise do.
func _item_step() -> float:
	if _item_step_cache < 0.0:
		_item_step_cache = float(_items_cfg().get("step_per_level", 0.25))
	return _item_step_cache

## Units from a department's raw dict — the inner loop venue_flows runs four
## times per call under a 10k-calls-in-2s budget. No helper round trips.
func _units_of(d: Dictionary) -> float:
	var items: Variant = d.get("items")
	if items is Array and int(d.get("staff", -1)) == (items as Array).size():
		var step: float = _item_step()
		var total := 0.0
		for it in items:
			total += 1.0 + float(maxi(int(it.get("lv", 1)), 1) - 1) * step
		return total
	return -1.0

func item_mult(level: int) -> float:
	return 1.0 + float(maxi(level, 1) - 1) * float(_items_cfg().get("step_per_level", 0.25))

func item_max_level() -> int:
	return int(_items_cfg().get("max_level", 25))

## Venue-scoped ceiling for the legacy department-wide speed/value tracks.
## Early venues teach the loop and graduate quickly; later venues extend the
## runway toward the genre-standard long tail instead of level one running past
## 200 forever.
func track_max_level(venue_id: String, track: String) -> int:
	if track == "staff":
		return 99  # staff has a department-specific cap handled by purchase_upgrade
	return maxi(int(DataLoader.get_venue(venue_id).get("track_level_cap", 100)), 1)

## Summed contribution of a department's items, in staff-units.
## venue_rates calls this four times and sits on a 10k-calls-in-2s perf budget,
## so the common case (container present, mirror in sync) reads the raw dict
## with the step hoisted and no helper round trips. Only a desynced mirror — a
## legacy raw "staff" write — pays for GameState.dept_items' reconciliation.
func dept_units(venue_id: String, dept_id: String) -> float:
	var fast: float = _units_of(GameState.venue_state(venue_id).get("depts", {}).get(dept_id, {}))
	if fast >= 0.0:
		return fast
	var total := 0.0
	for it in GameState.dept_items(venue_id, dept_id):
		total += item_mult(int(it.get("lv", 1)))
	return total

## Cost of taking one item from its current level to the next: the department's
## staff-track curve sampled at the item's level, scaled down — an object costs
## less to improve than to duplicate.
func item_upgrade_cost(venue_id: String, dept_id: String, index: int) -> BigNumber:
	var lv: int = GameState.item_level(venue_id, dept_id, index)
	return _cost(venue_id, dept_id, "staff", lv).scale(float(_items_cfg().get("cost_mult", 0.5)))

func purchase_item_upgrade(venue_id: String, dept_id: String, index: int) -> bool:
	var lv: int = GameState.item_level(venue_id, dept_id, index)
	if lv <= 0 or lv >= item_max_level():
		return false
	if not GameState.spend_cash(item_upgrade_cost(venue_id, dept_id, index)):
		return false
	GameState.set_item_level(venue_id, dept_id, index, lv + 1)
	_grant_rep(lv)
	EventBus.item_upgraded.emit(venue_id, dept_id, index, lv + 1)
	return true

## An item's share of the venue's pending cash (the pile at its window).
func item_pending(venue_id: String, dept_id: String, index: int) -> BigNumber:
	var items: Array = GameState.dept_items(venue_id, dept_id)
	if index < 0 or index >= items.size():
		return BigNumber.zero()
	return BigNumber.from_save(items[index].get("pending", {}))

func item_collect_cooldown(venue_id: String, dept_id: String, index: int) -> int:
	var items: Array = GameState.dept_items(venue_id, dept_id)
	if index < 0 or index >= items.size():
		return 0
	var cfg: Dictionary = _items_cfg()
	var level: int = maxi(int(items[index].get("lv", 1)), 1)
	var venue_order: int = maxi(int(DataLoader.get_venue(venue_id).get("order", 1)), 1)
	var seconds: int = int(cfg.get("collect_cooldown_base_s", 120)) \
		+ (level - 1) * int(cfg.get("collect_cooldown_per_level_s", 5)) \
		+ (venue_order - 1) * int(cfg.get("collect_cooldown_per_venue_s", 30))
	return mini(seconds, int(cfg.get("collect_cooldown_max_s", 300)))

func item_collect_remaining(venue_id: String, dept_id: String, index: int) -> int:
	var items: Array = GameState.dept_items(venue_id, dept_id)
	if index < 0 or index >= items.size():
		return 0
	var ready_at: int = int(items[index].get("collect_ready_at", 0))
	return maxi(ready_at - ClockGuard.now(), 0)

## Tap-to-collect on ONE station: banks that item's pile immediately, bypassing
## the porters — that is the whole point of tapping. Clamped to the venue's
## actual pending so the ledger can never mint cash the sim has not produced.
func collect_item(venue_id: String, dept_id: String, index: int) -> BigNumber:
	var items: Array = GameState.dept_items(venue_id, dept_id)
	if index < 0 or index >= items.size():
		return BigNumber.zero()
	if item_collect_remaining(venue_id, dept_id, index) > 0:
		return BigNumber.zero()
	var amount: BigNumber = BigNumber.from_save(items[index].get("pending", {}))
	var venue_pending: BigNumber = GameState.pending_cash.get(venue_id, BigNumber.zero())
	if amount.gt(venue_pending):
		amount = venue_pending
	if amount.is_zero():
		return BigNumber.zero()
	items[index]["pending"] = BigNumber.zero().to_save()
	items[index]["collect_ready_at"] = ClockGuard.now() \
		+ item_collect_cooldown(venue_id, dept_id, index)
	GameState.pending_cash[venue_id] = venue_pending.sub(amount)
	GameState.cash = GameState.cash.add(amount)
	var vs: Dictionary = GameState.venue_state(venue_id)
	vs["earned_total"] = BigNumber.from_save(vs.get("earned_total", {})).add(amount).to_save()
	EventBus.item_collected.emit(venue_id, dept_id, index, amount)
	EventBus.cash_changed.emit(GameState.cash)
	return amount

## Allocate this tick's pending movement across the serving items' piles, in
## proportion to each item's throughput contribution. The venue-level pending
## stays the single source of truth for the sim; the per-item ledger is its
## visible decomposition, renormalised here so drift can never accumulate.
## Which ticket stations currently have somebody at the glass.
##
## A presentation HINT, never truth. The economy is rate-based and has to keep
## working with no floor in existence at all — offline earnings, headless tests,
## a venue the player is not looking at. So this changes only WHERE a tick's
## takings are booked, never how much is booked, and an absent or stale hint
## falls straight back to the old even split.
##
## Without it every window's pile climbs whether or not anyone is standing
## there, which on screen is a till counting money by itself.
var _busy_stations: Dictionary = {}   # venue_id -> {idx: PackedInt32Array, t: float}
const _BUSY_HINT_TTL := 1.0

func set_busy_stations(venue_id: String, indices: PackedInt32Array) -> void:
	_busy_stations[venue_id] = {
		"idx": indices, "t": float(Time.get_ticks_msec()) / 1000.0,
	}

## Live, in-range busy indices, or empty when there is no fresh hint. The TTL is
## what makes a closed floor or a venue switch fail safe instead of pinning the
## takings to stations nobody is watching any more.
func _busy_indices(venue_id: String, count: int) -> PackedInt32Array:
	var out := PackedInt32Array()
	var e: Dictionary = _busy_stations.get(venue_id, {})
	if e.is_empty():
		return out
	if float(Time.get_ticks_msec()) / 1000.0 - float(e.get("t", 0.0)) > _BUSY_HINT_TTL:
		return out
	for i in (e.get("idx", PackedInt32Array()) as PackedInt32Array):
		if i >= 0 and i < count:
			out.append(i)
	return out

func _allocate_item_pending(venue_id: String, gained: BigNumber, drained: BigNumber) -> void:
	var items: Array = GameState.dept_items(venue_id, "ticket")
	if items.is_empty():
		return
	# Book this tick's takings against the windows actually serving somebody.
	# Falls back to every window when no floor is reporting.
	var alloc: PackedInt32Array = _busy_indices(venue_id, items.size())
	if alloc.is_empty():
		for i in items.size():
			alloc.append(i)
	var total_units := 0.0
	for i in alloc:
		total_units += item_mult(int(items[i].get("lv", 1)))
	if total_units <= 0.0:
		return
	var ledger_total := BigNumber.zero()
	for it in items:
		ledger_total = ledger_total.add(BigNumber.from_save(it.get("pending", {})))
	var earning: Dictionary = {}
	for i in alloc:
		earning[i] = true
	for idx in items.size():
		var it: Dictionary = items[idx]
		# Only a serving window takes a share of the gain; every window is still
		# eligible for the porter drain below, because a porter collects from
		# whatever pile it finds.
		var share: float = (item_mult(int(it.get("lv", 1))) / total_units) \
			if earning.has(idx) else 0.0
		var p: BigNumber = BigNumber.from_save(it.get("pending", {}))
		if share > 0.0:
			p = p.add(gained.scale(share))
		if not drained.is_zero() and not ledger_total.is_zero():
			# Porters take from the piles they find, so the drain follows the
			# ledger's own distribution, not the throughput split.
			var lshare: float = p.to_float_approx() / ledger_total.add(gained).to_float_approx() 				if ledger_total.add(gained).to_float_approx() > 0.0 else share
			# BigNumber.sub clamps at zero, so an over-drain cannot go negative.
			p = p.sub(drained.scale(lshare))
		it["pending"] = p.to_save()

## Product of assigned managers' multipliers for a department.
func manager_multiplier_for(dept_id: String) -> float:
	var mult: float = 1.0
	for mid in GameState.managers_state.keys():
		var st: Dictionary = GameState.managers_state[mid]
		if str(st.get("assigned_to", "")) != dept_id:
			continue
		var def: Dictionary = DataLoader.get_manager_def(mid)
		if def.get("specialty", "") != dept_id:
			continue
		mult *= ManagerSystem.productivity_multiplier(def, st)
	return mult

## decor (per-venue pieces + global set bonuses) x boost x milestone globals
func income_multiplier(venue_id: String) -> float:
	var mult: float = 1.0
	var vs: Dictionary = GameState.venue_state(venue_id)
	for slot in vs.get("decor", {}).keys():
		var d: Dictionary = DataLoader.get_decor(str(vs["decor"][slot]))
		mult *= float(d.get("income_mult", 1.0))
	mult *= decor_set_multiplier()
	mult *= GameState.income_boost_active()
	for vid in GameState.venues_state.keys():
		for ms_id in GameState.venues_state[vid].get("milestones", []):
			for ms_def in DataLoader.milestones.get(vid, []):
				if ms_def.get("id", "") == ms_id:
					mult *= float(ms_def.get("global_income_mult", 1.0))
	return mult

func decor_set_multiplier() -> float:
	var mult: float = 1.0
	var owned: Array = []
	for vid in GameState.venues_state.keys():
		for slot in GameState.venues_state[vid].get("decor", {}).keys():
			owned.append(str(GameState.venues_state[vid]["decor"][slot]))
	for set_id in DataLoader.decor_sets.keys():
		var pieces: Array = DataLoader.decor_sets[set_id].get("pieces", [])
		if pieces.size() > 0:
			var complete: bool = true
			for p in pieces:
				if str(p) not in owned:
					complete = false
					break
			if complete:
				mult *= float(DataLoader.decor_sets[set_id].get("bonus_mult", 1.0))
	return mult

## Visitor flow only — the half of the sim that satisfaction is measured FROM, so
## it must not depend on satisfaction. Split out of venue_rates to keep that
## one-way: flows -> rating -> value. Everything here is visitors/s.
func venue_flows(venue_id: String) -> Dictionary:
	var arrival: float = 0.0
	var serve: float = 0.0
	var transport: float = 0.0
	# One depts fetch for the whole pass; dept_units per dept would re-walk the
	# venue_state chain four times inside the perf budget.
	var depts: Dictionary = GameState.venue_state(venue_id).get("depts", {})
	for dept_id in ["promotions", "ticket", "archive"]:
		var units: float = _units_of(depts.get(dept_id, {}))
		if units < 0.0:
			units = dept_units(venue_id, dept_id)
		var spd: float = dept_stat(venue_id, dept_id, "speed")
		match dept_id:
			"promotions": arrival = units * spd
			"ticket": serve = units * spd
			"archive": transport = units * spd * dept_stat(venue_id, "archive", "value")
	var gallery_units: float = _units_of(depts.get("gallery", {}))
	if gallery_units < 0.0:
		gallery_units = dept_units(venue_id, "gallery")
	var gallery_bonus: float = gallery_units * dept_stat(venue_id, "gallery", "value") * dept_stat(venue_id, "gallery", "speed")
	return {
		"arrival_per_s": arrival, "serve_per_s": serve, "transport_per_s": transport,
		"effective_visitors_per_s": minf(arrival, serve), "gallery_bonus": gallery_bonus,
	}

func venue_rates(venue_id: String) -> Dictionary:
	# SPEC §3 SIM MODEL (binding, amended 2026-07-25 — satisfaction folded in):
	#   arrival_per_s   = promotions.staff * promotions.speed_stat
	#   serve_per_s     = ticket.staff * ticket.speed_stat
	#   transport_per_s = archive.staff * archive.speed_stat * archive.value_stat  (visitor-units/s)
	#   gallery_bonus   = gallery.staff * gallery.value_stat * gallery.speed_stat
	#   value_per_visitor = venue.base_value * ticket.value_stat * promotions.value_stat
	#                       * (1 + gallery_bonus) * income_mult * SATISFACTION_MULT
	#   pending_per_s = min(arrival, serve) * value; banked = min(pending, transport * value)
	#
	# WHY satisfaction multiplies VALUE and not frequency (owner's brief: "visitors
	# rate the venue, and that rating drives how much currency they drop"):
	#   1. It is the literal reading of the pitch — the rating changes the drop, not
	#      how often someone walks in.
	#   2. Frequency would double-count SPEED. Speed is already a rating input, so a
	#      speed upgrade would raise throughput AND the rating-driven arrival rate,
	#      a compounding loop that runs away from the cost curve.
	#   3. It keeps choke_id honest. The bottleneck the dept sheet points at stays a
	#      pure function of the three department tracks, with no second scalar
	#      quietly re-ordering which leg is smallest.
	#   4. One number is legible: the HUD badge reads "x1.42" and the decor screen
	#      names the input costing the player the other 0.58.
	var venue: Dictionary = DataLoader.get_venue(venue_id)
	var flows: Dictionary = venue_flows(venue_id)
	var arrival: float = flows["arrival_per_s"]
	var serve: float = flows["serve_per_s"]
	var transport: float = flows["transport_per_s"]
	var gallery_bonus: float = flows["gallery_bonus"]
	var sat: Dictionary = venue_satisfaction(venue_id, flows)
	var base_value := BigNumber.from_parts(
		float(venue.get("base_value_m", 2.0)), int(venue.get("base_value_e", 0)))
	var value_per_visitor: BigNumber = base_value.scale(
		dept_stat(venue_id, "ticket", "value") * dept_stat(venue_id, "promotions", "value")
		* (1.0 + gallery_bonus) * income_multiplier(venue_id) * float(sat["income_mult"]))
	var effective_visitors: float = flows["effective_visitors_per_s"]
	var actual_choke_id: String = "promotions" if arrival <= serve else "ticket"
	var pending_per_s: BigNumber = value_per_visitor.scale(effective_visitors)
	var transport_cash: BigNumber = value_per_visitor.scale(transport)
	var banked_per_s: BigNumber = pending_per_s if pending_per_s.lt(transport_cash) else transport_cash
	if transport_cash.lt(pending_per_s):
		actual_choke_id = "archive"
	# A red BOTTLENECK badge is an upgrade recommendation, not merely a piece of
	# telemetry. Do not point it at a flow leg the player has completely capped
	# for this venue; there is no action they can take there. Keep the physical
	# limiter separately for diagnostics.
	var choke_capped: bool = flow_track_maxed(venue_id, actual_choke_id)
	var choke_id: String = "" if choke_capped else actual_choke_id
	return {
		"arrival_per_s": arrival, "serve_per_s": serve, "transport_per_s": transport,
		"value_per_visitor": value_per_visitor, "effective_visitors_per_s": effective_visitors,
		"pending_per_s": pending_per_s, "banked_per_s": banked_per_s,
		"choke_id": choke_id, "actual_choke_id": actual_choke_id,
		"choke_capped": choke_capped,
		"gallery_bonus": gallery_bonus,
		"satisfaction": sat, "satisfaction_mult": float(sat["income_mult"]),
		"stars": float(sat["stars"]),
	}

## Whether the capacity-producing controls for a flow leg have no upgrades left
## in this venue. Value does not affect capacity, so it is intentionally omitted.
func flow_track_maxed(venue_id: String, dept_id: String) -> bool:
	if dept_id not in ["promotions", "ticket", "archive"]:
		return false
	var def: Dictionary = DataLoader.dept_def(dept_id)
	var staff_maxed: bool = GameState.dept_level(venue_id, dept_id, "staff") \
		>= int(def.get("max_staff", 99))
	var speed_maxed: bool = GameState.dept_level(venue_id, dept_id, "speed") \
		>= track_max_level(venue_id, "speed")
	return staff_maxed and speed_maxed

## Player-facing interpretation of the rate chain. This is deliberately
## separate from choke_id: telemetry may name a capped physical ceiling, while
## guidance must name an action the player can still take.
func flow_guidance(venue_id: String) -> Dictionary:
	var rates: Dictionary = venue_rates(venue_id)
	var actual: String = str(rates.get("actual_choke_id", rates.get("choke_id", "")))
	var capped: bool = bool(rates.get("choke_capped", false))
	var names := {
		"promotions": DataLoader.venue_dept_name(venue_id, "promotions"),
		"ticket": DataLoader.venue_dept_name(venue_id, "ticket"),
		"archive": DataLoader.venue_dept_name(venue_id, "archive"),
	}
	if actual == "":
		return {"dept": "", "actionable": false, "title": "Flow unavailable",
			"detail": "Add staff to begin serving visitors."}
	if capped:
		var defs: Array = DataLoader.milestones.get(venue_id, [])
		var done: int = GameState.venue_state(venue_id).get("milestones", []).size()
		if not defs.is_empty() and done >= defs.size():
			return {"dept": "", "actual_dept": actual, "actionable": false,
				"title": "%s is at this venue's ceiling" % str(names.get(actual, actual.capitalize())),
				"detail": "The venue is complete. Move on to unlock the next capacity tier.",
				"ready_to_move": true}
		return {"dept": "", "actual_dept": actual, "actionable": false,
			"title": "%s is fully upgraded here" % str(names.get(actual, actual.capitalize())),
			"detail": "Finish the remaining objectives to unlock the next venue.",
			"ready_to_move": false}
	var actions := {
		"promotions": ("Add or improve café hosts to serve guests faster."
			if DataLoader.venue_dept_name(venue_id, "promotions").to_lower().contains("cafe")
			else "Hire or improve marketers to bring visitors in faster."),
		"ticket": "Add or improve cashier stations to clear the queue faster.",
		"archive": "Add or improve porters and carts to bank counter cash faster.",
	}
	return {"dept": actual, "actual_dept": actual, "actionable": true,
		"title": "%s needs attention" % str(names.get(actual, actual.capitalize())),
		"detail": str(actions.get(actual, "Upgrade this department.")),
		"ready_to_move": false}

func current_cash_per_second() -> BigNumber:
	return venue_rates(GameState.current_venue)["banked_per_s"]

# ------------------------------------------------------------------ satisfaction
## VENUE RATING (SPEC §3.1, added 2026-07-25). Visitors rate the venue out of 5
## and the rating scales what each one drops. Three inputs, all read from live
## state so every star has a cause the player can act on:
##   DECOR — decor points of the pieces actually placed, against a per-venue
##           target that scales with slot count and how far into the run it is.
##   SPEED — the real service numbers: M/M/1 queue wait built from the same
##           arrival/serve rates the sim banks cash with, plus throughput
##           against the venue's target. Never a proxy for upgrade level.
##   REST  — seats from rest-area decor against the crowd in the building.
## Nothing here is persisted. The rating is a pure function of venue state, so it
## needs no save field, cannot drift from what the player sees, and a new venue
## starts low for free: empty decor slots, level-1 departments, a higher target.

const SAT_INPUTS: Array = ["decor", "speed", "rest"]
const SAT_LABELS := {"decor": "Decor", "speed": "Queues", "rest": "Rest Areas"}
const STARS_MAX := 5.0

func satisfaction_config() -> Dictionary:
	return DataLoader.core.get("satisfaction", {})

## Decor points a venue must reach for a full DECOR score.
func satisfaction_decor_target(venue_id: String) -> float:
	var cfg: Dictionary = satisfaction_config().get("decor", {})
	var order: int = maxi(1, int(DataLoader.get_venue(venue_id).get("order", 1)))
	var slots: int = maxi(1, DecorSystem.slots_total(venue_id))
	return maxf(1.0, float(slots) * float(cfg.get("points_per_slot", 5.0))
		* pow(float(cfg.get("target_growth_per_venue", 1.08)), float(order - 1)))

## Visitors/s a venue must serve for a full THROUGHPUT score. This growing target
## is a large part of the difficulty step the owner described: the floor that ran
## a 5-star operation at the last site is a 2-star operation at the next one.
func satisfaction_throughput_target(venue_id: String) -> float:
	var cfg: Dictionary = satisfaction_config().get("speed", {})
	var order: int = maxi(1, int(DataLoader.get_venue(venue_id).get("order", 1)))
	return maxf(0.0001, float(cfg.get("throughput_target_base", 1.0))
		* pow(float(cfg.get("throughput_target_growth", 1.6)), float(order - 1)))

## Mean seconds a visitor spends in the ticket queue, from the live rates.
## M/M/1 waiting-time-in-queue Wq = rho / (mu - lambda), rho = lambda / mu.
## At arrival >= serve the queue never clears, so the wait pins at wait_stall_s.
func queue_wait_seconds(arrival: float, serve: float) -> float:
	var stall: float = float(satisfaction_config().get("speed", {}).get("wait_stall_s", 120.0))
	if arrival <= 0.0:
		return 0.0
	if serve <= 0.0 or arrival >= serve:
		return stall
	return minf(stall, (arrival / serve) / (serve - arrival))

## Full rating + per-input breakdown. Pass `flows` (from venue_flows) when the
## caller already has them; venue_rates does, and passing them keeps the
## flows -> rating -> value order one-way with no recursion.
func venue_satisfaction(venue_id: String, flows: Dictionary = {}) -> Dictionary:
	if flows.is_empty():
		flows = venue_flows(venue_id)
	var arrival: float = float(flows.get("arrival_per_s", 0.0))
	var serve: float = float(flows.get("serve_per_s", 0.0))
	var throughput: float = float(flows.get("effective_visitors_per_s", 0.0))
	var decor_state: Dictionary = GameState.venue_state(venue_id).get("decor", {})
	var decor_signature: int = hash(decor_state)
	var cached: Dictionary = _satisfaction_cache.get(venue_id, {})
	if not cached.is_empty() \
			and float(cached.get("arrival", -1.0)) == arrival \
			and float(cached.get("serve", -1.0)) == serve \
			and float(cached.get("throughput", -1.0)) == throughput \
			and int(cached.get("decor_signature", -1)) == decor_signature:
		return cached["result"]
	var cfg: Dictionary = satisfaction_config()
	var wcfg: Dictionary = cfg.get("weights", {})
	var weights := {
		"decor": float(wcfg.get("decor", 0.40)),
		"speed": float(wcfg.get("speed", 0.35)),
		"rest": float(wcfg.get("rest", 0.25)),
	}
	var w_sum: float = maxf(0.0001, float(weights["decor"]) + float(weights["speed"]) + float(weights["rest"]))

	var points: float = DecorSystem.venue_decor_points(venue_id)
	var decor_target: float = satisfaction_decor_target(venue_id)
	var decor_score: float = clampf(points / decor_target, 0.0, 1.0)

	var scfg: Dictionary = cfg.get("speed", {})
	var wait_s: float = queue_wait_seconds(arrival, serve)
	var wait_good: float = float(scfg.get("wait_good_s", 3.0))
	var wait_bad: float = maxf(wait_good + 0.001, float(scfg.get("wait_bad_s", 30.0)))
	var wait_score: float = clampf(1.0 - (wait_s - wait_good) / (wait_bad - wait_good), 0.0, 1.0)
	var tp_target: float = satisfaction_throughput_target(venue_id)
	var tp_score: float = clampf(throughput / tp_target, 0.0, 1.0)
	var queue_weight: float = clampf(float(scfg.get("queue_weight", 0.6)), 0.0, 1.0)
	var speed_score: float = queue_weight * wait_score + (1.0 - queue_weight) * tp_score
	# An empty venue has an empty queue, and an empty queue is not fast service.
	# Without this a floor with no staff would bank a full wait score for having
	# nobody standing in it.
	if throughput <= 0.0:
		speed_score = 0.0

	var rcfg: Dictionary = cfg.get("rest", {})
	var seats: int = int(rcfg.get("base_seats", 2)) + DecorSystem.venue_rest_seats(venue_id)
	var crowd: float = throughput * float(rcfg.get("dwell_seconds", 30.0))
	var seats_needed: int = maxi(1, int(ceil(crowd * float(rcfg.get("seats_per_visitor", 0.25)))))
	var rest_score: float = clampf(float(seats) / float(seats_needed), 0.0, 1.0)

	var scores := {"decor": decor_score, "speed": speed_score, "rest": rest_score}
	var score: float = 0.0
	for key in SAT_INPUTS:
		score += float(weights[key]) * float(scores[key])
	score = clampf(score / w_sum, 0.0, 1.0)

	# The input holding the player back is the biggest WEIGHTED shortfall, not the
	# lowest raw score: a 0.5 on the 40%-weight input costs more stars than a 0.3
	# on the 25% one, and pointing at the cheaper fix would be a lie.
	var limiting: String = "decor"
	var worst_loss: float = -1.0
	for key in SAT_INPUTS:
		var loss: float = float(weights[key]) * (1.0 - float(scores[key]))
		if loss > worst_loss:
			worst_loss = loss
			limiting = key

	var mult_min: float = float(cfg.get("income_mult_min", 0.5))
	var mult_max: float = float(cfg.get("income_mult_max", 2.0))
	var details := {
		"decor": "%d of %d decor points" % [int(round(points)), int(round(decor_target))],
		"speed": ("queue never clears" if wait_s >= float(scfg.get("wait_stall_s", 120.0))
			else "%.0fs wait · %s of %s/s" % [wait_s,
				_sat_rate(throughput), _sat_rate(tp_target)]),
		"rest": "%d of %d seats" % [seats, seats_needed],
	}
	var inputs: Dictionary = {}
	for key in SAT_INPUTS:
		inputs[key] = {
			"label": str(SAT_LABELS[key]),
			"score": float(scores[key]),
			"weight": float(weights[key]) / w_sum,
			"detail": str(details[key]),
		}

	var result := {
		"score": score,
		"stars": score * STARS_MAX,
		"stars_rounded": roundf(score * STARS_MAX * 2.0) / 2.0,
		"income_mult": mult_min + (mult_max - mult_min) * score,
		"inputs": inputs,
		"limiting": limiting,
		"limiting_label": str(SAT_LABELS[limiting]),
		"reason": _sat_reason(limiting, scores, details),
		"mood": _sat_mood(score),
		"queue_wait_s": wait_s,
		"throughput_per_s": throughput,
		"throughput_target": tp_target,
		"decor_points": points,
		"decor_target": decor_target,
		"seats": seats,
		"seats_needed": seats_needed,
		"crowd": crowd,
	}
	_satisfaction_cache[venue_id] = {
		"arrival": arrival,
		"serve": serve,
		"throughput": throughput,
		"decor_signature": decor_signature,
		"result": result,
	}
	return result

## Cash multiplier the rating applies to value-per-visitor. See venue_rates for
## why the rating moves the drop and not the drop rate.
func satisfaction_multiplier(venue_id: String) -> float:
	return float(venue_satisfaction(venue_id)["income_mult"])

## Crowd mood bucket for anything that draws visitors. See api notes: a floor
## renderer picks a face/emote from this without re-deriving the rating.
func satisfaction_mood(venue_id: String) -> String:
	return str(venue_satisfaction(venue_id)["mood"])

func _sat_mood(score: float) -> String:
	if score >= 0.8:
		return "delighted"
	if score >= 0.55:
		return "content"
	if score >= 0.3:
		return "restless"
	return "unhappy"

func _sat_rate(v: float) -> String:
	return ("%.1f" % v) if v < 10.0 else ("%d" % int(round(v)))

func _sat_reason(limiting: String, scores: Dictionary, details: Dictionary) -> String:
	if float(scores[limiting]) >= 0.999:
		return "The crowd loves this place."
	match limiting:
		"decor":
			return "The halls look bare — %s." % str(details["decor"])
		"speed":
			return "Queues are slow — %s." % str(details["speed"])
		_:
			return "Nowhere to sit — %s." % str(details["rest"])

func purchase_upgrade(venue_id: String, dept_id: String, track: String) -> bool:
	var def: Dictionary = DataLoader.dept_def(dept_id)
	var level: int = GameState.dept_level(venue_id, dept_id, track)
	if track == "staff":
		# Buying "staff" places a new item on the floor at level 1.
		var staff: int = GameState.dept_items(venue_id, dept_id).size()
		if staff >= int(def.get("max_staff", 99)):
			return false
		var cost_s: BigNumber = _cost(venue_id, dept_id, track, staff)
		if not GameState.spend_cash(cost_s):
			return false
		GameState.add_dept_item(venue_id, dept_id)
		_grant_rep(staff)
		EventBus.department_upgraded.emit(venue_id, dept_id, track, staff + 1)
		return true
	if level >= track_max_level(venue_id, track):
		return false
	var cost: BigNumber = _cost(venue_id, dept_id, track, level)
	if not GameState.spend_cash(cost):
		return false
	GameState.set_dept_level(venue_id, dept_id, track, level + 1)
	_grant_rep(level)
	EventBus.department_upgraded.emit(venue_id, dept_id, track, level + 1)
	return true

func _cost(venue_id: String, dept_id: String, track: String, level: int) -> BigNumber:
	var venue: Dictionary = DataLoader.get_venue(venue_id)
	return DataLoader.upgrade_cost(dept_id, track, level,
		float(venue.get("cost_mult", 1.0)), int(venue.get("cost_exp", 0)))

func _grant_rep(level: int) -> void:
	var cfg: Dictionary = DataLoader.core.get("reputation", {}).get("xp_per_upgrade", {})
	var xp: float = float(cfg.get("base", 2.0)) + float(level) * float(cfg.get("per_level", 0.25))
	GameState.add_reputation(BigNumber.from_float(xp))

## Tap: collect venue pending cash into vault + tip bonus.
func manual_collect(venue_id: String) -> BigNumber:
	var pending: BigNumber = GameState.pending_cash.get(venue_id, BigNumber.zero())
	if pending.is_zero():
		return BigNumber.zero()
	var cfg: Dictionary = DataLoader.core.get("economy", {})
	var frac: float = float(cfg.get("manual_collect_fraction", 1.0))
	var tip: float = float(cfg.get("tip_bonus_pct", 0.05))
	var amount: BigNumber = pending.scale(frac * (1.0 + tip))
	GameState.pending_cash[venue_id] = pending.sub(pending.scale(frac))
	# The station piles are a decomposition of the venue pending; a venue-wide
	# sweep empties them by the same fraction or the chips would show cash that
	# is no longer there.
	for it in GameState.dept_items(venue_id, "ticket"):
		it["pending"] = BigNumber.from_save(it.get("pending", {})).scale(1.0 - frac).to_save()
	GameState.cash = GameState.cash.add(amount)
	EventBus.manual_collect.emit(amount)
	EventBus.cash_changed.emit(GameState.cash)
	return amount

# --- Money bags ----------------------------------------------------------------
## A served visitor may leave a tip bag on the floor for the player to tap.
##
## WHY BOTH THE ODDS AND THE SIZE SCALE WITH SATISFACTION. The owner's brief was
## that visitors "drop money bags depending on how quick the service and the decor
## was". Satisfaction already composes exactly those inputs — decor, real service
## speed, rest areas — so the bag reads the star score rather than re-deriving
## them, and the decor screen's existing breakdown doubles as the explanation for
## why bags are rare. Scaling BOTH means a poor venue drops the occasional small
## bag rather than nothing at all: zero drops would read as a broken feature, and
## a player cannot learn a system that never fires.
##
## Value is denominated in VISITORS' worth of income, not currency, so it tracks
## the whole progression curve without a per-venue table to maintain.

func _bag_cfg() -> Dictionary:
	return DataLoader.core.get("money_bags", {})

## 0..1 star fraction for the current venue.
func _bag_t(venue_id: String) -> float:
	var stars: float = float(venue_satisfaction(venue_id).get("stars", 0.0))
	return clampf(stars / 5.0, 0.0, 1.0)

func bag_drop_chance(venue_id: String) -> float:
	var c: Dictionary = _bag_cfg()
	return lerpf(float(c.get("chance_min", 0.10)), float(c.get("chance_max", 0.55)),
		_bag_t(venue_id))

## What one bag is worth right now.
func bag_value(venue_id: String) -> BigNumber:
	var c: Dictionary = _bag_cfg()
	var visitors: float = lerpf(float(c.get("value_visitors_min", 6.0)),
		float(c.get("value_visitors_max", 26.0)), _bag_t(venue_id))
	var rates: Dictionary = venue_rates(venue_id)
	return (rates["value_per_visitor"] as BigNumber).scale(visitors)

func bag_lifetime() -> float:
	return float(_bag_cfg().get("lifetime_s", 14.0))

func bag_max_alive() -> int:
	return int(_bag_cfg().get("max_alive", 6))

## Should this served visitor leave a bag? Called once per serve by the floor.
func roll_bag(venue_id: String) -> bool:
	return randf() < bag_drop_chance(venue_id)

## Bank a tapped bag. A tip is FRESH cash, not a draw against pending: the pending
## pile is the sim's own ledger and taking from it would make tapping a bag
## cannibalise the porters' banking rather than reward the player for a well-run
## venue.
func collect_bag(venue_id: String, amount: BigNumber) -> BigNumber:
	if amount == null or amount.is_zero():
		return BigNumber.zero()
	GameState.cash = GameState.cash.add(amount)
	var vs: Dictionary = GameState.venue_state(venue_id)
	vs["earned_total"] = BigNumber.from_save(vs.get("earned_total", {})).add(amount).to_save()
	Analytics.log_event("money_bag_collected", {"venue": venue_id})
	EventBus.money_bag_collected.emit(venue_id, amount)
	EventBus.cash_changed.emit(GameState.cash)
	return amount

## Expedition idle insight (SPEC §6.2): accrues into capped storage; must be collected.
func insight_idle_config() -> Dictionary:
	return DataLoader.get_event("expedition").get("insight_idle",
		{"per_minute": 2.0, "cap_base": 60, "cap_per_rep_level": 5})

func insight_cap() -> BigNumber:
	var cfg: Dictionary = insight_idle_config()
	var cap: float = float(cfg.get("cap_base", 60)) + float(cfg.get("cap_per_rep_level", 5)) * GameState.rep_level()
	return BigNumber.from_float(cap)

func insight_per_second() -> BigNumber:
	if not GameState.feature_unlocked("expedition"):
		return BigNumber.zero()
	var cfg: Dictionary = insight_idle_config()
	return BigNumber.from_float(float(cfg.get("per_minute", 2.0)) / 60.0)

func tick_insight_storage(now_unix: int) -> void:
	if not GameState.feature_unlocked("expedition"):
		return
	var stored: BigNumber = BigNumber.from_save(GameState.expedition_state.get("insight_stored", {}))
	var cap: BigNumber = insight_cap()
	if stored.gte(cap):
		return
	var rate: BigNumber = insight_per_second()
	var last: int = int(GameState.expedition_state.get("last_tick", now_unix))
	var elapsed: int = ClockGuard.validate_elapsed(last, now_unix, 8 * 3600)
	if elapsed <= 0:
		GameState.expedition_state["last_tick"] = now_unix
		return
	stored = stored.add(rate.scale(float(elapsed)))
	if stored.gt(cap):
		stored = cap
	GameState.expedition_state["insight_stored"] = stored.to_save()
	GameState.expedition_state["last_tick"] = now_unix
	EventBus.insight_storage_changed.emit(stored, cap)

## Collect stored insight with a multiplier (1.0 normal, 2.0 RV, 3.0 gems). Returns granted amount.
func collect_insight(multiplier: float) -> BigNumber:
	var stored: BigNumber = BigNumber.from_save(GameState.expedition_state.get("insight_stored", {}))
	if stored.is_zero():
		return BigNumber.zero()
	var granted: BigNumber = stored.scale(multiplier)
	GameState.expedition_state["insight_stored"] = BigNumber.zero().to_save()
	GameState.add_insight(granted)
	EventBus.insight_storage_changed.emit(BigNumber.zero(), insight_cap())
	return granted
