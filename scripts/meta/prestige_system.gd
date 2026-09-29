extends RefCounted
## VenueProgression — the ONE-WAY museum ladder (SPEC §6.1/§7). No class_name; preload.
##
## The file keeps its prestige_system.gd name and its can_prestige/do_prestige/
## block_reason/next_venue_id symbols because the EventBus signals, the HUD entry
## point, the offer triggers and the analytics schema all live in files this track
## does not own. The PLAYER-FACING word is "open the next museum": this is a
## graduation to a bigger building, not a prestige reset.
##
## THE GATE. Complete the milestone chain, cap the four core operation tracks,
## and meet the current museum's installed furnishing count and decor score.
## Readiness is shown together; no premium currency or event item is required.
##
## THE MOVE IS ONE-WAY. The venue you leave is recorded in GameState.venues_closed
## and can never be current again. Nothing in the game offers a way back.
##
## WHAT CROSSES THE THRESHOLD (the screen renders this list from carry_over() and
## left_behind() below, so the copy the player reads cannot drift from what the
## code does):
##   CASH — in FULL, including the old floor's uncollected pending cash, which is
##          swept into the vault on the way out instead of being deleted. Money
##          carrying over is the whole point of the step.
##   GEMS — in full. Premium currency, some of it bought with real money;
##          confiscating it at a progression step would be indefensible.
##   INSIGHT — in full. It levels managers, and managers carry, so stranding it
##          would strand the collection it exists to serve.
##   MANAGERS — cards, levels, ranks and assignments. A collection the player
##          paid for, in gems or in time. Never touched here.
##   REPUTATION — in full. It is the account-wide unlock ladder (managers at rep
##          6, expeditions at rep 7); resetting it would re-lock earned features.
##   DECOR SET BONUSES — DecorSystem.owned_anywhere() is cross-venue, so pieces
##          bought at a closed museum keep paying into their set multiplier.
##          Money spent on decor is never destroyed, only its placement is.
##
## WHAT STAYS WITH THE BUILDING:
##   PLACED DECOR — pieces are fixed to the hall they were installed in. This is
##          what gives the visitor rating teeth again: a new museum opens bare,
##          rates near zero on decor and rest areas, and re-dressing it is what
##          the carried-over cash is for.
##   DEPARTMENT LEVELS — new building, new staff, level 1 everywhere.
##   QUESTS AND MILESTONES — the new venue runs its own chain.
##
## DIFFICULTY at the new venue is data that already exists. venues.json carries
## cost_mult / cost_exp, which Economy._cost applies to every upgrade price, and
## Economy's satisfaction decor + throughput targets grow with venue order. No
## parallel scaling system was invented.
##
## THE OLD VENUE IS FROZEN, NOT WIPED. Its departments, decor, milestones and
## lifetime totals are left exactly as the player built them, as a record of the
## museum they ran. The previous code reset them to level 1, which only made
## sense while the step was called a prestige; nothing reads a closed venue's
## rates, so the reset destroyed history and bought nothing.
##
## WITHIN-VENUE PRESTIGE: none exists in this game, and none was added. Stacking
## a second reset loop on a one-way ladder would give the player two competing
## "should I reset now?" decisions and blur the single clear gate above.

const QuestSystem = preload("res://scripts/meta/quest_system.gd")
const DecorSystem = preload("res://scripts/meta/decor_system.gd")
const WingSystem = preload("res://scripts/meta/wing_system.gd")

static func config() -> Dictionary:
	return DataLoader.core.get("venue_progression", {})

# ------------------------------------------------------------------- the gate

## Milestones needed to open the next museum. Clamped to the chain the venue
## actually has, so a tuning value larger than the data can never lock the ladder.
static func milestones_required(venue_id: String) -> int:
	var want: int = int(config().get("milestones_required", 8))
	var defs: Array = DataLoader.milestones.get(venue_id, [])
	if defs.is_empty():
		return want
	return mini(want, defs.size())

