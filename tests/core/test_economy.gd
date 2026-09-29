extends SceneTree
## test_economy.gd — choke-point sim, purchase flow, step multipliers, manual collect.
## Run: godot --headless --path <repo> -s tests/core/test_economy.gd

var failures := 0

func check(cond: bool, msg: String) -> void:
	if cond:
		print("  PASS ", msg)
	else:
		failures += 1
		print("  FAIL ", msg)

func _init() -> void:
	call_deferred("run")

const V := "whispering_pines"

func run() -> void:
	for pair in [["event_bus","EventBus"],["data_loader","DataLoader"],["clock_guard","ClockGuard"],["analytics","Analytics"],["ad_service","AdService"],["iap_service","IAPService"],["game_state","GameState"],["save_system","SaveSystem"],["economy","Economy"]]:
		var n: Node = load("res://autoload/%s.gd" % pair[0]).new()
		n.name = pair[1]
		root.add_child(n)

	# Under -s the main script compiles before autoload names are bound;
	# access the bootstrapped singletons via local aliases instead.
	var EventBus: Node = root.get_node("EventBus")
	var DataLoader: Node = root.get_node("DataLoader")
	var ClockGuard: Node = root.get_node("ClockGuard")
	var Analytics: Node = root.get_node("Analytics")
	var GameState: Node = root.get_node("GameState")
	var SaveSystem: Node = root.get_node("SaveSystem")
	var Economy: Node = root.get_node("Economy")

	GameState.reset_to_new_game()  # ready_flag stays false -> Economy._process no-ops

	print("-- choke model: archive weakest by construction --")
	# Crank promotions + ticket speed so archive transport is the clear minimum.
	GameState.set_dept_level(V, "promotions", "speed", 10)
	GameState.set_dept_level(V, "ticket", "speed", 10)
	GameState.set_dept_level(V, "archive", "speed", 1)
	var rates: Dictionary = Economy.venue_rates(V)
	check(rates["choke_id"] == "archive", "choke_id == archive (got %s)" % rates["choke_id"])
	var transport: float = rates["transport_per_s"]
	var value: BigNumber = rates["value_per_visitor"]
	var expected_banked: BigNumber = value.scale(transport)
	var banked: BigNumber = rates["banked_per_s"]
	check(banked.eq(expected_banked), "banked == transport * value")
	check(rates["pending_per_s"].gt(banked), "pending > banked when archive chokes")
	check(Economy.current_cash_per_second().eq(banked), "current_cash_per_second == banked_per_s")

	print("-- choke model: promotions weakest --")
	GameState.reset_to_new_game()
	GameState.set_dept_level(V, "promotions", "speed", 1)   # arrival 0.28
	GameState.set_dept_level(V, "ticket", "speed", 20)      # serve huge
	GameState.set_dept_level(V, "archive", "speed", 20)     # transport huge
	var r2: Dictionary = Economy.venue_rates(V)
	check(r2["choke_id"] == "promotions", "choke_id == promotions (got %s)" % r2["choke_id"])
	check(r2["banked_per_s"].eq(r2["pending_per_s"]), "banked == pending when transport ample")
	var expected_pending: BigNumber = r2["value_per_visitor"].scale(minf(r2["arrival_per_s"], r2["serve_per_s"]))
	check(r2["pending_per_s"].eq(expected_pending), "pending == min(arrival, serve) * value")

	print("-- value & gallery bonus --")
	GameState.reset_to_new_game()
	var base_rates: Dictionary = Economy.venue_rates(V)
	# base value 2.0 * ticket value 1.0 * (1 + 0) * 1.0 * venue-rating multiplier.
	# The rating is a live factor now (see test_satisfaction.gd), so the expected
	# value is stated against it rather than a frozen literal.
	var sat_mult: float = Economy.satisfaction_multiplier(V)
	check(is_equal_approx(base_rates["value_per_visitor"].to_float_approx(), 2.0 * sat_mult),
		"base value_per_visitor == 2 * rating mult (%.4f)" % sat_mult)
	check(is_equal_approx(float(base_rates["satisfaction_mult"]), sat_mult),
		"venue_rates exposes satisfaction_mult")
	var vs: Dictionary = GameState.venue_state(V)
	vs["depts"]["gallery"]["staff"] = 2  # 2 * 0.05 = +10%
	var gal_rates: Dictionary = Economy.venue_rates(V)
	check(is_equal_approx(gal_rates["value_per_visitor"].to_float_approx(), 2.2 * sat_mult),
		"gallery bonus +10% -> 2.2 * rating mult")
	check(is_equal_approx(float(gal_rates["satisfaction_mult"]), sat_mult),
		"gallery staff does not move the rating (it is not a rating input)")

	print("-- step multiplier doubles at level 10 --")
	check(is_equal_approx(DataLoader.track_step_multiplier("ticket", "speed", 9), 1.0), "step mult lvl 9 == 1.0")
	check(is_equal_approx(DataLoader.track_step_multiplier("ticket", "speed", 10), 2.0), "step mult lvl 10 == 2.0")
	GameState.set_dept_level(V, "ticket", "speed", 9)
	var s9: float = Economy.dept_stat(V, "ticket", "speed")
	GameState.set_dept_level(V, "ticket", "speed", 10)
	var s10: float = Economy.dept_stat(V, "ticket", "speed")
	# raw stat grows by per_level 0.04 then doubles: s10 = (s9 + 0.04) * 2
	check(is_equal_approx(s10, (s9 + 0.04) * 2.0), "dept_stat doubles at level 10 (%f -> %f)" % [s9, s10])

	print("-- purchase flow --")
	GameState.reset_to_new_game()
	GameState.cash = BigNumber.from_float(1000.0)
	var xp_before: BigNumber = GameState.reputation_xp.copy()
	var cost: BigNumber = DataLoader.upgrade_cost("ticket", "speed", 1, 1.0, 0)
	var ok: bool = Economy.purchase_upgrade(V, "ticket", "speed")
	check(ok, "purchase_upgrade succeeds with funds")
	check(GameState.dept_level(V, "ticket", "speed") == 2, "level incremented to 2")
	check(is_equal_approx(GameState.cash.to_float_approx(), 1000.0 - cost.to_float_approx()), "cash spent == cost")
	var xp_gain: float = GameState.reputation_xp.sub(xp_before).to_float_approx()
	check(is_equal_approx(xp_gain, 2.0 + 0.25 * 1.0), "rep xp granted = base + level*per_level")
	# staff track increments staff and respects max_staff
	var staff_before: int = int(GameState.venue_state(V)["depts"]["ticket"]["staff"])
	check(Economy.purchase_upgrade(V, "ticket", "staff"), "staff purchase succeeds")
	check(int(GameState.venue_state(V)["depts"]["ticket"]["staff"]) == staff_before + 1, "staff incremented")
	GameState.venue_state(V)["depts"]["ticket"]["staff"] = int(DataLoader.dept_def("ticket")["max_staff"])
	check(not Economy.purchase_upgrade(V, "ticket", "staff"), "staff purchase blocked at max_staff")
	# insufficient funds
	GameState.reset_to_new_game()
	GameState.cash = BigNumber.zero()
	check(not Economy.purchase_upgrade(V, "ticket", "speed"), "purchase fails without funds")
	check(GameState.dept_level(V, "ticket", "speed") == 1, "failed purchase leaves level unchanged")

	print("-- manual collect --")
	GameState.reset_to_new_game()
	GameState.cash = BigNumber.zero()
	GameState.pending_cash[V] = BigNumber.from_float(100.0)
	var got: BigNumber = Economy.manual_collect(V)
	# fraction 1.0, tip 5% -> 105
	check(is_equal_approx(got.to_float_approx(), 105.0), "manual_collect returns pending * (1 + tip)")
	check(GameState.pending_cash[V].is_zero(), "pending cleared after collect")
	check(is_equal_approx(GameState.cash.to_float_approx(), 105.0), "cash credited")

	print("-- income boost --")
	GameState.reset_to_new_game()
	var normal: float = Economy.current_cash_per_second().to_float_approx()
	GameState.boosts["income_x2_until"] = ClockGuard.now() + 3600
	check(is_equal_approx(GameState.income_boost_active(), 2.0), "boost active = 2.0")
	var boosted: float = Economy.current_cash_per_second().to_float_approx()
	check(is_equal_approx(boosted, normal * 2.0), "boost doubles income rate")
	GameState.boosts["income_x2_until"] = 0
	check(is_equal_approx(GameState.income_boost_active(), 1.0), "boost expired = 1.0")

	print("-- insight storage (expedition locked at rep 1) --")
	GameState.reset_to_new_game()
	check(Economy.insight_per_second().is_zero(), "insight rate 0 while expedition locked")
	GameState.expedition_state["last_tick"] = ClockGuard.now() - 600
	Economy.tick_insight_storage(ClockGuard.now())
	check(BigNumber.from_save(GameState.expedition_state["insight_stored"]).is_zero(), "no insight accrues while locked")

	_test_takings_land_on_busy_windows(GameState, Economy)

	print("RESULT: ", "ALL PASS" if failures == 0 else "%d FAILURES" % failures)
	quit(0 if failures == 0 else 1)

