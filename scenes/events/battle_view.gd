extends Control
## Shared match-3 battle view (SPEC §6): 8x8 board, boss citation meter,
## moves counter, per-manager charge pips. Used by Inspection Frenzy stages
## and the Expedition boss. Config via setup_battle(), result via signal.
##
## The view OWNS an opaque page. It is parented over a live screen, and without a
## background the host's team picker and stage rows rendered straight through the
## board — the single thing that read as "the game is broken".
##
## The MODEL settles instantly and the BOARD animates afterwards. play_move()
## applies the swap, the damage, the move counter and the terminal check in one
## synchronous call (so a headless test can play a whole battle in a loop), then
## starts a cosmetic tween timeline that pops, drops and refills the tiles. Input
## is blocked for the length of that timeline.

signal battle_finished(result: String)  # "win" | "lose"

const Match3 = preload("res://scripts/events/match3_engine.gd")
const BattleMath = preload("res://scripts/events/battle_math.gd")

const UI := preload("res://scripts/ui/ui_kit.gd")
## Tile colours ARE the department colours — a player has to read a board tile as
## "that's my archive specialist" instantly, so they must not drift from the
## floor's palette.
##
## Neutral was UI.PANEL_SOFT (#F3ECFF) on a #F7F2FF page: a 1.03:1 tile carrying a
## white glyph, i.e. a fifth of the board rendered as holes. It is now a deep
## plum-grey at 3.46:1 against the page and 1.8:1 against the nearest department
## hue, so it reads as a piece rather than as a gap.
const NEUTRAL_TILE := Color("#3F3A5C")
const TILE_COLORS := [
	UI.DEPT_COLORS["promotions"],
	UI.DEPT_COLORS["ticket"],
	UI.DEPT_COLORS["archive"],
	UI.DEPT_COLORS["gallery"],
	NEUTRAL_TILE,
]
const GLYPHS := ["P", "T", "A", "G", "-"]
const DEPT_NAMES := ["Promotions", "Ticketing", "Archive", "Gallery", "Filing"]
## Shape is a second, colour-blind-safe channel: each department reads as a
## different silhouette (disc, card, squircle, framed card) before its hue does.
const TILE_RADIUS := [40, 10, 26, 10, 6]
## Neutral tiles are inset so they visibly sit BELOW the department tiles — the
## piece that charges nobody should also look like filler.
const TILE_INSET := [4, 4, 4, 4, 18]
const SPEC_TO_TILE := {"promotions": 0, "ticket": 1, "archive": 2, "gallery": 3}
const INK := UI.INK
const ACCENT := UI.ACCENT
## Every department hue is LIGHT (gold sits at 1.21:1 against the page), so a tile
## cannot separate from the page by its fill. It separates by a thick dark rim
## plus an extruded bottom lip — the same trick the kit's candy buttons use.
const TILE_RIM_DARKEN := 0.55
## UI.INK is tuned for body text on cream and only reaches 2.62:1 on the violet
## tile. Glyphs sit on saturated fills, so they get the deeper shell ink.
const GLYPH_DARK := UI.BG_DEEP

## 80 design px = 48dp on a 1080p phone, the Android minimum touch target; the
## board was 72 (43dp). 8*80 + 7*4 = 668, inside the 680px popup content width.
const TILE := 80
const GAP := 4
const BOARD_SPAN := TILE + GAP
const DRAG_THRESHOLD := 24.0

const SWAP_TIME := 0.11
const POP_TIME := 0.14
const DROP_TIME := 0.17

var _engine  # Match3 instance (untyped: duck-typed calls)
var _team: Array = []        # [{"def":Dictionary, "state":Dictionary}]
var _boss_hp := 1.0
var _boss_hp_max := 1.0
var _moves := 0
var _over := false
var _busy := false
var _selected := Vector2i(-1, -1)
var _cells: Array = []       # [y][x] -> Control (touch target)
var _visuals: Array = []     # [y][x] -> Panel (the drawn tile, tweened)
var _display: Array = []     # [y][x] -> int, the tile type currently drawn
var _meter: ProgressBar
var _hp_label: Label
var _moves_label: Label
var _focus_chip: PanelContainer
var _focus_label: Label
var _pips: Array = []        # ProgressBar per manager slot
var _pip_names: Array = []   # Label per manager slot
var _painted_focus := -2     # focus the board was last painted for
var _float_layer: Control
var _board: Control
var _press_cell := Vector2i(-1, -1)
var _press_point := Vector2.ZERO
var _dragged := false
var _move_tween: Tween
var _cell_tweens: Array = []   # per-tile pop/drop tweens, killed on the next move


