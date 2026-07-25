extends SceneTree
## test_satisfaction.gd — venue rating: the maths, the income effect, the edges.
## Run: godot --headless --path <repo> -s tests/core/test_satisfaction.gd
##
## Like test_meta.gd this file must not touch autoload identifiers at parse time:
## the engine binds them only after this entry script compiles. Everything runs
## in _initialize() off root.get_node().

var failures: int = 0

const V1 := "whispering_pines"
const V6 := "aurora_world"

var DL: Node    # DataLoader
var GS: Node    # GameState
var EC: Node    # Economy
var SS: Node    # SaveSystem
var DS: GDScript

func check(cond: bool, msg: String) -> void:
	if cond:
		print("  PASS ", msg)
	else:
		failures += 1
		printerr("  FAIL ", msg)

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	DL = root.get_node("DataLoader")
	GS = root.get_node("GameState")
	EC = root.get_node("Economy")
	SS = root.get_node("SaveSystem")
	DS = load("res://scripts/meta/decor_system.gd")
	DL.reload_all()

	_test_config()
	_test_fresh_venue_is_low()
	_test_weighted_sum()
	_test_decor_input()
	_test_speed_input_uses_real_rates()
	_test_rest_input()
	_test_income_effect()
	_test_boundaries()
	_test_limiting_input()
	_test_venue_difficulty_step()
	_test_derived_not_persisted()

	print("RESULT: ", "ALL PASS" if failures == 0 else "%d FAILURES" % failures)
	quit(0 if failures == 0 else 1)

# ----------------------------------------------------------------- config
func _test_config() -> void:
	print("-- config --")
	var cfg: Dictionary = EC.satisfaction_config()
	check(not cfg.is_empty(), "balance_core.json has a satisfaction block")
	var w: Dictionary = cfg.get("weights", {})
	var sum: float = float(w.get("decor", 0.0)) + float(w.get("speed", 0.0)) + float(w.get("rest", 0.0))
	check(is_equal_approx(sum, 1.0), "weights sum to 1.0 (got %f)" % sum)
	check(float(cfg.get("income_mult_min", 0.0)) < 1.0, "min rating multiplier is a penalty")
	check(float(cfg.get("income_mult_max", 0.0)) > 1.5, "max rating multiplier is a real lever")
	var seat_pieces: int = 0
	for did in DL.decor.keys():
		if DS.piece_rest_seats(str(did)) > 0:
			seat_pieces += 1
	check(seat_pieces >= 5, "decor.json ships rest-area pieces (%d)" % seat_pieces)

# ----------------------------------------------------- a new venue starts LOW
func _test_fresh_venue_is_low() -> void:
	print("-- a fresh venue rates low (the difficulty step) --")
	GS.reset_to_new_game()
	for vid in [V1, V6]:
		var s: Dictionary = EC.venue_satisfaction(vid)
		check(float(s["stars"]) < 2.5, "%s fresh rating below 2.5 stars (%.2f)" % [vid, s["stars"]])
		check(float(s["inputs"]["decor"]["score"]) == 0.0, "%s fresh decor score 0 (no pieces)" % vid)
		check(str(s["limiting"]) == "decor", "%s fresh limiting input is decor" % vid)
	# The floor is not punitive on day one: a brand-new save must not open with a
	# below-1.0 income multiplier, or the very first tick reads as a nerf.
	var mult: float = float(EC.venue_satisfaction(V1)["income_mult"])
	check(mult >= 0.95 and mult <= 1.05, "venue 1 new-game multiplier is ~x1.00 (got %.4f)" % mult)

# --------------------------------------------------- the weighted-sum maths
func _test_weighted_sum() -> void:
	print("-- score is the weighted sum of its three inputs --")
	GS.reset_to_new_game()
	var s: Dictionary = EC.venue_satisfaction(V1)
	var w: Dictionary = EC.satisfaction_config().get("weights", {})
	var expected: float = (
		float(w["decor"]) * float(s["inputs"]["decor"]["score"])
		+ float(w["speed"]) * float(s["inputs"]["speed"]["score"])
		+ float(w["rest"]) * float(s["inputs"]["rest"]["score"]))
	check(absf(float(s["score"]) - expected) < 0.0001,
		"score == w.decor*d + w.speed*s + w.rest*r (%.5f vs %.5f)" % [s["score"], expected])
	check(absf(float(s["stars"]) - float(s["score"]) * 5.0) < 0.0001, "stars == score * 5")
	var cfg: Dictionary = EC.satisfaction_config()
	var lo: float = float(cfg["income_mult_min"])
	var hi: float = float(cfg["income_mult_max"])
	check(absf(float(s["income_mult"]) - (lo + (hi - lo) * float(s["score"]))) < 0.0001,
		"income_mult interpolates min..max linearly in score")