## A till must not count money with nobody standing at it.
##
## The economy is rate-based and books takings every tick whether or not the
## floor exists, which is correct — offline earnings depend on it. What was wrong
## was WHERE: the gain was split evenly across every window, so an empty one
## climbed exactly as fast as a busy one. VenueFloor now reports which windows
## have a customer and the gain follows. The total is untouched, which is the
## property that keeps every balance number in the game valid.
func _test_takings_land_on_busy_windows(GameState: Node, Economy: Node) -> void:
	print("-- takings land on the windows actually serving --")
	GameState.reset_to_new_game()
	GameState.ready_flag = true
	var vid: String = GameState.current_venue
	GameState.set_dept_level(vid, "ticket", "staff", 3)
	var items: Array = GameState.dept_items(vid, "ticket")
	check(items.size() == 3, "three ticket windows (%d)" % items.size())
	for it in items:
		it["pending"] = BigNumber.zero().to_save()

	var gained := BigNumber.from_parts(3.0, 3)

	# Only window 1 has anyone at it.
	Economy.set_busy_stations(vid, PackedInt32Array([1]))
	Economy._allocate_item_pending(vid, gained, BigNumber.zero())
	var p0: float = Economy.item_pending(vid, "ticket", 0).to_float_approx()
	var p1: float = Economy.item_pending(vid, "ticket", 1).to_float_approx()
	var p2: float = Economy.item_pending(vid, "ticket", 2).to_float_approx()
	check(p0 == 0.0 and p2 == 0.0,
		"the two idle windows took nothing (%.0f, %.0f)" % [p0, p2])
	check(p1 > 0.0, "the serving window took the lot (%.0f)" % p1)
	check(is_equal_approx(p0 + p1 + p2, gained.to_float_approx()),
		"and the TOTAL is unchanged — allocation moved, the economy did not")

	# No floor reporting (offline, headless): fall back to an even split, or
	# takings would vanish whenever nobody is watching.
	for it in items:
		it["pending"] = BigNumber.zero().to_save()
	Economy._busy_stations.clear()
	Economy._allocate_item_pending(vid, gained, BigNumber.zero())
	var q0: float = Economy.item_pending(vid, "ticket", 0).to_float_approx()
	var q1: float = Economy.item_pending(vid, "ticket", 1).to_float_approx()
	var q2: float = Economy.item_pending(vid, "ticket", 2).to_float_approx()
	check(q0 > 0.0 and q1 > 0.0 and q2 > 0.0,
		"with no floor reporting, every window still earns (%.0f/%.0f/%.0f)" % [q0, q1, q2])
	check(is_equal_approx(q0 + q1 + q2, gained.to_float_approx()),
		"and that total is unchanged too")

	# A stale hint must not pin takings to windows nobody is watching.
	for it in items:
		it["pending"] = BigNumber.zero().to_save()
	Economy.set_busy_stations(vid, PackedInt32Array([2]))
	(Economy._busy_stations[vid] as Dictionary)["t"] = -9999.0
	Economy._allocate_item_pending(vid, gained, BigNumber.zero())
	check(Economy.item_pending(vid, "ticket", 0).to_float_approx() > 0.0,
		"a stale hint expires back to the even split")