func setup_battle(cfg: Dictionary) -> void:
	# queue_free is deferred: a second setup_battle on the same instance used to
	# leave the previous board alive for a frame (2 children became 4). A retry
	# button reuses the view, so the teardown has to be synchronous.
	for c in get_children():
		remove_child(c)
		c.free()
	_cells.clear()
	_visuals.clear()
	_display.clear()
	_pips.clear()
	_pip_names.clear()
	_team = cfg.get("team", [])
	_boss_hp = maxf(float(cfg.get("boss_hp", 100.0)), 1.0)
	_boss_hp_max = _boss_hp
	_moves = int(cfg.get("moves", 20))
	var seed: int = int(cfg.get("seed", -1))
	if seed < 0:
		seed = int(randi())
	_engine = Match3.new(seed)
	var types: Array = []
	for m in _team:
		types.append(int(SPEC_TO_TILE.get(str(m.get("def", {}).get("specialty", "")), -1)))
	_engine.set_team(types)
	if _engine.is_deadlocked():
		_engine.reshuffle()
	_over = false
	_busy = false
	_selected = Vector2i(-1, -1)
	_press_cell = Vector2i(-1, -1)
	_painted_focus = -2
	_build_ui(str(cfg.get("boss_name", "Inspector")))
	_snap_board(_engine.grid())
	_refresh_status()


## Live model, for tests and for a host screen that wants to show progress.
func battle_state() -> Dictionary:
	return {"hp": _boss_hp, "hp_max": _boss_hp_max, "moves": _moves,
		"over": _over, "focus": _engine.focus_type() if _engine != null else -1}


