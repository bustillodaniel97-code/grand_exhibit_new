extends SceneTree
## tests/events/test_match3.gd — pure-logic engine tests (SPEC §6, §12).
## Run: godot --headless --path <repo> -s tests/events/test_match3.gd

const Match3 = preload("res://scripts/events/match3_engine.gd")

var failures := 0


func check(cond: bool, msg: String) -> void:
	if cond:
		print("PASS: ", msg)
	else:
		failures += 1
		printerr("FAIL: ", msg)


func _initialize() -> void:
	_test_generate_clean()
	_test_determinism()
	_test_revert_non_matching()
	_test_swap_clears_and_terminates()
	_test_charges_only_mapped_colors()
	_test_neutral_never_charges()
	_test_attack_fires_on_full_charge()
	_test_reshuffle()
	_test_focus_is_a_team_color()
	_test_focus_rerolls_only_when_satisfied()
	_test_focus_pays_more()
	_test_preview_matches_reality()
	_test_animation_snapshots()
	_test_legal_moves()
	quit(1 if failures > 0 else 0)


func _has_match(e) -> bool:
	return not e._find_matches().is_empty()


## Returns the result of the first adjacent swap that produces a match
## (non-matching probes revert harmlessly), or {} if none exists.
func _first_winning_swap(e) -> Dictionary:
	for y in 8:
		for x in 8:
			for d in [Vector2i(1, 0), Vector2i(0, 1)]:
				var a := Vector2i(x, y)
				var b: Vector2i = a + d
				if b.x >= 8 or b.y >= 8:
					continue
				var r: Dictionary = e.try_swap(a, b)
				if r["swapped"]:
					return r
	return {}


func _test_generate_clean() -> void:
	for seed in [1, 7, 42, 1337, 999983]:
		var e = Match3.new(seed)
		check(not _has_match(e), "generate() seed %d has no initial matches" % seed)
		check(e.grid().size() == 8 and e.grid()[0].size() == 8, "grid is 8x8")
		var valid := true
		for row in e.grid():
			for t in row:
				if t < 0 or t > 4:
					valid = false
		check(valid, "tile types within 0..4 (seed %d)" % seed)


func _test_determinism() -> void:
	var a = Match3.new(12345)
	var b = Match3.new(12345)
	check(a.grid() == b.grid(), "same seed -> identical board")
	a.set_team([0, 1, 2])
	b.set_team([0, 1, 2])
	check(a.focus_type() == b.focus_type(), "same seed -> identical audit focus")


func _test_revert_non_matching() -> void:
	var e = Match3.new(77)
	e.set_team([0, 1, 2])
	var before: Array = e.grid()
	var reverted := false
	for y in 8:
		for x in 7:
			var r: Dictionary = e.try_swap(Vector2i(x, y), Vector2i(x + 1, y))
			if not r["swapped"]:
				reverted = true
				break
		if reverted:
			break
	check(reverted, "found at least one non-matching swap")
	check(e.grid() == before, "non-matching swap leaves grid unchanged")
	# can_swap geometry.
	check(e.can_swap(Vector2i(0, 0), Vector2i(1, 0)), "adjacent horizontal swap allowed")
	check(e.can_swap(Vector2i(3, 3), Vector2i(3, 4)), "adjacent vertical swap allowed")
	check(not e.can_swap(Vector2i(0, 0), Vector2i(1, 1)), "diagonal swap rejected")
	check(not e.can_swap(Vector2i(0, 0), Vector2i(2, 0)), "distant swap rejected")
	check(not e.can_swap(Vector2i(0, 0), Vector2i(-1, 0)), "out-of-bounds swap rejected")


func _test_swap_clears_and_terminates() -> void:
	for seed in [3, 11, 555]:
		var e = Match3.new(seed)
		e.set_team([0, 1, 2])
		var r: Dictionary = _first_winning_swap(e)
		check(not r.is_empty(), "seed %d: a winning swap exists" % seed)
		if r.is_empty():
			continue
		check(int(r["tiles_cleared"]) >= 3, "cleared at least 3 tiles")
		check(r["events"].size() >= 1, "at least one resolve step")
		check(not _has_match(e), "cascades terminate: board stable after resolve (seed %d)" % seed)
		var stable := true
		for row in e.grid():
			for t in row:
				if t < 0 or t > 4:
					stable = false
		check(stable, "board fully refilled after gravity")


