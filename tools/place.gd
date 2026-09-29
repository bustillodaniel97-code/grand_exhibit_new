extends SceneTree
## Interactive asset placer — drag venue furniture on the running game and write
## the result straight back to data/venues.json.
##
##   godot --path . -s tools/place.gd -- venue=whispering_pines cash=1e40 levels=8
##
## WHY
##
## Placement notes were being made by drawing on a phone screenshot, and mapping
## an arrow back through the isometric projection by eye is genuinely ambiguous —
## three separate notes landed within 0.01 tiles of two or three different assets,
## and picking the wrong one costs a whole round trip. Dragging the actual thing
## removes the guess entirely.
##
## Dev tool. Lives outside tests/ so the suite glob skips it, and outside the
## shipping scenes entirely — nothing here is referenced by the game, and tools/
## is already excluded from the Android export.
##
## CONTROLS
##   F9            toggle edit mode (game input is untouched while it is off)
##   V             venue menu — pick any of the 12; click a row or press [ ]
##   left-drag     move the selected asset; click empty space to deselect
##   shift-drag    free placement (otherwise snaps to 1/20 tile)
##   arrows        nudge by 0.05 tiles, shift-arrows by 0.25
##   R             rotate 45 degrees on the ground plane (shift-R: 15)
##   M             mirror: none / diagonal / east-west / north-south
##   G             cycle grid: off / lines / lines + coordinates
##   Ctrl+S        write data/venues.json and hot-reload the floor
##   Ctrl+Z        undo the last move (single level)
##
## The venue argument is now only the STARTING venue. V switches to any of the
## twelve in place, carrying cash and staff levels across, so a whole audit pass
## runs in one session instead of twelve relaunches.

const MAIN := "res://scenes/main.tscn"
const Iso := preload("res://scenes/venue/floor/iso.gd")
const VENUES := "res://data/venues.json"
## Snap, in tiles. A twentieth reads as continuous at play scale but keeps the
## authored numbers short enough to review in a diff.
const SNAP := 0.05
## Tight ring for an exact hit. Deliberately small so two neighbouring assets
## stay distinguishable.
const PICK_RADIUS := 30.0
## Generous fallback. A marker sits at the piece's BASE, but tall art — a
## planter's leaves, a banner, a statue — draws well above that, so clicking what
## you can see lands nowhere near the handle. Reported as "I cannot move this
## plant" when the plant was perfectly movable and simply unclickable.
const PICK_RADIUS_FAR := 74.0

var _args := {}
var _floor: Node = null
var _ui: _Placer = null


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := (a as String).split("=", true, 1)
		if kv.size() == 2:
			_args[kv[0]] = kv[1]
	root.add_child((load(MAIN) as PackedScene).instantiate())
	call_deferred("_attach")


func _attach() -> void:
	var gs: Node = root.get_node_or_null("GameState")
	var ss: Node = root.get_node_or_null("SaveSystem")
	if ss != null:
		# Never let a placement session write the doctored state into a save.
		ss.set_process(false)
		ss.autosave_interval_sec = 1 << 30
	if gs != null:
		var BigNumber: GDScript = load("res://scripts/core/big_number.gd")
		if _args.has("cash"):
			gs.add_cash(BigNumber.from_float(float(_args["cash"])))
		if _args.has("venue"):
			var vid: String = String(_args["venue"])
			if vid not in gs.venues_unlocked:
				gs.venues_unlocked.append(vid)
			gs.current_venue = vid
		var lv := int(_args.get("levels", "0"))
		if lv > 0:
			for dept in ["ticket", "archive", "promotions", "gallery"]:
				for track in ["staff", "speed", "value"]:
					gs.set_dept_level(gs.current_venue, dept, track,
						gs.dept_level(gs.current_venue, dept, track) + lv)

	_floor = _find(root, "VenueFloor")
	if _floor == null:
		push_error("place.gd: no VenueFloor in the scene")
		quit(1)
		return
	if _args.has("venue") and _floor.has_method("retheme"):
		_floor.retheme(String(_args["venue"]))

	var layer := CanvasLayer.new()
	layer.layer = 40
	root.add_child(layer)
	_ui = _Placer.new()
	_ui.bind(_floor)
	layer.add_child(_ui)
	print("PLACER ready — F9 to edit, Ctrl+S to save")
	if OS.has_environment("GRAND_EXHIBIT_PLACER_SELFTEST"):
		call_deferred("_selftest")