func _build_ui(boss_name: String) -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var page := Panel.new()
	page.set_anchors_preset(Control.PRESET_FULL_RECT)
	page.add_theme_stylebox_override("panel", _flat(UI.SURFACE, 0))
	page.mouse_filter = Control.MOUSE_FILTER_STOP  # swallow taps meant for the host
	add_child(page)

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 6)
	margin.add_theme_constant_override("margin_right", 6)
	margin.add_theme_constant_override("margin_top", 8)
	margin.add_theme_constant_override("margin_bottom", 8)
	add_child(margin)
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 8)
	root.alignment = BoxContainer.ALIGNMENT_CENTER
	margin.add_child(root)

	var title := UI.make_display_label(boss_name, UI.TYPE_TITLE, INK)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	root.add_child(title)

	# Citation meter. The track is a real dark channel: on the light page the old
	# PANEL-coloured track made an empty meter invisible, so only the number moved.
	var meter_row := HBoxContainer.new()
	meter_row.alignment = BoxContainer.ALIGNMENT_CENTER
	meter_row.add_theme_constant_override("separation", 10)
	root.add_child(meter_row)
	_meter = ProgressBar.new()
	_meter.custom_minimum_size = Vector2(430, 30)
	_meter.max_value = 100.0
	_meter.show_percentage = false
	_meter.add_theme_stylebox_override("background", UI.make_bar_bg())
	_meter.add_theme_stylebox_override("fill", UI.make_bar_fill("red"))
	meter_row.add_child(_meter)
	_hp_label = UI.make_display_label("", UI.TYPE_HEADING, INK)
	meter_row.add_child(_hp_label)

	# Audit chip: the one thing the player must read every move.
	_focus_chip = PanelContainer.new()
	_focus_chip.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_focus_label = UI.make_display_label("", UI.TYPE_HEADING, Color.WHITE)
	UI.add_text_halo(_focus_label)
	_focus_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_focus_chip.add_child(_focus_label)
	root.add_child(_focus_chip)

	# Moves + manager charge pips.
	var mid_row := HBoxContainer.new()
	mid_row.alignment = BoxContainer.ALIGNMENT_CENTER
	mid_row.add_theme_constant_override("separation", 14)
	root.add_child(mid_row)
	_moves_label = UI.make_display_label("", UI.TYPE_TITLE, INK)
	_moves_label.custom_minimum_size = Vector2(120, 0)
	mid_row.add_child(_moves_label)
	for i in _team.size():
		var def: Dictionary = _team[i].get("def", {})
		var box := VBoxContainer.new()
		box.add_theme_constant_override("separation", 2)
		var name_l := UI.make_label(str(def.get("name", "Manager")).split(" ")[0], UI.TYPE_CAPTION)
		name_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		box.add_child(name_l)
		var pip := ProgressBar.new()
		pip.custom_minimum_size = Vector2(136, 18)
		pip.max_value = 100.0
		pip.show_percentage = false
		var col: Color = TILE_COLORS[int(SPEC_TO_TILE.get(str(def.get("specialty", "")), 4))]
		pip.add_theme_stylebox_override("background", UI.make_bar_bg())
		pip.add_theme_stylebox_override("fill", _flat(col, 9))
		box.add_child(pip)
		mid_row.add_child(box)
		_pips.append(pip)
		_pip_names.append(name_l)

	# Board: absolutely positioned cells so swaps, pops and drops can be tweened.
	# A GridContainer owns its children's positions and would fight every tween.
	var center := CenterContainer.new()
	center.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(center)
	_board = Control.new()
	var span: float = float(8 * TILE + 7 * GAP)
	_board.custom_minimum_size = Vector2(span, span)
	center.add_child(_board)
	for y in 8:
		var cell_row: Array = []
		var vis_row: Array = []
		var disp_row: Array = []
		for x in 8:
			var cell := Control.new()
			cell.position = Vector2(x * BOARD_SPAN, y * BOARD_SPAN)
			cell.size = Vector2(TILE, TILE)
			cell.mouse_filter = Control.MOUSE_FILTER_STOP
			_board.add_child(cell)
			var vis := Panel.new()
			vis.set_anchors_preset(Control.PRESET_FULL_RECT)
			vis.pivot_offset = Vector2(TILE, TILE) * 0.5
			vis.mouse_filter = Control.MOUSE_FILTER_IGNORE
			cell.add_child(vis)
			var glyph := UI.make_display_label("", UI.TYPE_TITLE, Color.WHITE)
			glyph.set_anchors_preset(Control.PRESET_FULL_RECT)
			glyph.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			glyph.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			glyph.mouse_filter = Control.MOUSE_FILTER_IGNORE
			vis.add_child(glyph)
			cell.gui_input.connect(_on_cell_input.bind(Vector2i(x, y)))
			cell_row.append(cell)
			vis_row.append(vis)
			disp_row.append(-1)
		_cells.append(cell_row)
		_visuals.append(vis_row)
		_display.append(disp_row)

	_float_layer = Control.new()
	_float_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	_float_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_float_layer)


## Outline colour for a tile. Exposed because it, not the fill, is what makes the
## tile visible against the page — the readability test asserts on this.
static func tile_rim(t: int) -> Color:
	return (TILE_COLORS[t] as Color).darkened(TILE_RIM_DARKEN)


## Highest-contrast glyph ink for a tile, dark or light.
static func glyph_ink(t: int) -> Color:
	var tile: Color = TILE_COLORS[t]
	var lt: float = tile.get_luminance() + 0.05
	var dark: float = maxf(lt, GLYPH_DARK.get_luminance() + 0.05) \
		/ minf(lt, GLYPH_DARK.get_luminance() + 0.05)
	var light: float = 1.05 / lt
	return GLYPH_DARK if dark >= light else Color.WHITE


func _flat(color: Color, radius: int, border := Color.TRANSPARENT) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = color
	sb.set_corner_radius_all(radius)
	if border != Color.TRANSPARENT:
		sb.set_border_width_all(4)
		sb.border_color = border
	return sb


