extends SceneTree
## Venue progression — the ONE-WAY museum ladder (SPEC §6.1/§7).
## Covers the gate, the move, what carries and what stays, the difficulty step at
## the new venue, and the fact that a new museum opens on a LOW visitor rating.
## Run: godot --headless --path <repo> -s tests/meta/test_venue_progression.gd
##
## GODOT 4.4 -s NOTE (same rule as test_meta.gd): this file must not reference
## autoload identifiers or preload autoload-referencing scripts at parse time.
## Autoloads are fetched from root in _initialize(); meta scripts are load()-ed.

var failures: int = 0

var EB: Node     # EventBus
var DL: Node     # DataLoader
var GS: Node     # GameState
var ECON: Node   # Economy
var PS: GDScript # scripts/meta/prestige_system.gd
var DS: GDScript # scripts/meta/decor_system.gd

func check(cond: bool, msg: String) -> void:
	if cond:
		print("PASS: ", msg)
	else:
		failures += 1
		printerr("FAIL: ", msg)

func _initialize() -> void:
	EB = root.get_node("EventBus")
	DL = root.get_node("DataLoader")
	GS = root.get_node("GameState")
	ECON = root.get_node("Economy")
	DL.reload_all()
	PS = load("res://scripts/meta/prestige_system.gd")
	DS = load("res://scripts/meta/decor_system.gd")
	check(PS != null and PS.can_instantiate(), "prestige_system.gd compiles")
	_test_gate()
	_test_move_is_one_way()
	_test_difficulty_step()
	_test_new_venue_rates_low()
	_test_keep_and_leave_copy()
	_test_final_venue()
	print("VENUE PROGRESSION TESTS DONE — failures: %d" % failures)
	quit(1 if failures > 0 else 0)

## Fill the milestone chain without running 400 quest batches.
func _complete_chain(vid: String, complete_operations: bool = true) -> void:
	var ids: Array = []
	for ms in DL.milestones.get(vid, []):
		ids.append(str(ms.get("id", "")))
	GS.venue_state(vid)["milestones"] = ids
	if complete_operations:
		_furnish(vid)
		var cap: int = int(DL.get_venue(vid).get("track_level_cap", 100))
		for spec in [["promotions", "speed"], ["ticket", "speed"],
				["archive", "speed"], ["gallery", "value"]]:
			GS.set_dept_level(vid, str(spec[0]), str(spec[1]), cap)

func _furnish(vid: String) -> void:
	for did in DL.decor:
		var def: Dictionary=DL.decor[did]
		if int(def.get("cost_gems",0))>0 or bool(def.get("event_exclusive",false)):continue
		if PS.decor_met(vid):break
		DS.grant_event_decor(did,vid)

# ------------------------------------------------------------------- the gate

func _test_gate() -> void:
	print("-- gate --")
	GS.reset_to_new_game()
	var vid: String = GS.current_venue
	check(PS.milestones_required(vid) == 4, "intro venue requires its authored 4 milestones")
	check(PS.milestones_done(vid) == 0, "fresh venue has none done")
	check(not PS.can_graduate(), "cannot move on at 0 milestones")
	check(PS.block_reason() == "0 of 4 milestones done",
		"block_reason counts progress (got '%s')" % PS.block_reason())
	check(PS.graduate() == false, "graduate() refused while gated")
	check(GS.current_venue == vid, "refused move did not switch venue")
	# Partway through the chain the reason still counts, so the screen can show it.
	GS.venue_state(vid)["milestones"] = ["wp_m1", "wp_m2", "wp_m3"]
	check(PS.block_reason() == "3 of 4 milestones done", "reason tracks partial progress")
	check(not GS.feature_unlocked("prestige"), "feature gate closed at 3 of 4")
	_complete_chain(vid, false)
	check(not PS.can_graduate(), "milestones alone do not bypass the operating build")
	check("Operations" in PS.block_reason(), "block reason points to the unfinished operation")
	var cap: int = int(DL.get_venue(vid).get("track_level_cap", 100))
	for spec in [["promotions", "speed"], ["ticket", "speed"],
			["archive", "speed"], ["gallery", "value"]]:
		GS.set_dept_level(vid, str(spec[0]), str(spec[1]), cap)
	check(not PS.can_graduate(), "operations and milestones still require furnishing")
	check("Furnish" in PS.block_reason(), "furnishing requirement is explicit")
	_furnish(vid)
	check(PS.can_graduate(), "gate opens on the furnished full chain")
	check(GS.feature_unlocked("prestige") and GS.feature_unlocked("graduation"),
		"feature_unlocked agrees with PrestigeSystem")

