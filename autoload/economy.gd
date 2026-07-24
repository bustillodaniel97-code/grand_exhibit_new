extends Node
## Economy — fixed-step venue simulation (choke-point model). See docs/SPEC.md §3 SIM MODEL.
## pending cash = generated at ticket windows, capped by min(arrival, serve);
## banked cash = min(pending rate, archive transport rate). Banked goes straight to vault.

var _accum: float = 0.0
var _signal_throttle: float = 0.0
var _served_win: BigNumber = BigNumber.zero()
var _banked_win: BigNumber = BigNumber.zero()

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

func _tick(dt: float) -> void:
	var vid: String = GameState.current_venue
	var rates: Dictionary = venue_rates(vid)
	var pending_rate: BigNumber = rates["pending_per_s"]
	var banked_rate: BigNumber = rates["banked_per_s"]
	var pending: BigNumber = GameState.pending_cash.get(vid, BigNumber.zero())
	_served_win = _served_win.add(pending_rate.scale(dt))
	pending = pending.add(pending_rate.scale(dt)).sub(banked_rate.scale(dt))
	GameState.pending_cash[vid] = pending
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
		var rank: int = clampi(int(st.get("rank", 1)), 1, 4)
		var rank_mults: Array = def.get("rank_mults", [1.0, 1.5, 2.25, 3.5])
		mult *= 1.0 + float(def.get("base_mult", 0.03)) * float(st.get("level", 1)) * float(rank_mults[rank - 1])
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

func venue_rates(venue_id: String) -> Dictionary:
	# SPEC §3 SIM MODEL (binding):
	#   arrival_per_s   = promotions.staff * promotions.speed_stat
	#   serve_per_s     = ticket.staff * ticket.speed_stat
	#   transport_per_s = archive.staff * archive.speed_stat     (visitor-units/s)
	#   value_per_visitor = venue.base_value * ticket.value_stat * (1 + gallery_bonus) * income_mult
	#   pending_per_s = min(arrival, serve) * value; banked = min(pending, transport * value)
	var venue: Dictionary = DataLoader.get_venue(venue_id)
	var vs: Dictionary = GameState.venue_state(venue_id)
	var arrival: float = 0.0
	var serve: float = 0.0
	var transport: float = 0.0
	for dept_id in ["promotions", "ticket", "archive"]:
		var staff: int = int(vs.get("depts", {}).get(dept_id, {}).get("staff", 1))
		var spd: float = dept_stat(venue_id, dept_id, "speed")
		match dept_id:
			"promotions": arrival = staff * spd
			"ticket": serve = staff * spd
			"archive": transport = staff * spd
	var gallery_staff: int = int(vs.get("depts", {}).get("gallery", {}).get("staff", 0))
	var gallery_bonus: float = gallery_staff * dept_stat(venue_id, "gallery", "value")
	var base_value := BigNumber.from_parts(
		float(venue.get("base_value_m", 2.0)), int(venue.get("base_value_e", 0)))
	var value_per_visitor: BigNumber = base_value.scale(
		dept_stat(venue_id, "ticket", "value") * (1.0 + gallery_bonus) * income_multiplier(venue_id))
	var effective_visitors: float = minf(arrival, serve)
	var choke_id: String = "promotions" if arrival <= serve else "ticket"
	var pending_per_s: BigNumber = value_per_visitor.scale(effective_visitors)
	var transport_cash: BigNumber = value_per_visitor.scale(transport)
	var banked_per_s: BigNumber = pending_per_s if pending_per_s.lt(transport_cash) else transport_cash
	if transport_cash.lt(pending_per_s):
		choke_id = "archive"
	return {
		"arrival_per_s": arrival, "serve_per_s": serve, "transport_per_s": transport,
		"value_per_visitor": value_per_visitor, "effective_visitors_per_s": effective_visitors,
		"pending_per_s": pending_per_s, "banked_per_s": banked_per_s, "choke_id": choke_id,
		"gallery_bonus": gallery_bonus,
	}

func current_cash_per_second() -> BigNumber:
	return venue_rates(GameState.current_venue)["banked_per_s"]

func purchase_upgrade(venue_id: String, dept_id: String, track: String) -> bool:
	var def: Dictionary = DataLoader.dept_def(dept_id)
	var level: int = GameState.dept_level(venue_id, dept_id, track)
	if track == "staff":
		var staff: int = int(GameState.venue_state(venue_id)["depts"][dept_id]["staff"])
		if staff >= int(def.get("max_staff", 99)):
			return false
		var cost_s: BigNumber = _cost(venue_id, dept_id, track, staff)
		if not GameState.spend_cash(cost_s):
			return false
		GameState.venue_state(venue_id)["depts"][dept_id]["staff"] = staff + 1
		_grant_rep(staff)
		EventBus.department_upgraded.emit(venue_id, dept_id, track, staff + 1)
		return true
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
	GameState.cash = GameState.cash.add(amount)
	EventBus.manual_collect.emit(amount)
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