# ------------------------------------------------------------------ input

func _on_cell_input(event: InputEvent, pos: Vector2i) -> void:
	# _busy is an INPUT gate only. play_move() itself always settles the model, so
	# a headless test can play a whole battle without pumping animation frames.
	if _over or _busy:
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_begin_press(pos, _cells[pos.y][pos.x].global_position + event.position)
		else:
			_end_press(pos)
	elif event is InputEventScreenTouch:
		if event.pressed:
			_begin_press(pos, _cells[pos.y][pos.x].global_position + event.position)
		else:
			_end_press(pos)
	elif event is InputEventMouseMotion or event is InputEventScreenDrag:
		_update_drag(_cells[pos.y][pos.x].global_position + event.position)


func _begin_press(pos: Vector2i, point: Vector2) -> void:
	_press_cell = pos
	_press_point = point
	_dragged = false


func _end_press(pos: Vector2i) -> void:
	var origin := _press_cell
	_press_cell = Vector2i(-1, -1)
	if _dragged or origin.x < 0 or origin != pos:
		return
	_on_cell_tapped(pos)


## Swipe-to-swap, the genre-standard gesture. Tap-then-tap still works; this just
## means a thumb flick does the obvious thing instead of nothing.
func _update_drag(point: Vector2) -> void:
	if _press_cell.x < 0 or _dragged:
		return
	var delta: Vector2 = point - _press_point
	if delta.length() < DRAG_THRESHOLD:
		return
	var dir := Vector2i(int(signf(delta.x)), 0) if absf(delta.x) > absf(delta.y) \
		else Vector2i(0, int(signf(delta.y)))
	var target: Vector2i = _press_cell + dir
	_dragged = true
	var from := _press_cell
	_press_cell = Vector2i(-1, -1)
	if target.x < 0 or target.x > 7 or target.y < 0 or target.y > 7:
		return
	_set_selected(Vector2i(-1, -1))
	play_move(from, target)


func _on_cell_tapped(pos: Vector2i) -> void:
	UI.play_sfx(self, "tap")
	if _selected == Vector2i(-1, -1) or pos == _selected:
		_set_selected(Vector2i(-1, -1) if pos == _selected else pos)
		return
	if not _engine.can_swap(_selected, pos):
		_set_selected(pos)  # retarget selection to the new tile
		return
	var from := _selected
	_set_selected(Vector2i(-1, -1))
	play_move(from, pos)


func _set_selected(pos: Vector2i) -> void:
	var prev := _selected
	_selected = pos
	if prev.x >= 0:
		_paint_cell(prev.x, prev.y)
	if pos.x >= 0:
		_paint_cell(pos.x, pos.y)
		var vis: Panel = _visuals[pos.y][pos.x]
		var tw := create_tween()
		tw.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tw.tween_property(vis, "scale", Vector2(1.12, 1.12), 0.09)


# ------------------------------------------------------------------ model

## Plays one move. The whole model (board, charges, damage, moves, terminal
## state) settles synchronously; the board animation that follows is cosmetic.
## Returns true when the swap was legal and consumed a move.
func play_move(from: Vector2i, to: Vector2i) -> bool:
	if _over or _engine == null:
		return false
	if not _engine.can_swap(from, to):
		return false
	var result: Dictionary = _engine.try_swap(from, to)
	if not result["swapped"]:
		UI.play_sfx(self, "tap")
		_shake_cell(from)
		_shake_cell(to)
		return false
	UI.play_sfx(self, "click")
	_moves -= 1
	_apply_result(result)
	var reshuffled := false
	if _boss_hp > 0.0 and _moves > 0 and _engine.is_deadlocked():
		_engine.reshuffle()
		reshuffled = true
	_animate_move(from, to, result, reshuffled)
	if _boss_hp <= 0.0:
		_finish("win")
	elif _moves <= 0:
		_finish("lose")
	return true


