extends RefCounted
## Deterministic 8x8 match-3 battler engine (SPEC §6). Pure logic, no nodes.
## Tiles: 0=promotions, 1=ticket, 2=archive, 3=gallery, 4=neutral brass.
## Neutral tiles never charge. All randomness flows through one seeded RNG.
##
## AUDIT FOCUS. A board with ~18 legal moves at every instant and no reason to
## prefer one over another is a tap tax, not a game: measured, a colour-aware
## player beat a first-legal-move player by 1.8%. The inspector now audits ONE
## department at a time and tiles of that colour charge at FOCUS_CHARGE_MULT, so
## every move is a search for a specific colour and the focus re-rolls the moment
## the player satisfies it. That is the whole decision space, and it is worth
## roughly a third of the damage budget (see tests/events/test_battle_balance.gd).

const SIZE := 8
const TYPE_COUNT := 5
const NEUTRAL := 4
const CHARGE_FULL := 100.0
## Tiles of one colour that fill a manager's charge bar. Was 12, which bought a
## 20-move battle only ~5 damage events end to end — long stretches where nothing
## happened. At 6 a manager fires roughly every other move, which both reads as
## responsive and tightens the outcome distribution enough to tune win rates.
const CHARGE_TILES := 6
const CHARGE_PER_TILE := CHARGE_FULL / float(CHARGE_TILES)
const CASCADE_MULT := 1.25             # charge multiplier per cascade step
const MATCH4_CHARGE_MULT := 1.5
const MATCH5_CHARGE_MULT := 2.5
const FOCUS_CHARGE_MULT := 1.8         # audited department pays this much more
## Satisfying the audit on consecutive moves compounds the bonus. Small on
## purpose: it is there so the chain counter on the HUD means something and so a
## run of good reads feels like a run, not so that one lucky chain wins a fight.
const FOCUS_CHAIN_STEP := 0.2
const FOCUS_CHAIN_MAX := 3
const MAX_CASCADE_STEPS := 64          # safety cap; cascades terminate long before

var _rng := RandomNumberGenerator.new()
var _grid: Array = []      # _grid[y][x] -> int tile type
var _team: Array = []      # manager slot -> tile type 0..3 (-1 = empty slot)
var _charges: Array = []   # manager slot -> float charge 0..100
var _focus := -1           # audited tile type, or -1 when the team owns no colour
var _focus_streak := 0     # consecutive moves that satisfied the audit


func _init(seed: int = 0) -> void:
	_rng.seed = seed
	generate()


## Team = tile type per manager slot (specialty mapping done by caller).
func set_team(tile_types: Array) -> void:
	_team = tile_types.duplicate()
	_charges.clear()
	for i in _team.size():
		_charges.append(0.0)
	_focus_streak = 0
	_roll_focus()


func get_charges() -> Array:
	return _charges.duplicate()


## Tile type the inspector is currently auditing, or -1 when the team fields no
## colour that could satisfy one (all-neutral or empty team).
func focus_type() -> int:
	return _focus


func focus_streak() -> int:
	return _focus_streak


## Charge multiplier the audited colour is paying RIGHT NOW, chain included.
func focus_multiplier() -> float:
	return FOCUS_CHARGE_MULT + FOCUS_CHAIN_STEP * float(mini(_focus_streak, FOCUS_CHAIN_MAX))


## Colours the team actually fields, deduplicated, neutral excluded.
func _team_colors() -> Array:
	var seen := {}
	for t in _team:
		var ti: int = int(t)
		if ti >= 0 and ti < NEUTRAL:
			seen[ti] = true
	return seen.keys()


## Rolls a new audit colour, preferring one different from the current focus so
## the player is asked to move their eyes rather than re-match the same colour.
func _roll_focus() -> void:
	var colors: Array = _team_colors()
	if colors.is_empty():
		_focus = -1
		return
	var pool: Array = []
	for c in colors:
		if int(c) != _focus:
			pool.append(c)
	if pool.is_empty():
		pool = colors
	_focus = int(pool[_rng.randi_range(0, pool.size() - 1)])