static func milestones_done(venue_id: String) -> int:
	return GameState.venue_state(venue_id).get("milestones", []).size()

static func milestone_gate_met(venue_id: String) -> bool:
	var need: int = milestones_required(venue_id)
	return need > 0 and milestones_done(venue_id) >= need

## The four tracks that physically carry one visitor through the operation.
## Requiring these—not every optional value/staff purchase—makes READY mean the
## venue was actually built, while leaving room for different player builds.
static func core_tracks() -> Array:
	return [
		["promotions", "speed", "Promotions Speed"],
		["ticket", "speed", "Ticket Speed"],
		["archive", "speed", "Archive Speed"],
		["gallery", "value", "Gallery Value"],
	]

static func operations_required(venue_id: String) -> int:
	if not bool(config().get("require_core_tracks_capped", true)):
		return 0
	return int(DataLoader.get_venue(venue_id).get("track_level_cap", 100)) * core_tracks().size()

static func operations_done(venue_id: String) -> int:
	var cap: int = int(DataLoader.get_venue(venue_id).get("track_level_cap", 100))
	var done := 0
	for track in core_tracks():
		done += mini(GameState.dept_level(venue_id, str(track[0]), str(track[1])), cap)
	return done

static func operations_progress(venue_id: String) -> float:
	var required := operations_required(venue_id)
	return 1.0 if required <= 0 else clampf(float(operations_done(venue_id)) / float(required), 0.0, 1.0)

static func operations_met(venue_id: String) -> bool:
	return operations_done(venue_id) >= operations_required(venue_id)

## Furnishing is local to the museum and must remain installed. Premium and
## event pieces can contribute, but every target is reachable with cash designs.
static func decor_required(venue_id: String) -> int:
	return ceili(DecorSystem.slots_total(venue_id) * float(config().get("decor_slot_fraction", .5)))

static func decor_points_required(venue_id: String) -> float:
	return decor_required(venue_id) * float(config().get("decor_points_per_required_piece", 4.0))

static func decor_done(venue_id: String) -> int:
	var valid: Dictionary = {}
	for did in GameState.venue_state(venue_id).get("decor", {}).values():
		if not DataLoader.get_decor(str(did)).is_empty():valid[str(did)] = true
	return valid.size()

static func decor_progress(venue_id: String) -> float:
	var pieces := clampf(float(decor_done(venue_id)) / maxf(decor_required(venue_id), 1), 0, 1)
	var points := clampf(DecorSystem.venue_decor_points(venue_id) / maxf(decor_points_required(venue_id), 1), 0, 1)
	return minf(pieces, points)

static func decor_met(venue_id: String) -> bool:
	return decor_done(venue_id) >= decor_required(venue_id) and DecorSystem.venue_decor_points(venue_id) + .00001 >= decor_points_required(venue_id)

static func decor_summary(venue_id: String) -> String:
	return "%d / %d furnishings · %d / %d decor points" % [decor_done(venue_id), decor_required(venue_id), roundi(DecorSystem.venue_decor_points(venue_id)), roundi(decor_points_required(venue_id))]

static func readiness_progress(venue_id: String) -> float:
	var partial := clampf(float(GameState.venue_state(venue_id).get("progress", 0.0)), 0, 1)
	var milestones := clampf((float(milestones_done(venue_id)) + partial) / maxf(milestones_required(venue_id), 1), 0, 1)
	var parts := milestones + operations_progress(venue_id) + decor_progress(venue_id)
	var wings: int = WingSystem.wings(venue_id).size()
	if wings == 0:
		return parts / 3.0
	return (parts + float(WingSystem.open_count(venue_id)) / float(wings)) / 4.0

## Every wing (upper floors, gilded facade) renovated: the building is complete.
static func wings_met(venue_id: String) -> bool:
	return WingSystem.all_open(venue_id)

static func gate_met(venue_id: String) -> bool:
	return milestone_gate_met(venue_id) and operations_met(venue_id) and decor_met(venue_id) and wings_met(venue_id)