## Drive a move and a rotate without a human, and print what the LIVE theme dict
## looked like before and after. "It edits the file" and "the floor redraws" are
## different claims, and only the second one is what makes the tool usable.
func _selftest() -> void:
	if _args.has("sweep"):
		_selftest_sweep()
		return
	if _args.has("stafftest"):
		_selftest_staff()
		return
	var i := -1
	for k in _ui.items.size():
		if str(_ui.items[k]["kind"]) == "bench":
			i = k
			break
	if i < 0:
		print("SELFTEST no bench in this venue")
		quit(0)
		return
	_ui.editing = true
	_ui.picked = i
	var live: Dictionary = _ui.items[i]["live"]
	print("SELFTEST before   at=%s axis=%s size=%s"
		% [str(live.get("at")), str(live.get("axis")), str(live.get("size"))])
	_ui._set_at(i, _ui._at_of(i) + Vector2(1.0, 0.0))
	_ui._apply_live(i)
	print("SELFTEST moved    at=%s" % str(live.get("at")))
	_ui._rotate(i)
	print("SELFTEST rotated  axis=%s  status=%s" % [str(live.get("axis")), _ui.status])
	print("SELFTEST file untouched (no Ctrl+S issued)")
	quit(0)


## Walk every venue through the picker and report what the tool sees in each.
##
## Switching venue is the one operation that can leave the tool indexing a
## building that is no longer on screen — a stale item list points at assets that
## were freed, and the first symptom is dragging one and watching nothing move.
## Counting items per venue proves the re-index actually happened.
## Drag a promotions clerk and read back the node's actual position.
##
## "The handle moved" and "the person moved" were different claims for a whole
## session. This asserts the second one.
func _selftest_staff() -> void:
	var i := -1
	for k in _ui.items.size():
		if str(_ui.items[k]["kind"]).begins_with("staff:promotions"):
			i = k
			break
	if i < 0:
		print("STAFFTEST no promotions post")
		quit(1)
		return
	_ui.editing = true
	_ui.picked = i
	var before: Vector2 = _floor._promo_nodes[0].position
	_ui._set_at(i, _ui._at_of(i) + Vector2(2.0, 0.0))
	_ui._apply_live(i)
	var after: Vector2 = _floor._promo_nodes[0].position
	print("STAFFTEST clerk screen pos %s -> %s   moved=%s"
		% [str(before), str(after), str(before != after)])
	quit(0 if before != after else 1)


func _selftest_sweep() -> void:
	for k in _ui.venues.size():
		_ui._switch_venue(k)
		var props := 0
		var stations := 0
		for it in _ui.items:
			if str(it["group"]) == "station":
				stations += 1
			else:
				props += 1
		print("SWEEP %2d  %-22s theme=%-22s items=%3d props=%3d staff=%d"
			% [k + 1, str(_ui.venues[k]["id"]), str(_floor._theme.id),
			_ui.items.size(), props, stations])
	quit(0)


func _find(n: Node, want: String) -> Node:
	if n.name == want:
		return n
	for c in n.get_children():
		var r: Node = _find(c, want)
		if r != null:
			return r
	return null