func _test_charges_only_mapped_colors() -> void:
	var e = Match3.new(2024)
	e.set_team([1, 2])  # ticket + archive managers; promotions/gallery unmapped
	var r: Dictionary = _first_winning_swap(e)
	check(not r.is_empty(), "charge test: winning swap found")
	if r.is_empty():
		return
	var matched_types := {}
	for ev in r["events"]:
		for m in ev["matches"]:
			matched_types[int(m["type"])] = true
	var charges: Array = r["charges"]
	for slot in charges.size():
		var color: int = [1, 2][slot]
		if float(charges[slot]) > 0.0:
			check(matched_types.has(color),
				"slot %d charged only because color %d matched" % [slot, color])
	# Unmapped colors must not have produced any charge anywhere:
	# with team [1,2] there is no slot for colors 0/3 — charges array has only 2 slots.
	check(charges.size() == 2, "one charge track per manager slot")
	if matched_types.has(1) or matched_types.has(2):
		var any_positive: bool = float(charges[0]) > 0.0 or float(charges[1]) > 0.0
		check(any_positive, "mapped color matches produce charge")


func _test_neutral_never_charges() -> void:
	var e = Match3.new(31415)
	e.set_team([4, 4, 4])  # every "manager" mapped to neutral brass
	check(e.focus_type() == -1, "all-neutral team has no audit focus to satisfy")
	var cleared_total := 0
	for i in 5:
		var r: Dictionary = _first_winning_swap(e)
		if r.is_empty():
			e.reshuffle()
			continue
		cleared_total += int(r["tiles_cleared"])
		for c in r["charges"]:
			check(float(c) == 0.0, "neutral matches never charge")
		for atk in r["attacks"]:
			check(false, "neutral mapping must not fire attacks (got %s)" % str(atk))
	check(cleared_total > 0, "neutral test actually cleared tiles")


func _test_attack_fires_on_full_charge() -> void:
	var e = Match3.new(2718)
	e.set_team([0])  # single promotions manager
	var attacks: Array = []
	var swaps := 0
	while attacks.is_empty() and swaps < 60:
		var r: Dictionary = _first_winning_swap(e)
		swaps += 1
		if r.is_empty():
			e.reshuffle()
			continue
		attacks.append_array(r["attacks"])
	check(not attacks.is_empty(), "charge fills to 100 and fires an attack within 60 swaps")
	if not attacks.is_empty():
		check(int(attacks[0]["manager_index"]) == 0, "attack carries manager_index 0")
		check(float(attacks[0]["charge_mult"]) >= 1.0, "attack charge_mult >= 1.0")


func _test_reshuffle() -> void:
	var e = Match3.new(8888)
	e.reshuffle()
	check(not _has_match(e), "reshuffle leaves no matches")
	check(not e.is_deadlocked(), "reshuffle leaves at least one legal move")


## --- audit focus: the board's only decision -------------------------------

func _test_focus_is_a_team_color() -> void:
	for seed in [5, 50, 500, 5000]:
		var e = Match3.new(seed)
		e.set_team([1, 3])
		check(e.focus_type() in [1, 3],
			"seed %d: audit focus is a colour the team actually fields" % seed)
	var empty = Match3.new(9)
	empty.set_team([])
	check(empty.focus_type() == -1, "empty team has no audit focus")


func _test_focus_rerolls_only_when_satisfied() -> void:
	var e = Match3.new(4242)
	e.set_team([0, 1, 2])
	var moves := 0
	var saw_hit := false
	var saw_miss := false
	while moves < 40 and not (saw_hit and saw_miss):
		var before: int = e.focus_type()
		var lm: Array = e.legal_moves()
		if lm.is_empty():
			e.reshuffle()
			continue
		var r: Dictionary = e.try_swap(lm[0]["a"], lm[0]["b"])
		moves += 1
		if not r["swapped"]:
			continue
		if bool(r["focus_hit"]):
			saw_hit = true
			check(int(r["focus_streak"]) >= 1, "satisfying the audit raises the chain")
		else:
			saw_miss = true
			check(int(r["focus"]) == before,
				"an unsatisfied audit stays put so the player can still find it")
			check(int(r["focus_streak"]) == 0, "missing the audit breaks the chain")
	check(saw_hit, "audit gets satisfied during normal play")
	check(saw_miss, "audit can also be missed — it is a real choice")