## "" when the player may move on, otherwise the player-facing reason.
static func block_reason() -> String:
	var vid: String = GameState.current_venue
	if not milestone_gate_met(vid):
		return "%d of %d milestones done" % [milestones_done(vid), milestones_required(vid)]
	if not operations_met(vid):
		var cap: int = int(DataLoader.get_venue(vid).get("track_level_cap", 100))
		for track in core_tracks():
			if GameState.dept_level(vid, str(track[0]), str(track[1])) < cap:
				return "Operations %d%% — upgrade %s to Lv.%d" % [
					int(round(operations_progress(vid) * 100.0)), str(track[2]), cap]
	if not decor_met(vid):
		return "Furnish this museum: " + decor_summary(vid)
	if not wings_met(vid):
		return "Renovate %s (%d / %d wings open)" % [str(WingSystem.next_wing(vid).get("name", "")),
			WingSystem.open_count(vid), WingSystem.wings(vid).size()]
	if next_venue_id() == "":
		return "This is the final museum"
	return ""

static func can_graduate() -> bool:
	return block_reason() == ""

## Legacy name, kept for callers outside this track.
static func can_prestige() -> bool:
	return can_graduate()

static func next_venue_id() -> String:
	var order: Array = DataLoader.venue_order()
	var idx: int = order.find(GameState.current_venue)
	if idx < 0 or idx + 1 >= order.size():
		return ""
	return str(order[idx + 1])

# -------------------------------------------------------------------- the move

## Open the next museum. One-way; see the header for what carries.
static func graduate() -> bool:
	if not can_graduate():
		return false
	var from_vid: String = GameState.current_venue
	var to_vid: String = next_venue_id()
	# Cash carries in FULL, so sweep the floor before the doors are locked. The
	# old code erased pending_cash, which silently confiscated whatever had
	# accrued since the player's last tap.
	var swept: BigNumber = pending_sweep(from_vid)
	if bool(config().get("bank_pending_cash_on_move", true)) and not swept.is_zero():
		GameState.add_cash(swept)
	GameState.pending_cash.erase(from_vid)
	GameState.pending_cash.erase(to_vid)
	# The venue is left exactly as built (see header) and marked shut for good.
	GameState.close_venue(from_vid)
	if to_vid not in GameState.venues_unlocked:
		GameState.venues_unlocked.append(to_vid)
	GameState.current_venue = to_vid
	GameState.venue_state(to_vid)  # ensure fresh state exists
	QuestSystem.ensure_active_quests(to_vid)
	EventBus.prestige_performed.emit(from_vid, to_vid)
	Analytics.log_event("venue_opened", {"from": from_vid, "to": to_vid,
		"swept_cash": swept.to_notation(),
		"decor_left": DecorSystem.slots_used(from_vid),
		"milestones": milestones_done(from_vid)})
	return true

## Legacy name, kept for callers outside this track.
static func do_prestige() -> bool:
	return graduate()

## Uncollected floor cash that graduate() would sweep into the vault.
static func pending_sweep(venue_id: String) -> BigNumber:
	var pending: Variant = GameState.pending_cash.get(venue_id, null)
	if pending == null:
		return BigNumber.zero()
	return pending as BigNumber

# ---------------------------------------------------------- selling the move

## How much richer a visitor is at `to` than at `from`, as a plain ratio.
static func value_ratio(from_vid: String, to_vid: String) -> float:
	var a: Dictionary = DataLoader.get_venue(from_vid)
	var b: Dictionary = DataLoader.get_venue(to_vid)
	var m: float = float(b.get("base_value_m", 1.0)) / maxf(float(a.get("base_value_m", 1.0)), 0.0001)
	return m * pow(10.0, int(b.get("base_value_e", 0)) - int(a.get("base_value_e", 0)))