## Applies every attack in the resolve and returns the total damage dealt.
func _apply_result(result: Dictionary) -> float:
	var total := 0.0
	for atk in result.get("attacks", []):
		var idx: int = int(atk.get("manager_index", -1))
		if idx < 0 or idx >= _team.size():
			continue
		total += BattleMath.manager_attack(
			_team[idx].get("def", {}), _team[idx].get("state", {})) \
			* float(atk.get("charge_mult", 1.0))
	_boss_hp = maxf(0.0, _boss_hp - total)
	return total


func _finish(result: String) -> void:
	if _over:
		return
	_over = true
	_refresh_status()
	battle_finished.emit(result)


# ------------------------------------------------------------------ animation

## Builds one tween timeline for the move: swap, then per cascade step a pop and
## a drop. Board state is pushed from the engine's snapshots so the display can
## never drift from the model.
func _animate_move(from: Vector2i, to: Vector2i, result: Dictionary, reshuffled: bool) -> void:
	# Input is gated on _busy, but play_move() is also a public API (retry paths,
	# tests). A second move mid-timeline must not leave half a board in flight.
	_kill_board_tweens()
	var undone: Array = result.get("grid_before", _engine.grid()).duplicate(true)
	var swapped: int = undone[from.y][from.x]
	undone[from.y][from.x] = undone[to.y][to.x]
	undone[to.y][to.x] = swapped
	_snap_board(undone)
	_busy = true
	var a: Panel = _visuals[from.y][from.x]
	var b: Panel = _visuals[to.y][to.x]
	var offset: Vector2 = Vector2(to - from) * float(BOARD_SPAN)
	var tw := create_tween()
	_move_tween = tw
	tw.set_parallel(true)
	tw.tween_property(a, "position", offset, SWAP_TIME)
	tw.tween_property(b, "position", -offset, SWAP_TIME)
	tw.set_parallel(false)
	tw.tween_callback(func() -> void:
		a.position = Vector2.ZERO
		b.position = Vector2.ZERO
		_snap_board(result.get("grid_before", _engine.grid())))
	for ev in result.get("events", []):
		var step: Dictionary = ev
		tw.tween_callback(_pop_cells.bind(step))
		tw.tween_interval(POP_TIME)
		tw.tween_callback(_drop_cells.bind(step))
		tw.tween_interval(DROP_TIME)
	tw.tween_callback(func() -> void:
		# Whatever the cascade did, the board the player is handed back is the
		# engine's own board. Nothing here is allowed to drift.
		_kill_cell_tweens()
		_snap_board(_engine.grid())
		if reshuffled:
			_float_text("Board reshuffled", ACCENT, size * 0.4)
		_busy = false
		_refresh_status())


func _kill_board_tweens() -> void:
	if _move_tween != null and _move_tween.is_valid():
		_move_tween.kill()
	_kill_cell_tweens()


## A pop tween fades a tile to alpha 0 over exactly POP_TIME, and the drop step
## that follows fires on the same boundary — so the fade could outlive the snap
## that refilled the cell and leave a permanent hole in the board. Every snap
## kills the tweens that were driving the tiles it is about to overwrite.
func _kill_cell_tweens() -> void:
	for t in _cell_tweens:
		if t != null and (t as Tween).is_valid():
			(t as Tween).kill()
	_cell_tweens.clear()


func _pop_cells(step: Dictionary) -> void:
	var cells: Array = step.get("cells", [])
	for c in cells:
		var p: Vector2i = c
		if p.x < 0 or p.x > 7 or p.y < 0 or p.y > 7:
			continue
		var vis: Panel = _visuals[p.y][p.x]
		var tw := create_tween()
		_cell_tweens.append(tw)
		tw.set_parallel(true)
		tw.tween_property(vis, "scale", Vector2(1.25, 1.25), POP_TIME * 0.35)
		tw.chain().tween_property(vis, "scale", Vector2(0.1, 0.1), POP_TIME * 0.65)
		tw.parallel().tween_property(vis, "modulate:a", 0.0, POP_TIME * 0.65)
	var attacks: Array = step.get("attacks", [])
	if attacks.is_empty():
		return
	UI.play_sfx(self, "buy")
	var total := 0.0
	for atk in attacks:
		var idx: int = int(atk.get("manager_index", -1))
		if idx < 0 or idx >= _team.size():
			continue
		total += BattleMath.manager_attack(
			_team[idx].get("def", {}), _team[idx].get("state", {})) \
			* float(atk.get("charge_mult", 1.0))
	if total > 0.0:
		# Damage lands ON the tiles that earned it. It used to spawn at a fixed
		# (300,120), ~130px above the board, in the host screen's header band.
		_float_text("-%d" % int(round(total)), UI.DANGER, _centroid(cells))