# -------------------------------------------------------------------- the move

func _test_move_is_one_way() -> void:
	print("-- the move --")
	GS.reset_to_new_game()
	var from_vid: String = GS.current_venue
	_complete_chain(from_vid)
	# A build worth remembering, plus uncollected cash on the floor.
	var from_cap: int = int(DL.get_venue(from_vid).get("track_level_cap", 100))
	GS.set_dept_level(from_vid, "ticket", "speed", from_cap)
	GS.venue_state(from_vid)["decor"]["0"] = "oak_bench"
	GS.add_cash(BigNumber.from_parts(4.0, 4))
	GS.add_gems(31)
	GS.add_insight(BigNumber.from_float(500.0))
	GS.pending_cash[from_vid] = BigNumber.from_float(2500.0)
	var cash_pre: BigNumber = GS.cash.copy()
	check(PS.graduate(), "graduate() succeeded")
	var to_vid: String = GS.current_venue
	check(to_vid == "copper_kettle", "advanced to the next venue in order")
	# Cash carries in FULL, floor included.
	check(GS.cash.eq(cash_pre.add(BigNumber.from_float(2500.0))),
		"pending floor cash swept into the vault instead of deleted")
	check(GS.gems == 31 + 25, "gems untouched (25 starter + 31)")
	check(GS.insight.eq(BigNumber.from_float(500.0)), "insight untouched")
	# One-way.
	check(GS.venue_is_closed(from_vid), "%s recorded closed" % from_vid)
	check(from_vid in GS.venues_closed, "venues_closed holds the id")
	check(not GS.venue_is_closed(to_vid), "the venue you moved into is open")
	# Frozen, not wiped.
	check(GS.dept_level(from_vid, "ticket", "speed") == from_cap,
		"closed venue keeps the build the player paid for")
	check(str(GS.venue_state(from_vid)["decor"].get("0", "")) == "oak_bench",
		"closed venue keeps its installed decor")
	# The new hall is bare.
	check(GS.venue_state(to_vid)["decor"].is_empty(), "new venue has no decor")
	check(GS.dept_level(to_vid, "ticket", "speed") == 1, "new venue departments at level 1")
	check(DS.venue_rest_seats(to_vid) == 0, "new venue has no rest seating")

# --------------------------------------------------------------- the difficulty

func _test_difficulty_step() -> void:
	print("-- difficulty step --")
	GS.reset_to_new_game()
	var a: String = GS.current_venue
	var b: String = PS.next_venue_id()
	# The preview must quote the SAME curve Economy actually charges, or the
	# screen is selling a different game from the one behind the door.
	var promised: float = PS.cost_ratio(a, b)
	var real_a: float = ECON._cost(a, "ticket", "speed", 1).to_float_approx()
	var real_b: float = ECON._cost(b, "ticket", "speed", 1).to_float_approx()
	var charged: float = real_b / maxf(real_a, 0.0001)
	check(absf(charged - promised) / promised < 0.001,
		"cost_ratio %.1f matches the charged ratio %.1f" % [promised, charged])
	check(promised > 1.0, "upgrades really are dearer at the next venue (%.0fx)" % promised)
	# Every hop must step BOTH dials up. Later museums deliberately charge more
	# than their starting visitor-value jump: their larger track caps are the
	# campaign's long tail, and the scripted pacing suite proves it remains
	# reachable rather than treating a high multiplier as sufficient evidence.
	var order: Array = DL.venue_order()
	var total_value: float = 1.0
	var total_cost: float = 1.0
	for i in range(order.size() - 1):
		var lo: String = str(order[i])
		var hi: String = str(order[i + 1])
		var v: float = PS.value_ratio(lo, hi)
		var c: float = PS.cost_ratio(lo, hi)
		check(v > 1.0 and c > 1.0, "%s -> %s steps up both value (%.0fx) and cost (%.0fx)"
			% [lo, hi, v, c])
		total_value *= v
		total_cost *= c
	var runway_ratio: float = total_cost / maxf(total_value, 1.0)
	check(runway_ratio > 1.0 and runway_ratio <= 10000.0,
		"the authored long-tail premium stays bounded (%.0fx cost/value)" % runway_ratio)
	check(PS.ratio_text(1.5) == "1.5x" and PS.ratio_text(750.0) == "750x"
		and PS.ratio_text(2.5e6) == "2.5e6x", "ratio_text reads as a multiplier at every scale")
	var preview: Dictionary = PS.next_venue_preview()
	check(str(preview.get("id", "")) == b and str(preview.get("name", "")) != "",
		"next_venue_preview names the next museum")
	check(int(preview.get("decor_slots", 0)) > 0, "preview quotes the empty decor slots")