## The focus bonus has to be worth chasing, or the board is a tap tax again.
func _test_focus_pays_more() -> void:
	var focus_charge := 0.0
	var other_charge := 0.0
	for seed in range(40):
		var e = Match3.new(7000 + seed * 13)
		e.set_team([0, 1, 2])
		var f: int = e.focus_type()
		var best_focus := {}
		var best_other := {}
		for mv in e.legal_moves():
			var pv: Dictionary = e.preview_swap(mv["a"], mv["b"])
			if int(pv["focus"]) > 0 and best_focus.is_empty():
				best_focus = mv
			elif int(pv["focus"]) == 0 and int(pv["total"]) >= 3 and best_other.is_empty():
				best_other = mv
		if best_focus.is_empty() or best_other.is_empty():
			continue
		var a = Match3.new(7000 + seed * 13)
		a.set_team([0, 1, 2])
		var ra: Dictionary = a.try_swap(best_focus["a"], best_focus["b"])
		for c in ra["charges"]:
			focus_charge += float(c)
		for atk in ra["attacks"]:
			focus_charge += 100.0 * float(atk["charge_mult"])
		var b = Match3.new(7000 + seed * 13)
		b.set_team([0, 1, 2])
		var rb: Dictionary = b.try_swap(best_other["a"], best_other["b"])
		for c in rb["charges"]:
			other_charge += float(c)
		for atk in rb["attacks"]:
			other_charge += 100.0 * float(atk["charge_mult"])
	check(focus_charge > other_charge * 1.15,
		"chasing the audit colour pays: %.0f vs %.0f charge over 40 boards" % [
			focus_charge, other_charge])


func _test_preview_matches_reality() -> void:
	var checked := 0
	for seed in [11, 22, 33, 44]:
		var e = Match3.new(seed)
		e.set_team([0, 1, 2])
		for mv in e.legal_moves():
			var pv: Dictionary = e.preview_swap(mv["a"], mv["b"])
			var live = Match3.new(seed)
			live.set_team([0, 1, 2])
			var r: Dictionary = live.try_swap(mv["a"], mv["b"])
			var first_step: Dictionary = r["events"][0]
			# match-4/5 clear extra lines beyond the run, so the preview is a
			# SUBSET of the real first step, never a superset.
			var actually_cleared: bool = true
			for c in pv["cells"]:
				if not (c in first_step["cells"]):
					actually_cleared = false
			check(actually_cleared,
				"preview_swap cells are all cleared for real (seed %d)" % seed)
			check(int(pv["total"]) >= 3, "a previewed legal move clears 3+ tiles")
			checked += 1
			break
	check(checked == 4, "preview verified on every probed seed")


## The view replays these snapshots to animate the cascade; if they drift from
## the engine's own board the display silently lies about the game state.
func _test_animation_snapshots() -> void:
	var e = Match3.new(60606)
	e.set_team([0, 1, 2])
	var r: Dictionary = _first_winning_swap(e)
	check(not r.is_empty(), "snapshot test: winning swap found")
	if r.is_empty():
		return
	check(r["grid_before"].size() == 8, "result carries the post-swap board")
	var events: Array = r["events"]
	for ev in events:
		check((ev as Dictionary).has("cells"), "each cascade step lists its cleared cells")
		check(int(ev["cleared"]) == (ev["cells"] as Array).size(),
			"cleared count matches the cell list")
		check((ev["grid_after"] as Array).size() == 8,
			"each cascade step carries the board it produced")
	check(events[events.size() - 1]["grid_after"] == e.grid(),
		"the last snapshot IS the engine's final board")


func _test_legal_moves() -> void:
	var e = Match3.new(31337)
	e.set_team([0, 1, 2])
	var moves: Array = e.legal_moves()
	check(not moves.is_empty(), "a fresh board has legal moves")
	var all_match := true
	for mv in moves:
		if not e.would_match(mv["a"], mv["b"]):
			all_match = false
	check(all_match, "every reported legal move really produces a match")
	check(e.legal_moves(1).size() == 1, "limit stops the scan early")
	check(e.is_deadlocked() == moves.is_empty(), "is_deadlocked agrees with legal_moves")