## Applies the post-cascade grid and drops every column that lost tiles in from
## above, so gravity reads as gravity instead of the board snapping.
func _drop_cells(step: Dictionary) -> void:
	var per_column := {}
	for c in step.get("cells", []):
		var p: Vector2i = c
		per_column[p.x] = int(per_column.get(p.x, 0)) + 1
	_kill_cell_tweens()
	_snap_board(step.get("grid_after", _engine.grid()))
	for x in per_column.keys():
		var drop: float = float(int(per_column[x])) * float(BOARD_SPAN)
		for y in 8:
			var vis: Panel = _visuals[y][int(x)]
			vis.position = Vector2(0.0, -drop)
			var tw := create_tween()
			_cell_tweens.append(tw)
			tw.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
			tw.tween_property(vis, "position", Vector2.ZERO, DROP_TIME)


func _centroid(cells: Array) -> Vector2:
	if _board == null or not is_instance_valid(_board):
		return size * 0.5
	if cells.is_empty():
		return _board.global_position - global_position + Vector2(size.x, 0) * 0.0
	var sum := Vector2.ZERO
	for c in cells:
		sum += Vector2(c) * float(BOARD_SPAN)
	sum /= float(cells.size())
	return _board.global_position - global_position + sum + Vector2(TILE, TILE) * 0.5


func _snap_board(grid: Array) -> void:
	for y in 8:
		for x in 8:
			var t: int = int(grid[y][x])
			var vis: Panel = _visuals[y][x]
			vis.position = Vector2.ZERO
			vis.scale = Vector2.ONE
			vis.modulate.a = 1.0
			_display[y][x] = t
			_paint_cell(x, y)


func _paint_cell(x: int, y: int) -> void:
	var t: int = int(_display[y][x])
	if t < 0 or t >= TILE_COLORS.size():
		return
	var vis: Panel = _visuals[y][x]
	var selected: bool = _selected == Vector2i(x, y)
	var focus: int = _engine.focus_type() if _engine != null else -1
	var sb := StyleBoxFlat.new()
	sb.bg_color = TILE_COLORS[t]
	sb.set_corner_radius_all(TILE_RADIUS[t])
	sb.set_border_width_all(3)
	sb.border_width_bottom = 6  # extruded lip: the tile reads as a physical piece
	sb.border_color = tile_rim(t)
	if selected:
		sb.set_border_width_all(6)
		sb.border_color = INK
	elif t == focus:
		# The audited colour wears a bright collar so the one thing worth hunting
		# is findable in a glance; the drop shadow still carries separation.
		sb.set_border_width_all(5)
		sb.border_color = Color.WHITE
	sb.shadow_color = Color(0.06, 0.03, 0.16, 0.30)
	sb.shadow_size = 4
	sb.shadow_offset = Vector2(0, 2)
	var inset: int = TILE_INSET[t]
	sb.expand_margin_left = -inset
	sb.expand_margin_right = -inset
	sb.expand_margin_top = -inset
	sb.expand_margin_bottom = -inset
	vis.add_theme_stylebox_override("panel", sb)
	if not selected:
		vis.scale = Vector2.ONE
	var glyph: Label = vis.get_child(0)
	glyph.text = GLYPHS[t]
	# Gold under a white letter was a 1.26:1 glyph. Pick whichever ink wins on
	# this hue and rim it with the opposite, so every letter reads on every tile.
	# No outline on the tile glyphs. Measured under GL Compatibility, an outlined
	# label is a second draw call per tile — 64 of them, 690 -> 754 with a battle
	# open — and glyph_ink() already guarantees at least 3:1 on every hue, so the
	# rim was buying nothing. The tile drop shadows, by contrast, are free.
	glyph.add_theme_color_override("font_color", glyph_ink(t))


