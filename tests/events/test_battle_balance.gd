extends SceneTree
## tests/events/test_battle_balance.gd — the solver harness that turns "is this
## fight fair" into something the battery can hold (SPEC §6, §12).
## Run: godot --headless --path <repo> -s tests/events/test_battle_balance.gd
##
## It plays real battles on the real engine with a REFERENCE PLAYER: takes the
## best audit-focus move `skill` of the time and a random legal move otherwise.
## Everything is seeded, so a tuning change moves these numbers deterministically
## instead of flaking. This is also where BattleMath.DAMAGE_PER_POWER_PER_MOVE is
## calibrated from — if that constant drifts from measured throughput, the
## calibration check below fails and every boss in the game is mis-quoted.

const Match3 = preload("res://scripts/events/match3_engine.gd")
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
const SPEC_TO_TILE := {"promotions": 0, "ticket": 1, "archive": 2, "gallery": 3}
## An attentive human, not a solver. Boss pressure in events.json is quoted
## against this player.
const REFERENCE_SKILL := 0.7
const TRIALS := 60

var failures := 0
var DL


func check(cond: bool, msg: String) -> void:
	if cond:
		print("PASS: ", msg)
	else:
		failures += 1
		printerr("FAIL: ", msg)


func _initialize() -> void:
	for n in AUTOLOADS.keys():
		if not root.has_node(n):
			var node: Node = load(AUTOLOADS[n]).new()
			node.name = n
			root.add_child(node)
	DL = root.get_node("DataLoader")
	DL.reload_all()
	_test_calibration_still_holds()
	_test_stage_one_is_winnable()
	_test_difficulty_ramps_without_walls()
	_test_collecting_managers_never_hurts()
	_test_focus_is_worth_playing_for()
	_test_no_battle_ever_locks_up()
	quit(1 if failures > 0 else 0)


func _team(level: int, rank: int) -> Array:
	var out: Array = []
	for mid in ["barker_theo", "docent_poppy", "archivist_mabel"]:
		out.append({"def": DL.get_manager_def(mid), "state": {"level": level, "rank": rank}})
	return out


## Plays `trials` seeded battles to the end of the move budget and returns every
## battle's total damage, sorted. Damage does not depend on boss HP, so one
## sample answers the win rate for any HP.
func _damages(team: Array, moves: int, trials: int, skill: float) -> Array:
	var rng := RandomNumberGenerator.new()
	var types: Array = []
	for m in team:
		types.append(int(SPEC_TO_TILE.get(str(m["def"].get("specialty", "")), -1)))
	var out: Array = []
	for s in trials:
		var e = Match3.new(1000 + s * 37)
		rng.seed = 555 + s
		e.set_team(types)
		var dmg := 0.0
		var left := moves
		var guard := 0
		while left > 0 and guard < moves * 20:
			guard += 1
			var lm: Array = e.legal_moves()
			if lm.is_empty():
				e.reshuffle()
				continue
			var pick: Dictionary = lm[rng.randi_range(0, lm.size() - 1)]
			if rng.randf() < skill:
				var best := -1.0
				for mv in lm:
					var pv: Dictionary = e.preview_swap(mv["a"], mv["b"])
					var score: float = float(pv["focus"]) * 10.0 + float(pv["total"])
					if score > best:
						best = score
						pick = mv
			var r: Dictionary = e.try_swap(pick["a"], pick["b"])
			left -= 1
			for a in r["attacks"]:
				dmg += BattleMath.manager_attack(
					team[int(a["manager_index"])]["def"],
					team[int(a["manager_index"])]["state"]) * float(a["charge_mult"])
		out.append(dmg)
	out.sort()
	return out


func _win_rate(damages: Array, hp: float) -> float:
	var wins := 0
	for d in damages:
		if float(d) >= hp:
			wins += 1
	return float(wins) / float(maxi(damages.size(), 1))


## BattleMath quotes every boss in the game as a share of expected_damage(). If
## that constant no longer matches what the board actually pays out, every
## pressure value in events.json silently means something else.
func _test_calibration_still_holds() -> void:
	var team := _team(5, 1)
	var tp: float = BattleMath.team_power(team)
	var d: Array = _damages(team, 22, TRIALS * 2, REFERENCE_SKILL)
	var mean := 0.0
	for v in d:
		mean += float(v)
	mean /= float(d.size())
	var predicted: float = BattleMath.expected_damage(tp, 22)
	var err: float = absf(mean / predicted - 1.0)
	check(err < 0.12, "expected_damage predicts real throughput within 12% "
		+ "(predicted %.0f, measured %.0f, err %.1f%%)" % [predicted, mean, err * 100.0])