## The overlay itself: grid, markers, hit-testing, drag, and the file write.
class _Placer extends Control:
	const Iso2 := preload("res://scenes/venue/floor/iso.gd")
	## Kinds whose long axis can be swapped. Everything else is a point or a
	## square, and rotating it would be a no-op that looks like a broken key.
	## Kinds with a FRONT as well as a long axis, so they get all four facings.
	const FLIPPABLE := ["bench", "skeleton", "hung_skeleton", "hanging"]
	## Kinds whose ART is screen-space rather than a grid footprint. Swapping their
	## axis rotates the plinth underneath and leaves the piece itself pointing the
	## same way — a skeleton on a turned base, which reads as broken. They flip and
	## nothing else.
	const FLIP_ONLY := ["skeleton", "hung_skeleton", "hanging"]
	const ROTATABLE := ["bench", "shelf", "vault_door", "rack", "cabinet",
		"vitrine", "case", "desk", "counter", "picture", "notice", "poster",
		"mural", "banner", "skeleton", "hung_skeleton", "casket", "statue",
		"plinth", "tank", "touch_pool", "crate", "trolley", "kiosk", "machine",
		"info_desk", "shelf", "rug", "patch"]

	var floor_node: Node
	var editing := false
	var grid_mode := 2                 # 0 off, 1 lines, 2 lines + labels
	var items: Array = []              # [{ref, kind, group, at}]
	var picked: int = -1
	var dragging := false
	var undo: Dictionary = {}
	var doc: Dictionary = {}
	var venue_id := ""
	var spread := 1.0
	var status := ""
	## [{id, name, generated}] in file order, which is progression order.
	var venues: Array = []
	var venue_menu := false
	var menu_rects: Array = []

	func bind(f: Node) -> void:
		floor_node = f
		set_anchors_preset(Control.PRESET_FULL_RECT)
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		set_process_input(true)
		_reload_doc()

	## Read the venue file straight from disk. The placer owns the AUTHORED
	## numbers, not the runtime theme: the theme has already had layout_spread
	## multiplied in and rounded, and writing that back would drift every venue a
	## little further every time the tool was opened.
	func _reload_doc() -> void:
		venue_id = str(floor_node._theme.id)
		var text := FileAccess.get_file_as_string(VENUES)
		doc = JSON.parse_string(text) as Dictionary
		items.clear()
		picked = -1
		venues.clear()
		for v in doc.get("venues", []):
			var vd: Dictionary = v as Dictionary
			# Venues 4-12 are emitted by tools/author_venue.py. Hand edits to them
			# survive here and in the file, but the next generator run overwrites
			# them — worth saying on screen rather than discovering it after an
			# afternoon of placement work.
			venues.append({"id": str(vd.get("id", "")),
				"name": str(vd.get("name", vd.get("id", ""))),
				"generated": venues.size() >= 3})
		for v in doc.get("venues", []):
			if str((v as Dictionary).get("id", "")) != venue_id:
				continue
			var theme: Dictionary = (v as Dictionary).get("theme", {})
			spread = float(theme.get("layout_spread", 1.0))
			# Pair each authored entry with the LIVE theme dict the renderer
			# actually draws from, by index — resolve() and _spread_specs()
			# preserve order within a group. Without this the tool edits the file
			# and nothing on screen moves until a save, which reads as a broken
			# tool rather than a deferred one.
			# Staff posts. Each department's people stand on `stations`, authored
			# as offsets INSIDE the room rather than as absolute positions, so they
			# were invisible to a tool that only knew about props. Held with their
			# room's origin so the offset can be rebuilt when one is dragged.
			for room in theme.get("rooms", []):
				var rm: Dictionary = room as Dictionary
				var rect: Array = rm.get("rect", [])
				if rect.size() < 2:
					continue
				# The renderer reads its own copy of the room, rebuilt by
				# VenueTheme.for_venue() from DataLoader's cache. Editing only the
				# authored document moves nothing on screen, so hold both.
				var live_room: Dictionary = floor_node._theme.by_id.get(
					str(rm.get("id", "")), {})
				var si := 0
				for st in rm.get("stations", []):
					items.append({"ref": st, "group": "station",
						"kind": "staff:%s" % str(rm.get("dept", rm.get("id", "?"))),
						"origin": Vector2(float(rect[0]), float(rect[1])),
						"live_room": live_room, "slot": si})
					si += 1
			for group in ["props", "exhibits"]:
				var live_list: Array = floor_node._theme.props if group == "props" \
					else floor_node._theme.exhibits
				var n := 0
				for entry in theme.get(group, []):
					var e: Dictionary = entry as Dictionary
					if not e.has("at"):
						n += 1
						continue
					items.append({"ref": e, "group": group,
						"kind": str(e.get("kind", "?")),
						"live": live_list[n] if n < live_list.size() else null})
					n += 1
		queue_redraw()

	## Push an authored change into the live theme and redraw the floor.
	##
	## Only `at`, `anchor`, `from` and `to` carry layout_spread (see
	## VenueFloor._spread_specs) — `size` and `axis` are authored units and go
	## across untouched. Getting that backwards would shrink furniture a little
	## more on every edit in the venues that use spread.
	func _apply_live(i: int) -> void:
		if str(items[i]["group"]) == "station":
			# Write into the LIVE room, then re-key the cast so _refresh_cast()
			# re-places everyone from it. retheme() cannot be used here: it rebuilds
			# the theme from DataLoader's cached copy and discards the edit, which is
			# exactly why dragging a clerk moved the handle and not the clerk.
			var lr: Variant = items[i].get("live_room")
			if lr is Dictionary and (lr as Dictionary).has("stations"):
				var ls: Array = (lr as Dictionary)["stations"]
				var slot: int = int(items[i]["slot"])
				var src: Array = items[i]["ref"]
				if slot < ls.size():
					var dst: Array = ls[slot]
					dst[0] = src[0]
					dst[1] = src[1]
			# _refresh_cast() only CREATES and DESTROYS staff — an existing node is
			# never re-placed, because in the game a post never moves. So free this
			# department's cast and let the refresh rebuild it at the new post.
			var dept: String = str(items[i]["kind"]).trim_prefix("staff:")
			var arrays := {"promotions": "_promo_nodes", "gallery": "_docent_nodes"}
			if arrays.has(dept):
				var arr: Array = floor_node.get(str(arrays[dept]))
				for c in arr:
					(c as Node).queue_free()
				arr.clear()
			floor_node._cast_key = ""
			floor_node._refresh_cast()
			return
		var live: Variant = items[i].get("live")
		if not (live is Dictionary):
			return
		var e: Dictionary = items[i]["ref"]
		var d: Dictionary = live
		for key in ["at", "anchor"]:
			if e.has(key):
				var v: Array = e[key]
				d[key] = [float(v[0]) * spread, float(v[1]) * spread]
		for key in ["size", "axis", "height", "flip", "rot", "mirror"]:
			if e.has(key):
				d[key] = e[key]
			else:
				d.erase(key)
		floor_node._props_key = ""
		floor_node._rebuild_props()

	func _venue_index() -> int:
		for i in venues.size():
			if str(venues[i]["id"]) == venue_id:
				return i
		return 0

	## Move the whole session to another building.
	##
	## Goes through retheme(), the same call the game uses, so the cast, the
	## surround, the storey nodes and the queues are rebuilt rather than left
	## pointing at the previous floor plan. GameState follows so the economy and the
	## department sheets describe the venue on screen; cash and every purchased level
	## are left exactly as they are.
	func _switch_venue(idx: int) -> void:
		if venues.is_empty():
			return
		idx = posmod(idx, venues.size())
		var vid: String = str(venues[idx]["id"])
		if vid == venue_id:
			venue_menu = false
			queue_redraw()
			return
		var gs: Node = floor_node.get_tree().root.get_node_or_null("GameState")
		if gs != null:
			if vid not in gs.venues_unlocked:
				gs.venues_unlocked.append(vid)
			gs.current_venue = vid
		floor_node.retheme(vid)
		_reload_doc()            # re-index: the old venue's assets are gone
		undo = {}                # an undo from another building is nonsense
		venue_menu = false
		status = "venue %d/%d — %s%s" % [idx + 1, venues.size(), vid,
			"  (generated: author_venue.py will overwrite hand edits)"
			if bool(venues[idx]["generated"]) else ""]
		queue_redraw()

	# ---------------------------------------------------------------- geometry

	func _to_screen(g: Vector2) -> Vector2:
		var canvas: Node2D = floor_node._canvas
		return canvas.get_global_transform() * Iso2.to_screen(g * spread)

	func _to_grid(p: Vector2) -> Vector2:
		var canvas: Node2D = floor_node._canvas
		var local: Vector2 = canvas.get_global_transform().affine_inverse() * p
		return Iso2.to_grid(local) / spread

	func _at_of(i: int) -> Vector2:
		if str(items[i]["group"]) == "station":
			var st: Array = items[i]["ref"]
			return items[i]["origin"] + Vector2(float(st[0]), float(st[1]))
		var a: Array = (items[i]["ref"] as Dictionary)["at"]
		return Vector2(float(a[0]), float(a[1]))

	func _set_at(i: int, g: Vector2) -> void:
		if str(items[i]["group"]) == "station":
			var st: Array = items[i]["ref"]
			var off: Vector2 = g - items[i]["origin"]
			st[0] = snappedf(off.x, 0.01)
			st[1] = snappedf(off.y, 0.01)
			return
		var e: Dictionary = items[i]["ref"]
		e["at"] = [snappedf(g.x, 0.01), snappedf(g.y, 0.01)]
		# Anchors are what the browse FSM and the geometry suite read, so they
		# have to travel with the piece rather than be left behind.
		if e.has("barrier"):
			var b: Dictionary = e["barrier"]
			var w: float = float((e.get("size", [1.0, 1.0]) as Array)[0])
			var h: float = float((e.get("size", [1.0, 1.0]) as Array)[1])
			b["from"] = [snappedf(g.x - 0.2, 0.01), snappedf(g.y + h + 0.5, 0.01)]
			b["to"] = [snappedf(g.x + w + 0.2, 0.01), snappedf(g.y + h + 0.5, 0.01)]
		if e.has("anchor") and e.has("size"):
			var s: Array = e["size"]
			e["anchor"] = [snappedf(g.x + float(s[0]) * 0.5, 0.01),
				snappedf(g.y + float(s[1]) * 0.5, 0.01)]
		elif e.has("anchor"):
			e["anchor"] = [snappedf(g.x, 0.01), snappedf(g.y, 0.01)]

	# ------------------------------------------------------------------- input

	func _input(event: InputEvent) -> void:
		if event is InputEventKey and event.pressed and not event.echo:
			match (event as InputEventKey).keycode:
				KEY_F9:
					editing = not editing
					mouse_filter = Control.MOUSE_FILTER_STOP if editing \
						else Control.MOUSE_FILTER_IGNORE
					status = "edit ON" if editing else "edit off"
					queue_redraw()
					get_viewport().set_input_as_handled()
					return
				KEY_M:
					if editing:
						if picked < 0:
							status = "select an asset first"
							queue_redraw()
						else:
							_mirror(picked)
						return
				KEY_V:
					if editing:
						venue_menu = not venue_menu
						queue_redraw()
						get_viewport().set_input_as_handled()
						return
				KEY_BRACKETLEFT:
					if editing:
						_switch_venue(_venue_index() - 1)
						get_viewport().set_input_as_handled()
						return
				KEY_BRACKETRIGHT:
					if editing:
						_switch_venue(_venue_index() + 1)
						get_viewport().set_input_as_handled()
						return
				KEY_ESCAPE:
					if editing and venue_menu:
						venue_menu = false
						queue_redraw()
						get_viewport().set_input_as_handled()
						return
				KEY_G:
					if editing:
						grid_mode = (grid_mode + 1) % 3
						queue_redraw()
						return
				KEY_R:
					if editing:
						if picked < 0:
							status = "select an asset first"
							queue_redraw()
						else:
							undo = {"i": picked, "at": _at_of(picked)}
							_spin(picked, 15.0 if (event as InputEventKey).shift_pressed
								else 45.0)
						return
				KEY_S:
					if editing and event.ctrl_pressed:
						_save()
						return
				KEY_Z:
					if editing and event.ctrl_pressed and not undo.is_empty():
						_set_at(int(undo["i"]), undo["at"])
						undo = {}
						status = "undone"
						queue_redraw()
						return
			if editing and picked >= 0:
				var step: float = 0.25 if (event as InputEventKey).shift_pressed else SNAP
				var d := Vector2.ZERO
				match (event as InputEventKey).keycode:
					KEY_LEFT: d = Vector2(-step, 0.0)
					KEY_RIGHT: d = Vector2(step, 0.0)
					KEY_UP: d = Vector2(0.0, -step)
					KEY_DOWN: d = Vector2(0.0, step)
				if d != Vector2.ZERO:
					undo = {"i": picked, "at": _at_of(picked)}
					_set_at(picked, _at_of(picked) + d)
					_apply_live(picked)
					queue_redraw()
					get_viewport().set_input_as_handled()
		if not editing:
			return
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
			if venue_menu:
				# The menu is on top, so it claims the click. Without this a row press
				# would also drop whatever asset happens to sit under it.
				if event.pressed:
					for r in menu_rects:
						if (r["rect"] as Rect2).has_point(event.position):
							_switch_venue(int(r["idx"]))
							break
				accept_event()
				return
			if event.pressed:
				picked = _pick(event.position)
				dragging = picked >= 0
				if dragging:
					undo = {"i": picked, "at": _at_of(picked)}
				queue_redraw()
			else:
				if dragging and picked >= 0:
					_apply_live(picked)     # on release, not every frame
				dragging = false
			accept_event()
		elif event is InputEventMouseMotion and venue_menu:
			accept_event()
		elif event is InputEventMouseMotion and dragging and picked >= 0:
			var g: Vector2 = _to_grid(event.position)
			if not (event as InputEventMouseMotion).shift_pressed:
				g = Vector2(snappedf(g.x, SNAP), snappedf(g.y, SNAP))
			_set_at(picked, g)
			queue_redraw()
			accept_event()

	## Is this grid point inside the band the camera actually shows at that depth?
	## Mirrors Iso.gx_window with the same 26px margin tests/venue/test_geometry.gd
	## holds the line at, so the tool agrees with the suite instead of disagreeing
	## with it after the fact.
	func _on_camera(g: Vector2) -> bool:
		var w: Vector2 = Iso2.gx_window(g.y * spread, 26.0)
		var gx: float = g.x * spread
		return gx >= w.x and gx <= w.y

	func _pick(p: Vector2) -> int:
		# Two passes: an exact hit wins outright, so tightly packed assets stay
		# individually selectable. Only if nothing is close do we reach for the
		# nearest thing within the generous ring.
		var near := -1
		var near_d := PICK_RADIUS
		var far := -1
		var far_d := PICK_RADIUS_FAR
		for i in items.size():
			var d: float = _to_screen(_at_of(i)).distance_to(p)
			if d < near_d:
				near_d = d
				near = i
			if d < far_d:
				far_d = d
				far = i
		return near if near >= 0 else far

	## Cycle a piece through the four facings the projection actually has.
	##
	## `axis` alone only gives two — which way the piece RUNS. A piece with a
	## front (a bench has a back and a seat) also needs which way it LOOKS, so R
	## walks x, x-flipped, y, y-flipped and back. Kinds that have no front ignore
	## the flip and simply alternate axis, which is still the whole of their
	## orientation.
	## Turn a piece on the ground plane.
	##
	## Real rotation now, not a choice between two footprints: Iso applies it
	## inside the projection, so every kind turns. `step` is 45 degrees by default
	## and 15 with shift, which is fine enough to line a piece up against a wall
	## that is not on the grid.
	##
	## The screen-space kinds are the exception. A skeleton's bones are offsets
	## hung off its spine in SCREEN space, so rotating the piece turns its plinth
	## and drags the animal round with it without the animal itself turning. Those
	## keep the flip, which mirrors the offsets properly.
	func _spin(i: int, step: float) -> void:
		var e: Dictionary = items[i]["ref"]
		var kind: String = str(e.get("kind", ""))
		if kind in FLIP_ONLY:
			e["flip"] = not bool(e.get("flip", false))
			_apply_live(i)
			status = "%s -> %s" % [kind,
				"facing back" if bool(e.get("flip", false)) else "facing front"]
			queue_redraw()
			return
		var deg: float = fmod(float(e.get("rot", 0.0)) + step + 360.0, 360.0)
		if is_zero_approx(deg):
			e.erase("rot")
		else:
			e["rot"] = snappedf(deg, 0.1)
		_apply_live(i)
		status = "%s -> %d deg" % [kind, int(deg)]
		queue_redraw()

	## Reflect a piece on the ground plane.
	##
	## The operation rotation cannot do. Cycles the axis the reflection happens
	## across: none, diagonal (reads as a left-right mirror on screen), east-west,
	## north-south. Mirroring is what matches an L of furniture on the opposite
	## side of a room — no angle produces a reflection of an asymmetric shape.
	const MIRRORS := ["", "d", "y", "x"]

	func _mirror(i: int) -> void:
		var e: Dictionary = items[i]["ref"]
		var cur: String = str(e.get("mirror", ""))
		var nxt: String = MIRRORS[(MIRRORS.find(cur) + 1) % MIRRORS.size()]
		if nxt == "":
			e.erase("mirror")
		else:
			e["mirror"] = nxt
		_apply_live(i)
		status = "%s -> mirror %s" % [str(e.get("kind", "?")),
			nxt if nxt != "" else "none"]
		queue_redraw()

	func _rotate(i: int) -> void:
		var e: Dictionary = items[i]["ref"]
		var kind: String = str(e.get("kind", ""))
		if kind not in ROTATABLE:
			status = "%s has no long axis to rotate" % kind
			queue_redraw()
			return
		var was_x: bool = str(e.get("axis", "x")) == "x"
		var was_flipped: bool = bool(e.get("flip", false))
		var can_flip: bool = kind in FLIPPABLE
		if kind in FLIP_ONLY:
			e["flip"] = not was_flipped            # the only turn it has
			_apply_live(i)
			status = "%s -> %s" % [kind,
				"facing back" if bool(e.get("flip", false)) else "facing front"]
			queue_redraw()
			return
		if can_flip and not was_flipped:
			e["flip"] = true                       # same run, other way round
		else:
			e["axis"] = "y" if was_x else "x"      # quarter turn
			e.erase("flip")
			if e.has("size"):
				var sz: Array = e["size"]
				e["size"] = [sz[1], sz[0]]
				_set_at(i, _at_of(i))              # re-centre on the new footprint
		_apply_live(i)
		status = "%s -> %s%s" % [kind, str(e.get("axis", "x")),
			" flipped" if bool(e.get("flip", false)) else ""]
		queue_redraw()

	func _save() -> void:
		# Back the file up BEFORE touching it. A save rewrites the whole document,
		# so a stray Ctrl+S is not a small edit — it replaces every venue's
		# formatting and any hand edits made since the tool was opened. That
		# happened once, from keys pressed by someone who was not driving, and the
		# only reason it was recoverable is that a copy existed outside the repo.
		var stamp := Time.get_datetime_string_from_system().replace(":", "")
		var backup := "res://data/venues.backup-%s.json" % stamp
		var prev := FileAccess.get_file_as_string(VENUES)
		if prev != "":
			var bf := FileAccess.open(backup, FileAccess.WRITE)
			if bf != null:
				bf.store_string(prev)
				bf.close()
		var f := FileAccess.open(VENUES, FileAccess.WRITE)
		if f == null:
			status = "SAVE FAILED: %s not writable" % VENUES
			queue_redraw()
			return
		f.store_string(JSON.stringify(doc, " "))
		f.close()
		# Re-read from disk and rebuild the floor, so what is on screen is what
		# was actually written rather than what the tool believes it wrote.
		var dl: Node = floor_node.get_tree().root.get_node_or_null("DataLoader")
		if dl != null and dl.has_method("reload_all"):
			dl.reload_all()
		var vid := venue_id
		floor_node._theme.id = "__reload__"
		floor_node.retheme(vid)
		_reload_doc()
		status = "saved — previous copy kept as %s" % backup.get_file()
		queue_redraw()

	# -------------------------------------------------------------------- draw

	func _draw() -> void:
		if not editing:
			draw_string(ThemeDB.fallback_font, Vector2(12.0, 22.0),
				"F9 — asset placer", HORIZONTAL_ALIGNMENT_LEFT, -1, 13,
				Color(1, 1, 1, 0.45))
			return
		if grid_mode > 0:
			_draw_grid()
		var off_canvas := 0
		for i in items.size():
			var p: Vector2 = _to_screen(_at_of(i))
			var on: bool = i == picked
			# Red means the piece has left the visible window. The projection
			# shears x by -gy, so the on-camera band slides one tile right for
			# every tile of depth — an asset can look perfectly central in the
			# plan and still be off the edge of the phone. Without this the tool
			# lets you place something invisible and the first sign is a failing
			# geometry test long afterwards.
			var visible: bool = _on_camera(_at_of(i))
			if not visible:
				off_canvas += 1
			var col: Color = Color(1.0, 0.85, 0.2, 0.95) if on \
				else Color(0.3, 0.9, 1.0, 0.7)
			if not visible:
				col = Color(1.0, 0.32, 0.32, 0.95)
			draw_circle(p, 7.0 if on else 4.0, col)
			if on:
				var g: Vector2 = _at_of(i)
				draw_string(ThemeDB.fallback_font, p + Vector2(10.0, -8.0),
					"%s  %.2f, %.2f" % [items[i]["kind"], g.x, g.y],
					HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(1, 1, 0.6))
		if venue_menu:
			_draw_venue_menu()
		var help := "F9 edit · V venue · drag · shift=free · arrows nudge · R rotate · M mirror · G grid · Ctrl+S save · Ctrl+Z undo"
		draw_string(ThemeDB.fallback_font, Vector2(12.0, size.y - 30.0), help,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(1, 1, 1, 0.7))
		if off_canvas > 0:
			draw_string(ThemeDB.fallback_font, Vector2(12.0, 44.0),
				"%d asset%s OFF CAMERA (red) — they will not be drawn in game"
				% [off_canvas, "" if off_canvas == 1 else "s"],
				HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(1.0, 0.45, 0.45))
		if status != "":
			draw_string(ThemeDB.fallback_font, Vector2(12.0, size.y - 12.0),
				status, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.6, 1.0, 0.7))

	func _draw_venue_menu() -> void:
		menu_rects.clear()
		var row := 30.0
		var w := 340.0
		var h: float = row * float(venues.size()) + 52.0
		var org := Vector2(size.x * 0.5 - w * 0.5, size.y * 0.5 - h * 0.5)
		draw_rect(Rect2(org, Vector2(w, h)), Color(0.05, 0.06, 0.12, 0.94))
		draw_rect(Rect2(org, Vector2(w, h)), Color(1, 1, 1, 0.22), false, 2.0)
		draw_string(ThemeDB.fallback_font, org + Vector2(14.0, 26.0),
			"VENUE  —  click, or [ ] to step, Esc to close",
			HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(1, 1, 1, 0.75))
		var here: int = _venue_index()
		for i in venues.size():
			var r := Rect2(org + Vector2(6.0, 38.0 + row * float(i)),
				Vector2(w - 12.0, row - 2.0))
			menu_rects.append({"rect": r, "idx": i})
			if i == here:
				draw_rect(r, Color(1.0, 0.85, 0.2, 0.16))
			# Amber marks a generated venue, where a placement survives until the next
			# author_venue.py run and no longer.
			var col: Color = Color(1, 1, 1, 0.95) if i == here \
				else (Color(1.0, 0.80, 0.45, 0.78) if bool(venues[i]["generated"])
					else Color(0.62, 0.92, 1.0, 0.80))
			draw_string(ThemeDB.fallback_font, r.position + Vector2(10.0, 20.0),
				"%2d  %s%s" % [i + 1, str(venues[i]["name"]),
					"  *" if bool(venues[i]["generated"]) else ""],
				HORIZONTAL_ALIGNMENT_LEFT, -1, 14, col)
		draw_string(ThemeDB.fallback_font, org + Vector2(14.0, h - 12.0),
			"*  generated — author_venue.py rewrites these",
			HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(1.0, 0.80, 0.45, 0.7))

	func _draw_grid() -> void:
		var b: Rect2 = floor_node._theme.bounds
		var x0 := int(floor(b.position.x / spread)) - 1
		var y0 := int(floor(b.position.y / spread)) - 1
		var x1 := int(ceil(b.end.x / spread)) + 1
		var y1 := int(ceil(b.end.y / spread)) + 1
		for gx in range(x0, x1 + 1):
			var wide: bool = gx % 5 == 0
			draw_line(_to_screen(Vector2(gx, y0)), _to_screen(Vector2(gx, y1)),
				Color(1, 1, 1, 0.36 if wide else 0.14), 2.0 if wide else 1.0)
		for gy in range(y0, y1 + 1):
			var wide2: bool = gy % 5 == 0
			draw_line(_to_screen(Vector2(x0, gy)), _to_screen(Vector2(x1, gy)),
				Color(1, 1, 1, 0.36 if wide2 else 0.14), 2.0 if wide2 else 1.0)
		if grid_mode < 2:
			return
		for gx in range(x0, x1 + 1, 2):
			for gy in range(y0, y1 + 1, 2):
				var p: Vector2 = _to_screen(Vector2(gx, gy))
				if p.x < -20.0 or p.y < -20.0 or p.x > size.x or p.y > size.y:
					continue
				draw_string(ThemeDB.fallback_font, p + Vector2(-9.0, 4.0),
					"%d,%d" % [gx, gy], HORIZONTAL_ALIGNMENT_LEFT, -1, 11,
					Color(1.0, 0.92, 0.45, 0.9))
