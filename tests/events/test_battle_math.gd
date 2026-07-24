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
	_test_final_stage_ratio()
	_test_team_power_scaling()
	_test_expedition_cycle_scaling()
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
	check(is_equal_approx(BattleMath.manager_attack(def, {"level": 1, "rank": 2}), bp * 1.5),
		"attack rank2 = battle_power * 1.5")
	check(is_equal_approx(BattleMath.manager_attack(def, {"level": 5, "rank": 4}), bp * 1.48 * 3.5),
		"attack level5/rank4 = battle_power * 1.48 * 3.5")
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
	# Formula sanity: stage 1 (i=0) at team_power 0 -> base_hp exactly.
	var base: float = float(ev.get("scaling", {}).get("base_hp", 500.0))
	check(is_equal_approx(BattleMath.stage_boss_hp(ev, 0, 0.0), base),
		"stage 0 hp at zero team power = base_hp")


func _test_final_stage_ratio() -> void:
	var ev: Dictionary = DL.get_event("inspection_frenzy")
	var stages: Array = ev.get("stages", [])
	var need: float = float(ev.get("scaling", {}).get("final_stage_power_need", 1.5))
	for tp in [50.0, 100.0, 1000.0]:
		var first: float = BattleMath.stage_boss_hp(ev, 0, tp)
		var last: float = BattleMath.stage_boss_hp(ev, stages.size() - 1, tp)
		check(last / first >= need,
			"last/first hp ratio %.1f >= final_stage_power_need (tp=%s)" % [last / first, str(tp)])


func _test_team_power_scaling() -> void:
	var ev: Dictionary = DL.get_event("inspection_frenzy")
	var low: float = BattleMath.stage_boss_hp(ev, 2, 0.0)
	var high: float = BattleMath.stage_boss_hp(ev, 2, 400.0)
	check(high > low, "boss hp scales up with team power")
	var ev2: Dictionary = ev.duplicate(true)
	ev2["scaling"] = ev.get("scaling", {}).duplicate()
	ev2["scaling"]["hp_vs_power"] = 0.9
	var s0: float = BattleMath.stage_boss_hp(ev2, 2, 100.0)
	var s1: float = BattleMath.stage_boss_hp(ev2, 2, 200.0)
	check(is_equal_approx(s1 / s0, pow(2.0, 0.9)),
		"doubling team power scales hp by 2^hp_vs_power")


func _test_expedition_cycle_scaling() -> void:
	var boss: Dictionary = DL.get_event("expedition").get("boss", {})
	var c0: float = BattleMath.expedition_boss_hp(boss, 100.0, 0)
	var c1: float = BattleMath.expedition_boss_hp(boss, 100.0, 1)
	var c2: float = BattleMath.expedition_boss_hp(boss, 100.0, 2)
	check(is_equal_approx(c1 / c0, 1.25), "boss hp +25% per cycle")
	check(is_equal_approx(c2 / c0, 1.5625), "boss hp compounds over two cycles")


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