## The headline regression: a fresh three-manager team clears stage 1 on a solid
## majority of seeds. The shipped build won 2 of 20.
func _test_stage_one_is_winnable() -> void:
	var ev: Dictionary = DL.get_event("inspection_frenzy")
	for desc in [["a day-one Lv1 team", 1, 1], ["an early Lv5 team", 5, 1]]:
		var team := _team(int(desc[1]), int(desc[2]))
		var tp: float = BattleMath.team_power(team)
		var moves: int = BattleMath.stage_moves(ev, 0)
		var rate: float = _win_rate(_damages(team, moves, TRIALS, REFERENCE_SKILL),
			BattleMath.stage_boss_hp(ev, 0, tp))
		check(rate >= 0.6, "%s clears stage 1 on most seeds (%.0f%%)" % [str(desc[0]), rate * 100.0])
		check(rate <= 0.98, "%s does not clear stage 1 for free (%.0f%%)" % [
			str(desc[0]), rate * 100.0])


func _test_difficulty_ramps_without_walls() -> void:
	var ev: Dictionary = DL.get_event("inspection_frenzy")
	var team := _team(5, 1)
	var tp: float = BattleMath.team_power(team)
	var rates: Array = []
	var cache := {}
	for i in (ev.get("stages", []) as Array).size():
		var moves: int = BattleMath.stage_moves(ev, i)
		if not cache.has(moves):
			cache[moves] = _damages(team, moves, TRIALS, REFERENCE_SKILL)
		rates.append(_win_rate(cache[moves], BattleMath.stage_boss_hp(ev, i, tp)))
	var descending := true
	for i in range(1, rates.size()):
		if float(rates[i]) > float(rates[i - 1]) + 0.05:
			descending = false
	check(descending, "win rate falls across the stage ladder %s" % str(rates))
	check(float(rates[rates.size() - 1]) >= 0.2,
		"the last stage is a challenge, not a wall (%.0f%%)" % [float(rates[-1]) * 100.0])
	check(float(rates[rates.size() - 1]) <= 0.7,
		"the last stage still means something (%.0f%%)" % [float(rates[-1]) * 100.0])
	# Expedition boss on the same footing.
	var boss: Dictionary = DL.get_event("expedition").get("boss", {})
	var bmoves: int = int(boss.get("moves", 24))
	var brate: float = _win_rate(_damages(team, bmoves, TRIALS, REFERENCE_SKILL),
		BattleMath.expedition_boss_hp(boss, tp, 0))
	check(brate >= 0.3, "the Guardian is beatable by an early team (%.0f%%)" % [brate * 100.0])


## THE inversion regression. Collecting and levelling managers is the event's own
## reward; it must never make the event harder. The shipped build scaled boss HP
## on the whole owned roster while damage came from the three brought along, so
## 14 Lv5 managers turned stage 1 from 120 HP into 959.
func _test_collecting_managers_never_hurts() -> void:
	var ev: Dictionary = DL.get_event("inspection_frenzy")
	var moves: int = BattleMath.stage_moves(ev, 5)
	var prev := -1.0
	var ladder: Array = []
	for desc in [[1, 1], [5, 1], [20, 2], [50, 4]]:
		var team := _team(int(desc[0]), int(desc[1]))
		var tp: float = BattleMath.team_power(team)
		var rate: float = _win_rate(_damages(team, moves, TRIALS, REFERENCE_SKILL),
			BattleMath.stage_boss_hp(ev, 5, tp))
		ladder.append(rate)
		check(rate >= prev - 0.03,
			"Lv%d rank%d is not worse off than the weaker team below it (%.0f%%)" % [
				int(desc[0]), int(desc[1]), rate * 100.0])
		prev = rate
	check(float(ladder[-1]) > float(ladder[0]) + 0.15,
		"growing the team visibly pays off on the hardest stage %s" % str(ladder))


## Without a reason to prefer one match over another the board is a tap tax: the
## shipped build's colour-aware player beat a first-legal-move player by 1.8%.
func _test_focus_is_worth_playing_for() -> void:
	var team := _team(5, 1)
	var blind: Array = _damages(team, 22, TRIALS, 0.0)
	var sharp: Array = _damages(team, 22, TRIALS, 1.0)
	var mb := 0.0
	var ms := 0.0
	for v in blind:
		mb += float(v)
	for v in sharp:
		ms += float(v)
	mb /= float(blind.size())
	ms /= float(sharp.size())
	check(ms > mb * 1.25, "chasing the audit is worth >25% more damage "
		+ "(%.0f vs %.0f, +%.0f%%)" % [ms, mb, (ms / mb - 1.0) * 100.0])


## A battle that cannot be advanced is a soft lock. The engine must always leave
## a legal move on the board, deadlock or not.
func _test_no_battle_ever_locks_up() -> void:
	var stuck := 0
	var reshuffles := 0
	for s in 40:
		var e = Match3.new(90000 + s * 991)
		e.set_team([0, 1, 2])
		for move in 25:
			if e.is_deadlocked():
				reshuffles += 1
				e.reshuffle()
				if e.is_deadlocked():
					stuck += 1
					break
			var lm: Array = e.legal_moves(1)
			if lm.is_empty():
				stuck += 1
				break
			e.try_swap(lm[0]["a"], lm[0]["b"])
	check(stuck == 0, "40 battles x 25 moves never reached a state with no legal move")
	print("  (deadlock reshuffles fired: %d)" % reshuffles)