## How much steeper the upgrade curve is at `to`. This IS the difficulty step,
## and it is read straight off venues.json cost_mult/cost_exp — the same numbers
## Economy._cost already charges — so the screen cannot promise a different game
## from the one the player is about to play.
static func cost_ratio(from_vid: String, to_vid: String) -> float:
	var a: Dictionary = DataLoader.get_venue(from_vid)
	var b: Dictionary = DataLoader.get_venue(to_vid)
	var m: float = float(b.get("cost_mult", 1.0)) / maxf(float(a.get("cost_mult", 1.0)), 0.0001)
	return m * pow(10.0, int(b.get("cost_exp", 0)) - int(a.get("cost_exp", 0)))

## Compact multiplier text: "1.5x", "750x", then "1.5e6x" past human range.
## Built by hand because GDScript's String % has no %e conversion.
static func ratio_text(ratio: float) -> String:
	if ratio >= 100000.0:
		var exp10: int = int(floor(log(ratio) / log(10.0)))
		return "%.1fe%dx" % [ratio / pow(10.0, exp10), exp10]
	if ratio >= 100.0:
		return "%dx" % int(round(ratio))
	if ratio >= 10.0:
		return "%.0fx" % ratio
	return "%.1fx" % ratio

## Rows for the "you take this with you" panel: {icon, label, detail}.
static func carry_over() -> Array:
	var vid: String = GameState.current_venue
	var swept: BigNumber = pending_sweep(vid)
	var cash_detail: String = GameState.cash.to_notation()
	if not swept.is_zero():
		cash_detail += " + %s still on the floor" % swept.to_notation()
	var owned: int = 0
	var cards: int = 0
	for mid in GameState.managers_state.keys():
		var n: int = int(GameState.managers_state[mid].get("cards", 0))
		cards += n
		if n > 0:
			owned += 1
	return [
		{"icon": "cash", "label": "Every coin you own", "detail": cash_detail},
		{"icon": "gems", "label": "Gems", "detail": "%d" % GameState.gems},
		{"icon": "insight", "label": "Insight", "detail": GameState.insight.to_notation()},
		{"icon": "medal", "label": "Your managers", "detail":
			"%d hired, %d cards — levels and posts intact" % [owned, cards]},
		{"icon": "trophy", "label": "Reputation", "detail":
			"Level %d, and everything it unlocked" % GameState.rep_level()},
		{"icon": "star", "label": "Decor set bonuses", "detail":
			"Pieces you bought keep counting, wherever they stand"},
	]

## Rows for the "this stays here" panel: {icon, label, detail}.
static func left_behind() -> Array:
	var vid: String = GameState.current_venue
	var venue: Dictionary = DataLoader.get_venue(vid)
	var used: int = DecorSystem.slots_used(vid)
	var total: int = DecorSystem.slots_total(vid)
	return [
		{"icon": "home", "label": "The decor you installed", "detail":
			"%d of %d pieces stay bolted to %s" % [used, total, str(venue.get("name", vid))]},
		{"icon": "arrow_up", "label": "Department levels", "detail":
			"New building, new staff — every track restarts at 1"},
		{"icon": "star_outline", "label": "Your visitor rating", "detail":
			"Bare halls and no seating rate low. Earn the stars back"},
	]

## What the next museum offers. {} at the end of the ladder.
static func next_venue_preview() -> Dictionary:
	var to_vid: String = next_venue_id()
	if to_vid == "":
		return {}
	var from_vid: String = GameState.current_venue
	var a: Dictionary = DataLoader.get_venue(from_vid)
	var b: Dictionary = DataLoader.get_venue(to_vid)
	return {
		"id": to_vid,
		"name": str(b.get("name", to_vid)),
		"desc": str(b.get("desc", "")),
		"value_ratio": value_ratio(from_vid, to_vid),
		"cost_ratio": cost_ratio(from_vid, to_vid),
		"decor_slots": int(b.get("decor_slots", 0)),
		"decor_slots_delta": int(b.get("decor_slots", 0)) - int(a.get("decor_slots", 0)),
		"order": int(b.get("order", 0)),
		"total": DataLoader.venue_order().size(),
	}
