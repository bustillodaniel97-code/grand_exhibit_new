extends SceneTree
## QA M5-2: device-clock cheating defenses (SPEC §3 ClockGuard, §10 offline earnings).
## - last_seen_unix in the FUTURE (device rollback) -> 0s, 0 amount, clock_anomaly("rollback")
## - last_seen_unix far in the past -> clamped to offline_cap_hours, capped flag
## - 2h absence -> ~2h x current rate
## - expired boost (income_x2_until in past) -> income_boost_active() == 1.0
## Run: godot --headless --path <repo> -s tests/qa/test_clock_cheating.gd

var failures: int = 0

func check(cond: bool, msg: String) -> void:
	if cond:
		print("  PASS ", msg)
	else:
		failures += 1
		printerr("  FAIL ", msg)

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var EB: Node = root.get_node("EventBus")
	var DL: Node = root.get_node("DataLoader")
	var GS: Node = root.get_node("GameState")
	var SS: Node = root.get_node("SaveSystem")
	var CG: Node = root.get_node("ClockGuard")
	var ECON: Node = root.get_node("Economy")
	DL.reload_all()
	GS.reset_to_new_game()
	GS.ready_flag = false  # freeze Economy._process so ticks can't perturb assertions

	var anomalies: Array = []
	EB.clock_anomaly.connect(func(kind): anomalies.append(kind))

	print("-- rollback: last_seen in the future --")
	GS.cash = BigNumber.zero()
	var now_unix: int = CG.now()
	GS.last_seen_unix = now_unix + 3600  # device clock rolled back an hour
	var off: Dictionary = SS.compute_offline_and_apply()
	check(off["seconds"] == 0, "future last_seen -> 0 offline seconds (got %d)" % off["seconds"])
	check((off["amount"] as BigNumber).is_zero(), "future last_seen -> 0 offline amount")
	check(GS.cash.is_zero(), "rollback grants no cash")
	check("rollback" in anomalies, "clock_anomaly('rollback') emitted (got %s)" % str(anomalies))

	print("-- far past: clamped to offline_cap_hours --")
	var cap_s: int = int(float(DL.core["economy"].get("offline_cap_hours", 4)) * 3600.0)
	var rate: BigNumber = ECON.current_cash_per_second()
	check(rate.gt(BigNumber.zero()), "fresh-game income rate positive")
	GS.cash = BigNumber.zero()
	now_unix = CG.now()
	GS.last_seen_unix = now_unix - 100 * 3600  # 100 hours away
	var off2: Dictionary = SS.compute_offline_and_apply()
	check(off2["seconds"] == cap_s, "far-past clamped to cap (%d == %d)" % [off2["seconds"], cap_s])
	check(off2["capped"] == true, "capped flag set on far-past absence")
	var expect2: BigNumber = rate.scale(float(cap_s))
	check((off2["amount"] as BigNumber).eq(expect2), "capped amount == rate x cap_seconds")
	check(GS.cash.eq(expect2), "capped amount applied to cash")

	print("-- honest 2h absence: ~2h x rate --")
	GS.cash = BigNumber.zero()
	now_unix = CG.now()
	GS.last_seen_unix = now_unix - 2 * 3600
	var off3: Dictionary = SS.compute_offline_and_apply()
	check(abs(off3["seconds"] - 7200) <= 5, "2h absence -> ~7200s (got %d)" % off3["seconds"])
	check(not off3["capped"], "2h absence not capped")
	var expect3: BigNumber = rate.scale(float(off3["seconds"]))
	check((off3["amount"] as BigNumber).eq(expect3), "2h amount == rate x seconds")
	check(GS.cash.eq(expect3), "2h amount applied to cash")

	print("-- micro-absence ignored (<=30s) --")
	GS.cash = BigNumber.zero()
	now_unix = CG.now()
	GS.last_seen_unix = now_unix - 20
	var off4: Dictionary = SS.compute_offline_and_apply()
	check((off4["amount"] as BigNumber).is_zero(), "20s absence grants nothing")

	print("-- boost expiry --")
	GS.boosts["income_x2_until"] = CG.now() - 10  # already expired
	check(GS.income_boost_active() == 1.0, "expired income_x2 -> multiplier 1.0")
	GS.boosts["income_x2_until"] = CG.now() + 3600
	check(GS.income_boost_active() == 2.0, "active income_x2 -> multiplier 2.0")
	GS.boosts["income_x2_until"] = 0
	check(GS.income_boost_active() == 1.0, "zero income_x2_until -> multiplier 1.0")

	print("-- compute_offline_and_apply updates last_seen --")
	check(abs(GS.last_seen_unix - CG.now()) <= 5, "last_seen_unix refreshed to now")

	print("---")
	if failures == 0:
		print("ALL QA CLOCK-CHEAT TESTS PASSED")
	else:
		printerr("QA CLOCK-CHEAT TESTS FAILED: %d" % failures)
	quit(0 if failures == 0 else 1)
