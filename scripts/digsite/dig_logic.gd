extends RefCounted
## DigLogic — the rules of one excavation site, as plain data. No class_name.
##
## A SITE is a Dictionary so it saves as-is inside GameState.dig_state:
##   venue, artifact (id), cols, rows, layers (Array[int], soil left per cell),
##   rock (Array[int] cell indices), art_cells (Array[int]), flags (survey
##   markers on a few artifact cells), finds ({"idx": {kind, amount, taken}}),
##   damage (cracks from the pick), done.
##
## Tools: the pick clears `depth` 2, the brush 1. The pick CRACKS the artifact
## when it breaks through onto one of its cells (its swing leaves that cell
## bare); the brush never does. A cell one layer above the artifact "peeks" (the
## view shows bone through the soil), which is what makes the brush a decision
## rather than a chore. Rock only yields to the pick, one layer per swing.

static func idx(site: Dictionary, x: int, y: int) -> int:
	return y * int(site["cols"]) + x

static func in_bounds(site: Dictionary, x: int, y: int) -> bool:
	return x >= 0 and y >= 0 and x < int(site["cols"]) and y < int(site["rows"])

## Lay out a fresh site. `art` is the artifact def from dig_sites.json.
static func generate(venue_id: String, art: Dictionary, cfg: Dictionary, seed_value: int) -> Dictionary:
	var grid: Dictionary = cfg.get("grid", {})
	var cols := int(grid.get("cols", 7))
	var rows := int(grid.get("rows", 9))
	var depth := int(grid.get("layers", 3))
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var fp: Array = art.get("cells", [[0, 0]])
	var w := 1
	var h := 1
	for c in fp:
		w = maxi(w, int(c[0]) + 1)
		h = maxi(h, int(c[1]) + 1)
	var ox := rng.randi_range(1, maxi(1, cols - w - 1))
	var oy := rng.randi_range(1, maxi(1, rows - h - 1))
	var site := {"venue": venue_id, "artifact": str(art.get("id", "")), "cols": cols, "rows": rows,
		"origin": [ox, oy], "layers": [], "rock": [], "art_cells": [], "flags": [], "finds": {},
		"damage": 0, "done": false, "seed": seed_value}
	var layers: Array = []
	layers.resize(cols * rows)
	layers.fill(depth)
	site["layers"] = layers
	var art_cells: Array = []
	for c in fp:
		art_cells.append(idx(site, ox + int(c[0]), oy + int(c[1])))
	site["art_cells"] = art_cells
	var free: Array = []
	for i in cols * rows:
		if i not in art_cells:
			free.append(i)
	_shuffle(free, rng)
	var finds_cfg: Dictionary = cfg.get("finds", {})
	var rocks: Array = []
	for _i in int(finds_cfg.get("rocks", 5)):
		if not free.is_empty():
			rocks.append(free.pop_back())
	site["rock"] = rocks
	var finds := {}
	var gem_range: Array = finds_cfg.get("gem_amount", [1, 3])
	for kind in ["coins", "gems", "crystals"]:
		for _i in int(finds_cfg.get(kind, 0)):
			if free.is_empty():
				break
			var amount := 1
			if kind == "gems":
				amount = rng.randi_range(int(gem_range[0]), int(gem_range[1]))
			elif kind == "crystals":
				amount = int(finds_cfg.get("crystal_energy", 3))
			finds[str(free.pop_back())] = {"kind": kind, "amount": amount, "taken": false}
	site["finds"] = finds
	var shuffled := art_cells.duplicate()
	_shuffle(shuffled, rng)
	site["flags"] = shuffled.slice(0, mini(int(finds_cfg.get("survey_flags", 2)), shuffled.size()))
	return site

static func _shuffle(a: Array, rng: RandomNumberGenerator) -> void:
	for i in range(a.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var t: Variant = a[i]
		a[i] = a[j]
		a[j] = t

static func layers_at(site: Dictionary, i: int) -> int:
	return int((site["layers"] as Array)[i])

static func is_art(site: Dictionary, i: int) -> bool:
	return i in (site["art_cells"] as Array)

static func is_rock(site: Dictionary, i: int) -> bool:
	return i in (site["rock"] as Array)

## One layer of soil left above the artifact: the view shows it peeking through.
static func peeks(site: Dictionary, i: int) -> bool:
	return is_art(site, i) and layers_at(site, i) == 1

static func complete(site: Dictionary) -> bool:
	for i in site["art_cells"]:
		if layers_at(site, int(i)) > 0:
			return false
	return true

## Uncovered share of the artifact, 0..1 (for the progress readout).
static func progress(site: Dictionary) -> float:
	var cells: Array = site["art_cells"]
	if cells.is_empty():
		return 1.0
	var bare := 0
	for i in cells:
		if layers_at(site, int(i)) == 0:
			bare += 1
	return float(bare) / float(cells.size())

## 3 stars minus one per crack, never below 1.
static func quality(site: Dictionary) -> int:
	return clampi(3 - int(site.get("damage", 0)), 1, 3)

## Swing `tool` ("pick" / "brush") at cell (x, y). Pure: mutates only `site`.
## Returns {ok, reason, removed, cracked, find ({} or {kind, amount}), complete}.
static func dig(site: Dictionary, x: int, y: int, tool: String, cfg: Dictionary) -> Dictionary:
	var out := {"ok": false, "reason": "", "removed": 0, "cracked": false, "find": {}, "complete": false}
	if bool(site.get("done", false)):
		out["reason"] = "done"
		return out
	if not in_bounds(site, x, y):
		out["reason"] = "outside"
		return out
	var i := idx(site, x, y)
	var left := layers_at(site, i)
	if left <= 0:
		out["reason"] = "empty"
		return out
	var rock := is_rock(site, i)
	if rock and tool != "pick":
		out["reason"] = "rock"
		return out
	var depth := 1 if rock else int((cfg.get("tools", {}) as Dictionary).get(tool, {}).get("depth", 1 if tool == "brush" else 2))
	var removed := mini(depth, left)
	(site["layers"] as Array)[i] = left - removed
	out["ok"] = true
	out["removed"] = removed
	if left - removed == 0:
		if is_art(site, i) and tool == "pick":
			site["damage"] = int(site.get("damage", 0)) + 1
			out["cracked"] = true
		var finds: Dictionary = site["finds"]
		var key := str(i)
		if finds.has(key) and not bool(finds[key].get("taken", false)):
			finds[key]["taken"] = true
			out["find"] = {"kind": str(finds[key]["kind"]), "amount": int(finds[key]["amount"])}
	if complete(site):
		site["done"] = true
		out["complete"] = true
	return out