func grid() -> Array:
	var out: Array = []
	for row in _grid:
		out.append(row.duplicate())
	return out


## Fills the board with no initial matches.
func generate() -> void:
	_grid.clear()
	for y in SIZE:
		var row: Array = []
		for x in SIZE:
			row.append(_pick_type_avoiding_match(x, y, row))
		_grid.append(row)


func _pick_type_avoiding_match(x: int, y: int, row: Array) -> int:
	var forbidden := {}
	if x >= 2 and row[x - 1] == row[x - 2]:
		forbidden[row[x - 1]] = true
	if y >= 2 and _grid[y - 1][x] == _grid[y - 2][x]:
		forbidden[_grid[y - 1][x]] = true
	var candidates: Array = []
	for t in TYPE_COUNT:
		if not forbidden.has(t):
			candidates.append(t)
	return candidates[_rng.randi_range(0, candidates.size() - 1)]


func _inside(p: Vector2i) -> bool:
	return p.x >= 0 and p.x < SIZE and p.y >= 0 and p.y < SIZE


func can_swap(a: Vector2i, b: Vector2i) -> bool:
	if not _inside(a) or not _inside(b):
		return false
	var d: Vector2i = (a - b).abs()
	return d.x + d.y == 1


## True when swapping a and b would produce at least one match. Lets the view
## answer "is this a legal move" without mutating the board.
func would_match(a: Vector2i, b: Vector2i) -> bool:
	if not can_swap(a, b):
		return false
	_swap_cells(a, b)
	var ok: bool = _match_at(a) or _match_at(b)
	_swap_cells(a, b)
	return ok


## What the FIRST cascade step of this swap would clear, without mutating the
## board: {cells:Array[Vector2i], total:int, focus:int}. Powers the idle hint in
## the view and the solver harness that tunes boss pressure — both have to rank a
## move before committing to it. Types are read INSIDE the hypothetical swap, so
## the two swapped tiles are counted at their new positions.
func preview_swap(a: Vector2i, b: Vector2i) -> Dictionary:
	if not can_swap(a, b):
		return {"cells": [], "total": 0, "focus": 0}
	_swap_cells(a, b)
	var cells := {}
	for g in _find_matches():
		for c in g["cells"]:
			cells[c] = true
	var focus := 0
	for c in cells.keys():
		if _grid[c.y][c.x] == _focus:
			focus += 1
	_swap_cells(a, b)
	return {"cells": cells.keys(), "total": cells.size(), "focus": focus}


## Attempts a swap. Non-matching swaps are reverted.
## Returns {swapped, events, attacks, charges, tiles_cleared, focus, focus_hit,
## focus_streak, grid_before}.
## events = one Dictionary per cascade step:
##   {step, matches:[{type, size, kind}], cleared:int, cells:Array[Vector2i],
##    grid_after:Array, attacks:[{manager_index, charge_mult}]}
## `cells` and `grid_after` exist so the view can animate the cascade instead of
## snapping the board; they are the only reason the engine keeps snapshots.
func try_swap(a: Vector2i, b: Vector2i) -> Dictionary:
	var result := {"swapped": false, "events": [], "attacks": [],
		"charges": get_charges(), "tiles_cleared": 0,
		"focus": _focus, "focus_hit": false, "focus_streak": _focus_streak,
		"grid_before": grid()}
	if not can_swap(a, b):
		return result
	_swap_cells(a, b)
	if _find_matches().is_empty():
		_swap_cells(a, b)
		return result
	result["swapped"] = true
	result["grid_before"] = grid()  # post-swap, pre-clear: what the swap tween lands on
	var resolved: Dictionary = _resolve()
	result["events"] = resolved["events"]
	result["attacks"] = resolved["attacks"]
	result["tiles_cleared"] = resolved["tiles_cleared"]
	var hit: bool = int(resolved["focus_cleared"]) > 0 and _focus >= 0
	if hit:
		_focus_streak += 1
		_roll_focus()
	elif _focus >= 0:
		_focus_streak = 0
	result["focus_hit"] = hit
	result["focus_streak"] = _focus_streak
	result["focus"] = _focus
	result["charges"] = get_charges()
	return result


