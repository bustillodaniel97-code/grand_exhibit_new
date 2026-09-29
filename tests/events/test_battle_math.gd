extends SceneTree
## tests/events/test_battle_math.gd — combat math + reward draws (SPEC §6, §12).
## Run: godot --headless --path <repo> -s tests/events/test_battle_math.gd

const BattleMath = preload("res://scripts/events/battle_math.gd")

const AUTOLOADS := {
	"EventBus": "res://autoload/event_bus.gd",
	"DataLoader": "res://autoload/data_loader.gd",
	"ClockGuard": "res://autoload/clock_guard.gd",
	"Analytics": "res://autoload/analytics.gd",
	"AdService": "res://autoload/ad_service.gd",
	"IAPService": "res://autoload/iap_service.gd",
	"GameState": "res://autoload/game_state.gd",
	"SaveSystem": "res://autoload/save_system.gd",
	"Economy": "res://autoload/economy.gd",
}

var failures := 0
var DL  # DataLoader node
var GS  # GameState node


func check(cond: bool, msg: String) -> void:
	if cond:
		print("PASS: ", msg)
	else:
		failures += 1
		printerr("FAIL: ", msg)


func _initialize() -> void:
	_boot()
	DL = root.get_node("DataLoader")
	GS = root.get_node("GameState")
	DL.reload_all()  # _ready is deferred past _initialize; force data now
	GS.reset_to_new_game()
	_test_manager_attack()
	_test_team_power()
	_test_stage_boss_hp_monotonic()
	_test_stage_ramp_is_a_ramp()
	_test_every_stage_is_winnable_on_paper()
	_test_stronger_team_is_never_worse_off()
	_test_expedition_cycle_scaling()
	_test_expedition_cycle_cap()
	_test_hp_floor()
	_test_reward_draw()
	quit(1 if failures > 0 else 0)


func _boot() -> void:
	for name in AUTOLOADS.keys():
		if root.has_node(name):
			continue
		var n: Node = load(AUTOLOADS[name]).new()
		n.name = name
		root.add_child(n)


func _test_manager_attack() -> void:
	var def: Dictionary = DL.get_manager_def("docent_poppy")
	check(not def.is_empty(), "docent_poppy def loaded")
	var bp: float = float(def.get("battle_power", 10.0))
	check(is_equal_approx(BattleMath.manager_attack(def, {"level": 1, "rank": 1}), bp),
		"attack level1/rank1 = battle_power")
	check(is_equal_approx(BattleMath.manager_attack(def, {"level": 5, "rank": 1}), bp * 1.48),
		"attack level5 = battle_power * 1.48")
	check(is_equal_approx(BattleMath.manager_attack(def, {"level": 1, "rank": 2}), bp * 1.3),
		"attack rank2 uses the ten-rank ladder")
	check(is_equal_approx(BattleMath.manager_attack(def, {"level": 5, "rank": 4}), bp * 1.48 * 2.2),
		"attack level5/rank4 uses Audit Efficiency")
	# Tolerant of junk state.
	check(BattleMath.manager_attack(def, {}) > 0.0, "attack tolerates empty state")


func _test_team_power() -> void:
	var d1: Dictionary = DL.get_manager_def("docent_poppy")
	var d2: Dictionary = DL.get_manager_def("paleontologist_rex")
	var tp: float = BattleMath.team_power([
		{"def": d1, "state": {"level": 1, "rank": 1}},
		{"def": d2, "state": {"level": 1, "rank": 1}},
	])
	var expect: float = float(d1["battle_power"]) + float(d2["battle_power"])
	check(is_equal_approx(tp, expect), "team_power = sum of manager attacks")
	check(BattleMath.team_power([]) == 0.0, "empty team power is 0")


func _test_stage_boss_hp_monotonic() -> void:
	var ev: Dictionary = DL.get_event("inspection_frenzy")
	var stages: Array = ev.get("stages", [])
	check(stages.size() == 6, "inspection has 6 stages")
	var prev := 0.0
	var monotonic := true
	for i in stages.size():
		var hp: float = BattleMath.stage_boss_hp(ev, i, 100.0)
		if hp <= prev:
			monotonic = false
		prev = hp
	check(monotonic, "stage_boss_hp strictly increasing in stage index")


## Boss HP is quoted as a fraction of the damage the SELECTED team can expect to
## deal in the stage's move budget. That fraction has to climb across the event,
## or later stages are only "harder" because they hand out more moves.
func _test_stage_ramp_is_a_ramp() -> void:
	var ev: Dictionary = DL.get_event("inspection_frenzy")
	var stages: Array = ev.get("stages", [])
	var prev := 0.0
	var climbs := true
	for i in stages.size():
		var moves: int = BattleMath.stage_moves(ev, i)
		var ratio: float = BattleMath.stage_boss_hp(ev, i, 100.0) \
			/ BattleMath.expected_damage(100.0, moves)
		if ratio <= prev:
			climbs = false
		prev = ratio
	check(climbs, "hp / expected damage rises every stage")
	check(prev < 1.25, "even the last stage stays inside a reachable %.2f of budget" % prev)