func _refresh_status() -> void:
	if _meter == null or not is_instance_valid(_meter):
		return
	_meter.value = 100.0 * _boss_hp / maxf(_boss_hp_max, 1.0)
	_hp_label.text = "%d/%d" % [int(ceil(_boss_hp)), int(ceil(_boss_hp_max))]
	_moves_label.text = "Moves %d" % maxi(_moves, 0)
	_moves_label.add_theme_color_override("font_color",
		UI.DANGER if _moves <= 3 else INK)
	var charges: Array = _engine.get_charges()
	for i in _pips.size():
		_pips[i].value = float(charges[i]) if i < charges.size() else 0.0
	_refresh_focus()


func _refresh_focus() -> void:
	if _focus_chip == null or not is_instance_valid(_focus_chip):
		return
	var f: int = _engine.focus_type()
	if f < 0 or f >= DEPT_NAMES.size():
		_focus_chip.visible = false
		return
	_focus_chip.visible = true
	# Name the manager the audit is actually paying, so the chip and the pips
	# tell one story instead of two.
	for i in _pip_names.size():
		var spec: String = str((_team[i].get("def", {}) as Dictionary).get("specialty", ""))
		var slot: int = int(SPEC_TO_TILE.get(spec, 4))
		(_pip_names[i] as Label).add_theme_color_override("font_color",
			tile_rim(slot) if slot == f else INK)
	var chip_sb := UI.make_panel(TILE_COLORS[f], 16, 0)
	chip_sb.content_margin_left = 20
	chip_sb.content_margin_right = 20
	chip_sb.content_margin_top = 6
	chip_sb.content_margin_bottom = 6
	_focus_chip.add_theme_stylebox_override("panel", chip_sb)
	var chip_ink: Color = glyph_ink(f)
	_focus_label.add_theme_color_override("font_color", chip_ink)
	_focus_label.add_theme_color_override("font_outline_color",
		Color(1, 1, 1, 0.7) if chip_ink != Color.WHITE else Color(0, 0, 0, 0.5))
	var streak: int = _engine.focus_streak()
	_focus_label.text = "AUDIT: %s   x%.1f" % [DEPT_NAMES[f], _engine.focus_multiplier()]
	if streak >= 2:
		_focus_label.text += "  (chain %d)" % streak
	if _painted_focus == f:
		return  # the collars are already on the right colour
	_painted_focus = f
	for y in 8:
		for x in 8:
			_paint_cell(x, y)


func _shake_cell(pos: Vector2i) -> void:
	if pos.x < 0 or pos.x > 7 or pos.y < 0 or pos.y > 7:
		return
	var vis: Panel = _visuals[pos.y][pos.x]
	var tw := create_tween()
	for i in 3:
		tw.tween_property(vis, "position:x", 7.0 if i % 2 == 0 else -7.0, 0.05)
	tw.tween_property(vis, "position:x", 0.0, 0.05)


## `at` is a position in this view's local space, so callers can aim at the
## board cells that earned the number rather than at a fixed header slot.
func _float_text(text: String, color: Color, at: Vector2) -> void:
	if _float_layer == null or not is_instance_valid(_float_layer):
		return
	var l := UI.make_display_label(text, UI.TYPE_HERO, color)
	UI.add_text_halo(l, Color(1, 1, 1, 0.85), 6)
	l.position = Vector2(clampf(at.x, 8.0, maxf(size.x - 90.0, 8.0)),
		clampf(at.y, 8.0, maxf(size.y - 60.0, 8.0)))
	_float_layer.add_child(l)
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(l, "position:y", l.position.y - 70.0, 0.7)
	tw.tween_property(l, "scale", Vector2(1.25, 1.25), 0.18)
	tw.chain().tween_property(l, "modulate:a", 0.0, 0.45)
	tw.tween_callback(l.queue_free)