# ---------------------------------------------------------------- DECOR input
func _test_decor_input() -> void:
	print("-- decor input reads what is actually placed --")
	GS.reset_to_new_game()
	GS.add_cash(BigNumber.from_parts(1.0, 9))
	var before: Dictionary = EC.venue_satisfaction(V1)
	check(float(before["decor_points"]) == 0.0, "0 decor points with empty slots")
	GS.add_gems(400)
	check(DS.buy_decor(V1, "crystal_chandelier"), "buy crystal_chandelier")
	var after: Dictionary = EC.venue_satisfaction(V1)
	check(float(after["decor_points"]) > float(before["decor_points"]), "placing a piece adds decor points")
	check(float(after["inputs"]["decor"]["score"]) > float(before["inputs"]["decor"]["score"]),
		"decor score rises with points")
	# Points default to the piece's income bonus in percent; rest-area pieces override.
	check(absf(DS.piece_decor_points("crystal_chandelier") - 10.0) < 0.001,
		"chandelier (+10% income) defaults to 10 decor points")
	check(absf(DS.piece_decor_points("visitor_benches") - 3.0) < 0.001,
		"visitor_benches uses its explicit decor_score of 3")
	# Overshooting the target clamps at 1.0 rather than banking spare credit.
	var vs: Dictionary = GS.venue_state(V1)
	for i in range(20):
		vs["decor"][str(100 + i)] = "crystal_chandelier"
	var maxed: Dictionary = EC.venue_satisfaction(V1)
	check(float(maxed["decor_points"]) > float(maxed["decor_target"]), "points now exceed target")
	check(is_equal_approx(float(maxed["inputs"]["decor"]["score"]), 1.0), "decor score clamps at 1.0")

# ---------------------------------------------------------------- SPEED input
func _test_speed_input_uses_real_rates() -> void:
	print("-- speed input is built from the real service rates --")
	GS.reset_to_new_game()
	var flows: Dictionary = EC.venue_flows(V1)
	var arrival: float = float(flows["arrival_per_s"])
	var serve: float = float(flows["serve_per_s"])
	var s: Dictionary = EC.venue_satisfaction(V1)
	# M/M/1 Wq = rho / (mu - lambda) computed off the same numbers the sim banks with.
	var expected_wait: float = (arrival / serve) / (serve - arrival)
	check(absf(float(s["queue_wait_s"]) - expected_wait) < 0.001,
		"queue wait == M/M/1 Wq from live rates (%.3fs vs %.3fs)" % [s["queue_wait_s"], expected_wait])
	check(absf(float(s["throughput_per_s"]) - float(flows["effective_visitors_per_s"])) < 0.0001,
		"throughput == min(arrival, serve), the sim's own effective visitors")

	# Faster windows -> shorter wait -> better speed score.
	var slow: float = float(s["inputs"]["speed"]["score"])
	GS.set_dept_level(V1, "ticket", "speed", 25)
	var fast: Dictionary = EC.venue_satisfaction(V1)
	check(float(fast["queue_wait_s"]) < float(s["queue_wait_s"]), "more serve rate shortens the queue")
	check(float(fast["inputs"]["speed"]["score"]) > slow, "shorter queue raises the speed score")

	# Arrival at or above serve = a queue that never clears: wait pins at the
	# stall constant and the wait half of the speed score goes to zero.
	GS.reset_to_new_game()
	GS.venue_state(V1)["depts"]["promotions"]["staff"] = 20   # arrival >> serve
	var stalled: Dictionary = EC.venue_satisfaction(V1)
	var stall_s: float = float(EC.satisfaction_config()["speed"]["wait_stall_s"])
	check(is_equal_approx(float(stalled["queue_wait_s"]), stall_s), "arrival >= serve pins wait at wait_stall_s")
	var qw: float = float(EC.satisfaction_config()["speed"]["queue_weight"])
	var tp_only: float = (1.0 - qw) * clampf(float(stalled["throughput_per_s"])
		/ float(stalled["throughput_target"]), 0.0, 1.0)
	check(absf(float(stalled["inputs"]["speed"]["score"]) - tp_only) < 0.0001,
		"stalled queue contributes nothing, only throughput scores")
	check(is_equal_approx(EC.queue_wait_seconds(0.0, 1.0), 0.0), "no arrivals means no wait")
	check(is_equal_approx(EC.queue_wait_seconds(1.0, 0.0), stall_s), "no service means a stalled queue")