func _swap_cells(a: Vector2i, b: Vector2i) -> void:
	var tmp: int = _grid[a.y][a.x]
	_grid[a.y][a.x] = _grid[b.y][b.x]
	_grid[b.y][b.x] = tmp


## Finds all match groups (3+ in a row/column). Returns Array of
## {type:int, cells:Array[Vector2i]}; runs of 4/5 stay one group.
func _find_matches() -> Array:
	var groups: Array = []
	# Horizontal runs.
	for y in SIZE:
		var x := 0
		while x < SIZE:
			var t: int = _grid[y][x]
			var run := 1
			while x + run < SIZE and _grid[y][x + run] == t:
				run += 1
			if run >= 3:
				var cells: Array = []
				for i in run:
					cells.append(Vector2i(x + i, y))
				groups.append({"type": t, "cells": cells})
			x += run
	# Vertical runs.
	for x in SIZE:
		var y := 0
		while y < SIZE:
			var t: int = _grid[y][x]
			var run := 1
			while y + run < SIZE and _grid[y + run][x] == t:
				run += 1
			if run >= 3:
				var cells: Array = []
				for i in run:
					cells.append(Vector2i(x, y + i))
				groups.append({"type": t, "cells": cells})
			y += run
	return groups


## Resolves the board: match -> score/charge -> clear -> gravity -> refill,
## looping cascades until stable.
## Returns {events, attacks, tiles_cleared, focus_cleared}.
func _resolve() -> Dictionary:
	var events: Array = []
	var all_attacks: Array = []
	var total_cleared := 0
	var focus_cleared := 0
	var step := 0
	while step < MAX_CASCADE_STEPS:
		var groups := _find_matches()
		if groups.is_empty():
			break
		var step_mult: float = pow(CASCADE_MULT, step)
		var clear_set := {}
		var match_descs: Array = []
		var attacks: Array = []
		for g in groups:
			var t: int = g["type"]
			var cells: Array = g["cells"]
			var kind := 3
			var kind_mult := 1.0
			var affected := {}  # Vector2i -> true (this group's cleared cells)
			for c in cells:
				affected[c] = true
			if cells.size() >= 5:
				kind = 5
				kind_mult = MATCH5_CHARGE_MULT
				for c in _cells_of_type(t):
					affected[c] = true
			elif cells.size() == 4:
				kind = 4
				kind_mult = MATCH4_CHARGE_MULT
				for c in _line_cells(cells):
					affected[c] = true
			# Charge managers mapped to this color by tiles of that color cleared.
			if t != NEUTRAL:
				var n_of_type := 0
				for c in affected.keys():
					if _grid[c.y][c.x] == t:
						n_of_type += 1
				if t == _focus:
					focus_cleared += n_of_type
					kind_mult *= focus_multiplier()
				var amount: float = CHARGE_PER_TILE * float(n_of_type) * kind_mult * step_mult
				for slot in _team.size():
					if int(_team[slot]) == t:
						_charges[slot] = float(_charges[slot]) + amount
						if float(_charges[slot]) >= CHARGE_FULL:
							var atk := {"manager_index": slot,
								"charge_mult": float(_charges[slot]) / CHARGE_FULL}
							attacks.append(atk)
							_charges[slot] = 0.0
			for c in affected.keys():
				clear_set[c] = true
			match_descs.append({"type": t, "size": cells.size(), "kind": kind})
		var cleared_this_step: int = clear_set.size()
		total_cleared += cleared_this_step
		var cells_list: Array = clear_set.keys()
		_clear_and_refill(clear_set)
		events.append({"step": step, "matches": match_descs,
			"cleared": cleared_this_step, "cells": cells_list,
			"grid_after": grid(), "attacks": attacks})
		all_attacks.append_array(attacks)
		step += 1
	return {"events": events, "attacks": all_attacks,
		"tiles_cleared": total_cleared, "focus_cleared": focus_cleared}