func _test_new_venue_rates_low() -> void:
	print("-- a new museum opens on a low rating --")
	GS.reset_to_new_game()
	var vid: String = GS.current_venue
	# Dress and staff the first museum properly.
	for dept in ["promotions", "ticket", "archive", "gallery"]:
		GS.set_dept_level(vid, dept, "speed", 14)
		GS.set_dept_level(vid, dept, "value", 10)
		GS.venue_state(vid)["depts"][dept]["staff"] = 5
	GS.venue_state(vid)["decor"] = {"0": "oak_bench", "1": "brass_fountain", "2": "marble_bust"}
	var before: float = float(ECON.venue_satisfaction(vid)["score"])
	_complete_chain(vid)
	check(PS.graduate(), "moved to the next museum")
	var after: float = float(ECON.venue_satisfaction(GS.current_venue)["score"])
	check(after < before, "new venue rates lower (%.3f -> %.3f)" % [before, after])
	check(after >= 0.0 and after <= 1.0, "new venue score in range (%.3f)" % after)
	var sat: Dictionary = ECON.venue_satisfaction(GS.current_venue)
	check(float(sat["decor_points"]) == 0.0, "new venue scores zero decor points")
	check(float(sat["decor_target"]) > 0.0, "new venue still has a decor target to hit")

# ------------------------------------------------------------------ the screen

func _test_keep_and_leave_copy() -> void:
	print("-- keep / leave lists --")
	GS.reset_to_new_game()
	var vid: String = GS.current_venue
	GS.venue_state(vid)["decor"]["0"] = "oak_bench"
	GS.pending_cash[vid] = BigNumber.from_float(1234.0)
	var keep: Array = PS.carry_over()
	var leave: Array = PS.left_behind()
	check(keep.size() >= 5, "carry_over lists every kept thing (%d rows)" % keep.size())
	check(leave.size() >= 2, "left_behind lists what stays (%d rows)" % leave.size())
	var keep_labels: String = ""
	for row in keep:
		check(row.has("icon") and row.has("label") and row.has("detail"),
			"carry row has icon/label/detail")
		keep_labels += str(row["label"]).to_lower() + "|"
	check("gems" in keep_labels and "managers" in keep_labels and "reputation" in keep_labels,
		"gems, managers and reputation are all promised as kept")
	# The cash row must mention the floor sweep, since that is the surprising part.
	check("still on the floor" in str(keep[0]["detail"]),
		"cash row names the pending cash it will sweep")
	var leave_labels: String = ""
	for row in leave:
		leave_labels += str(row["label"]).to_lower() + "|"
	check("decor" in leave_labels and "rating" in leave_labels,
		"decor and the rating are named as left behind")

func _test_final_venue() -> void:
	print("-- final venue --")
	GS.reset_to_new_game()
	var order: Array = DL.venue_order()
	var last: String = str(order[order.size() - 1])
	GS.current_venue = last
	_complete_chain(last)
	check(PS.next_venue_id() == "", "no venue after the last")
	check(PS.block_reason() == "This is the final museum", "final venue says so plainly")
	check(not PS.can_graduate(), "cannot move past the final museum")
	check(PS.next_venue_preview().is_empty(), "no preview at the end of the ladder")
	check(PS.graduate() == false, "graduate() refused at the final museum")