# ----------------------------------------------------------------- REST input
func _test_rest_input() -> void:
	print("-- rest areas: seats against the crowd --")
	GS.reset_to_new_game()
	GS.add_cash(BigNumber.from_parts(1.0, 9))
	var rcfg: Dictionary = EC.satisfaction_config().get("rest", {})
	var before: Dictionary = EC.venue_satisfaction(V1)
	check(int(before["seats"]) == int(rcfg["base_seats"]),
		"an undecorated venue offers only the venue's base seats")
	var expected_crowd: float = float(before["throughput_per_s"]) * float(rcfg["dwell_seconds"])
	check(absf(float(before["crowd"]) - expected_crowd) < 0.0001,
		"crowd == throughput * dwell_seconds")
	check(int(before["seats_needed"]) == maxi(1, int(ceil(expected_crowd * float(rcfg["seats_per_visitor"])))),
		"seats needed == ceil(crowd * seats_per_visitor)")
	check(DS.buy_decor(V1, "visitor_benches"), "buy visitor_benches")
	var after: Dictionary = EC.venue_satisfaction(V1)
	check(int(after["seats"]) == int(before["seats"]) + 6, "bench run adds its 6 seats")
	check(float(after["inputs"]["rest"]["score"]) > float(before["inputs"]["rest"]["score"]),
		"seating raises the rest score")
	check(is_equal_approx(float(after["inputs"]["rest"]["score"]), 1.0),
		"seats above the requirement clamp at 1.0")
	# oak_bench was seating in the fiction before it was seating in the maths.
	check(DS.piece_rest_seats("oak_bench") > 0, "oak_bench carries rest seats")
	check(DS.piece_rest_seats("crystal_chandelier") == 0, "a chandelier seats nobody")
	# A bigger crowd needs more seats: same seating, more visitors, lower score.
	GS.venue_state(V1)["depts"]["promotions"]["staff"] = 6
	GS.set_dept_level(V1, "ticket", "speed", 25)
	var crowded: Dictionary = EC.venue_satisfaction(V1)
	check(int(crowded["seats_needed"]) > int(after["seats_needed"]), "a bigger crowd needs more seats")
	check(float(crowded["inputs"]["rest"]["score"]) < 1.0, "the same seating no longer covers it")

# -------------------------------------------------------------- income effect
func _test_income_effect() -> void:
	print("-- the rating feeds income (value per visitor) --")
	GS.reset_to_new_game()
	GS.add_cash(BigNumber.from_parts(1.0, 9))
	GS.add_gems(2000)
	var poor: Dictionary = EC.venue_rates(V1)
	var poor_mult: float = float(poor["satisfaction_mult"])
	var poor_value: float = poor["value_per_visitor"].to_float_approx()
	# Decor moves BOTH the flat income_mult and the rating, so isolate the rating
	# by comparing value against the flat chain the rest of the sim uses.
	var flat: float = 2.0 * EC.income_multiplier(V1)
	check(absf(poor_value - flat * poor_mult) < 0.0001,
		"value_per_visitor == flat chain * rating multiplier")

	_make_five_star(V1)
	var rich: Dictionary = EC.venue_rates(V1)
	var rich_mult: float = float(rich["satisfaction_mult"])
	check(rich_mult > poor_mult, "a rated-up venue earns a bigger multiplier (%.2f -> %.2f)"
		% [poor_mult, rich_mult])
	check(rich["pending_per_s"].gt(poor["pending_per_s"]), "cash rate rises with the rating")
	# The rating changes the DROP, not the drop rate: flows are untouched by it.
	var flows_now: Dictionary = EC.venue_flows(V1)
	check(is_equal_approx(float(flows_now["effective_visitors_per_s"]),
		float(rich["effective_visitors_per_s"])),
		"visitor flow is identical with and without the rating applied")
	var ratio: float = rich["value_per_visitor"].to_float_approx() / (2.0 * EC.income_multiplier(V1))
	check(absf(ratio - rich_mult) < 0.0001, "the rating is the only extra factor on value")

