extends SceneTree
## QA M5-8: expedition idle insight storage (SPEC §4 events.json insight_idle, §6).
## - Locked expedition -> no accrual, rate 0.
## - Unlocked, 10h absence -> stored == cap exactly (cap < accrual), never beyond.
## - collect 1x / 2x multipliers pay correctly and drain storage.
## Run: godot --headless --path <repo> -s tests/qa/test_idle_insight.gd

var failures: int = 0

func check(cond: bool, msg: String) -> void:
	if cond:
		print("  PASS ", msg)
	else:
		failures += 1
		printerr("  FAIL ", msg)

func stored(ECON: Node, GS: Node) -> BigNumber:
	return BigNumber.from_save(GS.expedition_state.get("insight_stored", {}))

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var DL: Node = root.get_node("DataLoader")
	var GS: Node = root.get_node("GameState")
	var ECON: Node = root.get_node("Economy")
	var CG: Node = root.get_node("ClockGuard")
	DL.reload_all()
	GS.reset_to_new_game()
	GS.ready_flag = false  # freeze Economy._process; we call tick_insight_storage directly

	print("-- locked expedition: no accrual --")
	check(GS.rep_level() < 7, "fresh game rep < 7 (expedition locked)")
	check(ECON.insight_per_second().is_zero(), "insight_per_second == 0 while locked")
	var now: int = CG.now()
	GS.expedition_state["last_tick"] = now - 10 * 3600
	ECON.tick_insight_storage(now)
	check(stored(ECON, GS).is_zero(), "no insight accrues while locked")

	print("-- unlocked, 10h absence -> stored == cap (not beyond) --")
	GS.add_reputation(BigNumber.from_float(1250.0))  # rep 7
	check(GS.feature_unlocked("expedition"), "expedition unlocked at rep 7")
	var cap: BigNumber = ECON.insight_cap()
	var cfg: Dictionary = ECON.insight_idle_config()
	var expect_cap: float = float(cfg.get("cap_base", 60)) + float(cfg.get("cap_per_rep_level", 5)) * GS.rep_level()
	check(cap.eq(BigNumber.from_float(expect_cap)),
		"cap == cap_base + cap_per_rep_level x rep (%s == %s)" % [cap.to_notation(), str(expect_cap)])
	# Sanity: uncapped accrual over the internal 8h clamp would exceed cap.
	var eight_h_accrual: float = float(cfg.get("per_minute", 2.0)) / 60.0 * 8.0 * 3600.0
	check(eight_h_accrual > expect_cap, "scenario valid: 8h accrual (%.0f) exceeds cap (%.0f)"
		% [eight_h_accrual, expect_cap])
	now = CG.now()
	GS.expedition_state["last_tick"] = now - 10 * 3600
	GS.expedition_state["insight_stored"] = BigNumber.zero().to_save()
	ECON.tick_insight_storage(now)
	var s1: BigNumber = stored(ECON, GS)
	check(s1.eq(cap), "10h absence: stored == cap exactly (%s == %s)" % [s1.to_notation(), cap.to_notation()])
	check(not s1.gt(cap), "stored never exceeds cap")
	# Ticking again with more elapsed time must not push past the cap either.
	GS.expedition_state["last_tick"] = now - 20 * 3600
	ECON.tick_insight_storage(now)
	check(stored(ECON, GS).eq(cap), "re-tick at cap stays at cap")

	print("-- collect multipliers 1x / 2x --")
	var insight0: BigNumber = GS.insight.copy()
	var g1: BigNumber = ECON.collect_insight(1.0)
	check(g1.eq(cap), "collect 1x grants stored amount (%s)" % g1.to_notation())
	check(GS.insight.eq(insight0.add(cap)), "collect 1x lands in insight wallet")
	check(stored(ECON, GS).is_zero(), "collect drains storage")
	# Accrue a partial amount below cap: 20 minutes at per_minute rate.
	now = CG.now()
	GS.expedition_state["last_tick"] = now - 1200
	ECON.tick_insight_storage(now)
	var partial: BigNumber = stored(ECON, GS)
	var expect_partial: BigNumber = BigNumber.from_float(float(cfg.get("per_minute", 2.0)) * 20.0)
	check(partial.eq(expect_partial), "20min accrual == per_minute x 20 (%s == %s)"
		% [partial.to_notation(), expect_partial.to_notation()])
	check(partial.lt(cap), "partial accrual below cap")
	var insight1: BigNumber = GS.insight.copy()
	var g2: BigNumber = ECON.collect_insight(2.0)
	check(g2.eq(partial.scale(2.0)), "collect 2x grants exactly 2x stored (%s == 2x%s)"
		% [g2.to_notation(), partial.to_notation()])
	check(GS.insight.eq(insight1.add(partial.scale(2.0))), "collect 2x lands in insight wallet")
	check(stored(ECON, GS).is_zero(), "collect 2x drains storage")
	check(ECON.collect_insight(3.0).is_zero(), "collect on empty storage grants 0")

	print("---")
	if failures == 0:
		print("ALL QA IDLE-INSIGHT TESTS PASSED")
	else:
		printerr("QA IDLE-INSIGHT TESTS FAILED: %d" % failures)
	quit(0 if failures == 0 else 1)