## THE regression for "battles are arithmetically unwinnable". Boss HP must sit
## below the damage budget of the team that is fighting it, at EVERY team power
## — the old model derived HP from the whole owned roster, so a 14-manager
## collection turned stage 1 from 120 HP into 959 while damage stayed put.
func _test_every_stage_is_winnable_on_paper() -> void:
	var ev: Dictionary = DL.get_event("inspection_frenzy")
	var boss: Dictionary = DL.get_event("expedition").get("boss", {})
	for tp in [30.0, 44.4, 147.6, 722.4, 5000.0]:
		for i in (ev.get("stages", []) as Array).size():
			var moves: int = BattleMath.stage_moves(ev, i)
			var hp: float = BattleMath.stage_boss_hp(ev, i, tp)
			check(hp < BattleMath.expected_damage(tp, moves),
				"stage %d at team power %.0f is inside the damage budget (%.0f < %.0f)" % [
					i + 1, tp, hp, BattleMath.expected_damage(tp, moves)])
		var bhp: float = BattleMath.expedition_boss_hp(boss, tp, 0)
		check(bhp < BattleMath.expected_damage(tp, int(boss.get("moves", 24))),
			"expedition boss at team power %.0f is inside the damage budget" % tp)
	check(BattleMath.MAX_BUDGET_SHARE < 1.0,
		"the budget ceiling is a real ceiling, not a formality")


## Progression must not invert: a stronger team never faces a RELATIVELY tougher
## boss. Ratio = hp / expected damage; it may fall with power, never rise.
func _test_stronger_team_is_never_worse_off() -> void:
	var ev: Dictionary = DL.get_event("inspection_frenzy")
	var powers := [20.0, 30.0, 60.0, 100.0, 200.0, 500.0, 1500.0, 6000.0]
	for i in (ev.get("stages", []) as Array).size():
		var moves: int = BattleMath.stage_moves(ev, i)
		var prev := INF
		var ok := true
		for tp in powers:
			var ratio: float = BattleMath.stage_boss_hp(ev, i, tp) \
				/ BattleMath.expected_damage(tp, moves)
			if ratio > prev + 0.0001:
				ok = false
			prev = ratio
		check(ok, "stage %d: difficulty never rises with team power" % (i + 1))
	# And doubling the team really does roughly halve the effort.
	var lo: float = BattleMath.stage_boss_hp(ev, 2, 100.0) / BattleMath.expected_damage(100.0, 22)
	var hi: float = BattleMath.stage_boss_hp(ev, 2, 200.0) / BattleMath.expected_damage(200.0, 22)
	check(hi < lo, "doubling team power measurably eases the fight (%.3f -> %.3f)" % [lo, hi])
	check(hi > lo * 0.7, "growth is a reward, not a trivialiser")


func _test_expedition_cycle_scaling() -> void:
	var boss: Dictionary = DL.get_event("expedition").get("boss", {})
	var growth: float = float(boss.get("cycle_hp_growth", 1.15))
	var c0: float = BattleMath.expedition_boss_hp(boss, 100.0, 0)
	var c1: float = BattleMath.expedition_boss_hp(boss, 100.0, 1)
	var c2: float = BattleMath.expedition_boss_hp(boss, 100.0, 2)
	check(is_equal_approx(c1 / c0, growth), "boss hp grows by cycle_hp_growth per cycle")
	check(c2 >= c1 and c2 <= c0 * growth * growth,
		"escalation compounds up to the budget ceiling and no further")


## Uncapped compounding always wins eventually — at the old +25%/cycle a fully
## maxed team dropped to a 35% clear by cycle 4, turning an evergreen mode into a
## countdown to a wall. Escalation now tops out at "hard", never at "impossible".
func _test_expedition_cycle_cap() -> void:
	var boss: Dictionary = DL.get_event("expedition").get("boss", {})
	var moves: int = int(boss.get("moves", 24))
	for tp in [30.0, 100.0, 722.4]:
		var budget: float = BattleMath.expected_damage(tp, moves)
		var prev := 0.0
		var rises := true
		for cycle in [0, 1, 2, 4, 8, 40]:
			var hp: float = BattleMath.expedition_boss_hp(boss, tp, cycle)
			if hp < prev - 0.0001:
				rises = false
			prev = hp
			check(hp <= budget * BattleMath.MAX_BUDGET_SHARE + 0.001,
				"tp %.0f cycle %d: boss stays inside the damage budget (%.0f <= %.0f)" % [
					tp, cycle, hp, budget * BattleMath.MAX_BUDGET_SHARE])
		check(rises, "tp %.0f: later cycles are never easier" % tp)


func _test_hp_floor() -> void:
	var ev: Dictionary = DL.get_event("inspection_frenzy")
	var floor_hp: float = float(ev.get("scaling", {}).get("min_hp", 30.0))
	check(is_equal_approx(BattleMath.stage_boss_hp(ev, 0, 0.0), floor_hp),
		"a zero-power team still faces a real boss, not an instant win")
	check(BattleMath.expected_damage(0.0, 20) == 0.0, "no team, no damage")
	check(BattleMath.expected_damage(-5.0, 20) == 0.0, "negative power clamps to zero")
	check(BattleMath.stage_moves(ev, 99) == 20, "out-of-range stage falls back to 20 moves")


func _test_reward_draw() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 4242
	for box_id in DL.lootboxes.keys():
		var box: Dictionary = DL.get_lootbox(box_id)
		var drawn: Dictionary = BattleMath.draw_cards(box, DL.managers, rng)
		var total := 0
		var valid := true
		for mid in drawn.keys():
			if not DL.managers.has(mid):
				valid = false
			total += int(drawn[mid])
		check(valid, "%s: all drawn ids are valid manager ids" % box_id)
		check(total == int(box.get("cards_total", 0)),
			"%s: drew exactly cards_total cards" % box_id)
	# Determinism with a fixed seed.
	var a := RandomNumberGenerator.new()
	var b := RandomNumberGenerator.new()
	a.seed = 99
	b.seed = 99
	var d1: Dictionary = BattleMath.draw_cards(
		DL.get_lootbox("executive_case"), DL.managers, a)
	var d2: Dictionary = BattleMath.draw_cards(
		DL.get_lootbox("executive_case"), DL.managers, b)
	check(d1 == d2, "seeded draws are deterministic")