func _cells_of_type(t: int) -> Array:
	var out: Array = []
	for y in SIZE:
		for x in SIZE:
			if _grid[y][x] == t:
				out.append(Vector2i(x, y))
	return out


## Full row or column containing a 4-match (orientation from the run's cells).
func _line_cells(cells: Array) -> Array:
	var out: Array = []
	var first: Vector2i = cells[0]
	var second: Vector2i = cells[1]
	if first.y == second.y:  # horizontal run -> clear the row
		for x in SIZE:
			out.append(Vector2i(x, first.y))
	else:  # vertical run -> clear the column
		for y in SIZE:
			out.append(Vector2i(first.x, y))
	return out


func _clear_and_refill(clear_set: Dictionary) -> void:
	for c in clear_set.keys():
		_grid[c.y][c.x] = -1
	# Gravity per column: compact down, refill from the top.
	for x in SIZE:
		var kept: Array = []
		for y in SIZE:
			if _grid[y][x] != -1:
				kept.append(_grid[y][x])
		var missing: int = SIZE - kept.size()
		for y in missing:
			_grid[y][x] = _rng.randi_range(0, TYPE_COUNT - 1)
		for i in kept.size():
			_grid[missing + i][x] = kept[i]


## True when no legal swap would produce a match.
func is_deadlocked() -> bool:
	return legal_moves(1).is_empty()


## Every swap that would produce a match, as [{a:Vector2i, b:Vector2i}].
## `limit` > 0 stops early (is_deadlocked only needs to know whether one exists).
func legal_moves(limit: int = 0) -> Array:
	var out: Array = []
	for y in SIZE:
		for x in SIZE:
			var p := Vector2i(x, y)
			for dir in [Vector2i(1, 0), Vector2i(0, 1)]:
				var q: Vector2i = p + dir
				if not _inside(q):
					continue
				_swap_cells(p, q)
				var makes_match: bool = _match_at(p) or _match_at(q)
				_swap_cells(p, q)
				if makes_match:
					out.append({"a": p, "b": q})
					if limit > 0 and out.size() >= limit:
						return out
	return out


func _match_at(p: Vector2i) -> bool:
	var t: int = _grid[p.y][p.x]
	var run_h := 1
	var x: int = p.x - 1
	while x >= 0 and _grid[p.y][x] == t:
		run_h += 1
		x -= 1
	x = p.x + 1
	while x < SIZE and _grid[p.y][x] == t:
		run_h += 1
		x += 1
	if run_h >= 3:
		return true
	var run_v := 1
	var y: int = p.y - 1
	while y >= 0 and _grid[y][p.x] == t:
		run_v += 1
		y -= 1
	y = p.y + 1
	while y < SIZE and _grid[y][p.x] == t:
		run_v += 1
		y += 1
	return run_v >= 3


## Shuffles the existing tiles in place until the board has no matches
## and at least one legal move (used when deadlocked mid-battle).
func reshuffle() -> void:
	var flat: Array = []
	for y in SIZE:
		for x in SIZE:
			flat.append(_grid[y][x])
	for attempt in 100:
		# Fisher-Yates with the engine RNG (deterministic).
		for i in range(flat.size() - 1, 0, -1):
			var j: int = _rng.randi_range(0, i)
			var tmp: int = flat[i]
			flat[i] = flat[j]
			flat[j] = tmp
		var idx := 0
		for y in SIZE:
			for x in SIZE:
				_grid[y][x] = flat[idx]
				idx += 1
		if _find_matches().is_empty() and not is_deadlocked():
			return
	# Fallback (practically unreachable): fresh board.
	generate()