# ------------------------------------------------------------------ boundaries
func _test_boundaries() -> void:
	print("-- boundaries --")
	var cfg: Dictionary = EC.satisfaction_config()
	var lo: float = float(cfg["income_mult_min"])
	var hi: float = float(cfg["income_mult_max"])
	# Floor: no decor, no staff anywhere, nothing served.
	GS.reset_to_new_game()
	var vs: Dictionary = GS.venue_state(V6)
	for dept_id in ["promotions", "ticket", "archive", "gallery"]:
		vs["depts"][dept_id]["staff"] = 0
	var dead: Dictionary = EC.venue_satisfaction(V6)
	check(float(dead["score"]) >= 0.0 and float(dead["score"]) <= 1.0, "score stays in 0..1 with zero staff")
	check(not is_nan(float(dead["score"])), "score is not NaN with zero staff")
	check(is_equal_approx(float(dead["queue_wait_s"]), 0.0), "no arrivals, no queue wait")
	check(is_equal_approx(float(dead["inputs"]["decor"]["score"]), 0.0), "decor floor is 0")
	var dead_rates: Dictionary = EC.venue_rates(V6)
	check(dead_rates["banked_per_s"].is_zero(), "a venue with no staff banks nothing")
	# Ceiling.
	GS.reset_to_new_game()
	_make_five_star(V1)
	var best: Dictionary = EC.venue_satisfaction(V1)
	check(is_equal_approx(float(best["score"]), 1.0), "a fully-served, fully-decorated, fully-seated venue scores 1.0")
	check(is_equal_approx(float(best["stars"]), 5.0), "5.0 stars at score 1.0")
	check(is_equal_approx(float(best["income_mult"]), hi), "multiplier tops out at income_mult_max")
	check(str(best["mood"]) == "delighted", "mood at the ceiling is delighted")
	check(str(best["reason"]).length() > 0, "there is always a reason string")
	# Every input score is a proper fraction, whatever the state.
	for probe in [dead, best]:
		for key in ["decor", "speed", "rest"]:
			var sc: float = float(probe["inputs"][key]["score"])
			check(sc >= 0.0 and sc <= 1.0, "input %s stays in 0..1 (%.3f)" % [key, sc])
	check(lo < hi, "multiplier range is ordered")

# ---------------------------------------------------------- limiting input
func _test_limiting_input() -> void:
	print("-- the breakdown names the input costing the most stars --")
	GS.reset_to_new_game()
	_make_five_star(V1)
	# Strip the seating back out: rest becomes the only shortfall.
	var vs: Dictionary = GS.venue_state(V1)
	for slot in vs["decor"].keys():
		if DS.piece_rest_seats(str(vs["decor"][slot])) > 0:
			vs["decor"][slot] = "crystal_chandelier"
	var s: Dictionary = EC.venue_satisfaction(V1)
	check(str(s["limiting"]) == "rest", "rest is named when seating is the only gap (got %s)" % s["limiting"])
	check("sit" in str(s["reason"]).to_lower(), "the reason sentence explains the seating gap")
	check(str(s["limiting_label"]) == "Rest Areas", "limiting_label is player-facing")
	# It is the biggest WEIGHTED shortfall, not the lowest raw score.
	var w: Dictionary = EC.satisfaction_config().get("weights", {})
	var worst: float = -1.0
	var worst_key: String = ""
	for key in ["decor", "speed", "rest"]:
		var loss: float = float(w[key]) * (1.0 - float(s["inputs"][key]["score"]))
		if loss > worst:
			worst = loss
			worst_key = key
	check(str(s["limiting"]) == worst_key, "limiting == argmax(weight * shortfall)")
	for key in ["decor", "speed", "rest"]:
		check(str(s["inputs"][key]["detail"]).length() > 0, "input %s carries a numeric detail line" % key)

