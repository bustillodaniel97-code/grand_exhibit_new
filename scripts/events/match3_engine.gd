extends RefCounted
## Deterministic 8x8 match-3 battler engine (SPEC §6). Pure logic, no nodes.
## Tiles: 0=promotions, 1=ticket, 2=archive, 3=gallery, 4=neutral brass.
## Neutral tiles never charge. All randomness flows through one seeded RNG.

const SIZE := 8
const TYPE_COUNT := 5
const NEUTRAL := 4
const CHARGE_FULL := 100.0
const CHARGE_PER_TILE := 100.0 / 12.0  # 12 cleared tiles of a color = full charge
const CASCADE_MULT := 1.25             # charge multiplier per cascade step
const MATCH4_CHARGE_MULT := 1.5
const MATCH5_CHARGE_MULT := 2.5
const MAX_CASCADE_STEPS := 64          # safety cap; cascades terminate long before

var _rng := RandomNumberGenerator.new()
var _grid: Array = []      # _grid[y][x] -> int tile type
var _team: Array = []      # manager slot -> tile type 0..3 (-1 = empty slot)
var _charges: Array = []   # manager slot -> float charge 0..100


func _init(seed: int = 0) -> void:
	_rng.seed = seed
	generate()


## Team = tile type per manager slot (specialty mapping done by caller).
func set_team(tile_types: Array) -> void:
	_team = tile_types.duplicate()
	_charges.clear()
	for i in _team.size():
		_charges.append(0.0)


func get_charges() -> Array:
	return _charges.duplicate()


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


## Attempts a swap. Non-matching swaps are reverted.
## Returns {swapped, events, attacks, charges, tiles_cleared}.
## events = one Dictionary per cascade step:
##   {step, matches:[{type, size, kind}], cleared:int, attacks:[{manager_index, charge_mult}]}
func try_swap(a: Vector2i, b: Vector2i) -> Dictionary:
	var result := {"swapped": false, "events": [], "attacks": [],
		"charges": get_charges(), "tiles_cleared": 0}
	if not can_swap(a, b):
		return result
	_swap_cells(a, b)
	if _find_matches().is_empty():
		_swap_cells(a, b)
		return result
	result["swapped"] = true
	var resolved: Dictionary = _resolve()
	result["events"] = resolved["events"]
	result["attacks"] = resolved["attacks"]
	result["tiles_cleared"] = resolved["tiles_cleared"]
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
## looping cascades until stable. Returns {events, attacks, tiles_cleared}.
func _resolve() -> Dictionary:
	var events: Array = []
	var all_attacks: Array = []
	var total_cleared := 0
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
		events.append({"step": step, "matches": match_descs,
			"cleared": cleared_this_step, "attacks": attacks})
		all_attacks.append_array(attacks)
		_clear_and_refill(clear_set)
		step += 1
	return {"events": events, "attacks": all_attacks, "tiles_cleared": total_cleared}


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
					return false
	return true


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