# ------------------------------------------------- per-venue difficulty step
func _test_venue_difficulty_step() -> void:
	print("-- targets scale per venue, so the same floor rates lower later --")
	GS.reset_to_new_game()
	check(EC.satisfaction_decor_target(V6) > EC.satisfaction_decor_target(V1),
		"decor target grows with venue order")
	check(EC.satisfaction_throughput_target(V6) > EC.satisfaction_throughput_target(V1),
		"throughput target grows with venue order")
	# Identical department levels and identical decor points in both venues.
	for vid in [V1, V6]:
		GS.set_dept_level(vid, "ticket", "speed", 12)
		GS.venue_state(vid)["depts"]["promotions"]["staff"] = 3
		var placed: Dictionary = {}
		for i in range(6):
			placed[str(i)] = "crystal_chandelier"
		GS.venue_state(vid)["decor"] = placed
	var early: Dictionary = EC.venue_satisfaction(V1)
	var late: Dictionary = EC.venue_satisfaction(V6)
	check(float(late["score"]) < float(early["score"]),
		"the same build rates lower at venue 6 (%.3f vs %.3f)" % [late["score"], early["score"]])
	check(float(late["income_mult"]) < float(early["income_mult"]),
		"and therefore earns less per visitor")

# ------------------------------------------------- derived, so no save field
func _test_derived_not_persisted() -> void:
	print("-- the rating is derived, so it needs no save field --")
	GS.reset_to_new_game()
	GS.add_cash(BigNumber.from_parts(1.0, 9))
	check(DS.buy_decor(V1, "visitor_benches"), "place a rest area before saving")
	GS.set_dept_level(V1, "ticket", "speed", 8)
	var before: Dictionary = EC.venue_satisfaction(V1)
	var save: Dictionary = GS.to_save_dict()
	var round_tripped: Dictionary = JSON.parse_string(JSON.stringify(save))
	# A pre-satisfaction save has no rating key of any kind — nothing to migrate.
	check(not save.has("satisfaction") and not save.has("rating"),
		"to_save_dict adds no rating field")
	var v1_state: Dictionary = round_tripped["venues_state"][V1]
	check(not v1_state.has("satisfaction") and not v1_state.has("stars"),
		"venue state adds no rating field")
	GS.reset_to_new_game()
	GS.from_save_dict(round_tripped)
	var after: Dictionary = EC.venue_satisfaction(V1)
	check(absf(float(after["score"]) - float(before["score"])) < 0.0001,
		"rating reproduces exactly from a reloaded save (%.5f vs %.5f)" % [before["score"], after["score"]])
	check(int(after["seats"]) == int(before["seats"]), "rest seats survive the round trip")
	# An old save that predates rest_seats/decor_score still rates: both fields
	# have defaults, so a venue full of legacy pieces scores on income bonus.
	GS.reset_to_new_game()
	var legacy: Dictionary = {}
	for i in range(4):
		legacy[str(i)] = ["oak_bench", "velvet_rope", "crest_banner", "mosaic_floor"][i]
	GS.venue_state(V1)["decor"] = legacy
	var legacy_sat: Dictionary = EC.venue_satisfaction(V1)
	check(float(legacy_sat["decor_points"]) > 0.0, "legacy pieces score decor points from income bonus")
	check(float(legacy_sat["score"]) > 0.0 and float(legacy_sat["score"]) <= 1.0, "legacy venue rates in range")

# --------------------------------------------------------------------- helpers
## Drive a venue to a perfect rating: decor over target, queue under the good
## threshold with throughput over target, seating over the crowd. Slots are
## written directly (as test_meta does) so the state is exact, not shopped-for.
func _make_five_star(venue_id: String) -> void:
	GS.venue_state(venue_id)["depts"]["promotions"]["staff"] = 5
	GS.set_dept_level(venue_id, "ticket", "speed", 25)
	var placed: Dictionary = {}
	var pieces: Array = ["panorama_rest_deck", "quiet_reading_nook", "atrium_lounge",
		"picnic_lawn", "crystal_chandelier", "sphinx_statue"]
	for i in range(pieces.size()):
		placed[str(i)] = str(pieces[i])
	GS.venue_state(venue_id)["decor"] = placed
