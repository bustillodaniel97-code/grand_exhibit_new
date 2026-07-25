extends Control
## Shared match-3 battle view (SPEC §6): 8x8 board, boss citation meter,
## moves counter, per-manager charge pips. Used by Inspection Frenzy stages
## and the Expedition boss. Config via setup_battle(), result via signal.

signal battle_finished(result: String)  # "win" | "lose"

const Match3 = preload("res://scripts/events/match3_engine.gd")
const BattleMath = preload("res://scripts/events/battle_math.gd")

const UI := preload("res://scripts/ui/ui_kit.gd")
## Tile colours ARE the department colours — a player has to read a board tile as
## "that's my archive specialist" instantly, so they must not drift from the
## floor's palette. These were a private copy of the retired muted scheme.
const TILE_COLORS := [
	UI.DEPT_COLORS["promotions"],
	UI.DEPT_COLORS["ticket"],
	UI.DEPT_COLORS["archive"],
	UI.DEPT_COLORS["gallery"],
	UI.PANEL_SOFT,                 # neutral
]
const GLYPHS := ["P", "T", "A", "G", "•"]
const SPEC_TO_TILE := {"promotions": 0, "ticket": 1, "archive": 2, "gallery": 3}
const INK := UI.INK
const PANEL := UI.PANEL
const ACCENT := UI.ACCENT
const TILE := 72
const GAP := 6

var _engine  # Match3 instance (untyped: duck-typed calls)
var _team: Array = []        # [{"def":Dictionary, "state":Dictionary}]
var _boss_hp := 1.0
var _boss_hp_max := 1.0
var _moves := 0
var _over := false
var _selected := Vector2i(-1, -1)
var _cells: Array = []       # [y][x] -> Panel
var _meter: ProgressBar
var _hp_label: Label
var _moves_label: Label
var _pips: Array = []        # ProgressBar per manager slot
var _float_layer: Control


func setup_battle(cfg: Dictionary) -> void:
	# cfg: {boss_name:String, boss_hp:float, moves:int, team:Array, seed:int}
	for c in get_children():
		c.queue_free()
	_cells.clear()
	_pips.clear()
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
	_selected = Vector2i(-1, -1)
	_build_ui(str(cfg.get("boss_name", "Inspector")))
	_refresh_board()
	_refresh_status()


func _build_ui(boss_name: String) -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var root := VBoxContainer.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_theme_constant_override("separation", 10)
	root.alignment = BoxContainer.ALIGNMENT_CENTER
	add_child(root)
	_float_layer = Control.new()
	_float_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	_float_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_float_layer)

	var title := Label.new()
	title.text = boss_name
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 30)
	title.add_theme_color_override("font_color", INK)
	root.add_child(title)

	# Citation meter.
	var meter_row := HBoxContainer.new()
	meter_row.alignment = BoxContainer.ALIGNMENT_CENTER
	meter_row.add_theme_constant_override("separation", 12)
	root.add_child(meter_row)
	var meter_title := Label.new()
	meter_title.text = "Citation Meter"
	meter_title.add_theme_color_override("font_color", INK)
	meter_row.add_child(meter_title)
	_meter = ProgressBar.new()
	_meter.custom_minimum_size = Vector2(340, 26)
	_meter.max_value = 100.0
	_meter.show_percentage = false
	_meter.add_theme_stylebox_override("background", _style(PANEL, 8))
	_meter.add_theme_stylebox_override("fill", _style(ACCENT, 8))
	meter_row.add_child(_meter)
	_hp_label = Label.new()
	_hp_label.add_theme_color_override("font_color", INK)
	meter_row.add_child(_hp_label)

	# Moves + manager charge pips.
	var mid_row := HBoxContainer.new()
	mid_row.alignment = BoxContainer.ALIGNMENT_CENTER
	mid_row.add_theme_constant_override("separation", 24)
	root.add_child(mid_row)
	_moves_label = Label.new()
	_moves_label.add_theme_font_size_override("font_size", 24)
	_moves_label.add_theme_color_override("font_color", INK)
	mid_row.add_child(_moves_label)
	for i in _team.size():
		var def: Dictionary = _team[i].get("def", {})
		var box := VBoxContainer.new()
		box.add_theme_constant_override("separation", 2)
		var name_l := Label.new()
		name_l.text = str(def.get("name", "Manager")).split(" ")[0]
		name_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		name_l.add_theme_font_size_override("font_size", 14)
		name_l.add_theme_color_override("font_color", INK)
		box.add_child(name_l)
		var pip := ProgressBar.new()
		pip.custom_minimum_size = Vector2(120, 14)
		pip.max_value = 100.0
		pip.show_percentage = false
		var col: Color = TILE_COLORS[int(SPEC_TO_TILE.get(str(def.get("specialty", "")), 4))]
		pip.add_theme_stylebox_override("background", _style(PANEL, 6))
		pip.add_theme_stylebox_override("fill", _style(col, 6))
		box.add_child(pip)
		mid_row.add_child(box)
		_pips.append(pip)

	# Board.
	var center := CenterContainer.new()
	root.add_child(center)
	var grid_box := GridContainer.new()
	grid_box.columns = 8
	grid_box.add_theme_constant_override("h_separation", GAP)
	grid_box.add_theme_constant_override("v_separation", GAP)
	center.add_child(grid_box)
	for y in 8:
		var row: Array = []
		for x in 8:
			var cell := Panel.new()
			cell.custom_minimum_size = Vector2(TILE, TILE)
			var glyph := Label.new()
			glyph.set_anchors_preset(Control.PRESET_FULL_RECT)
			glyph.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			glyph.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			glyph.add_theme_font_size_override("font_size", 30)
			glyph.add_theme_color_override("font_color", Color.WHITE)
			cell.add_child(glyph)
			var pos := Vector2i(x, y)
			cell.gui_input.connect(_on_cell_input.bind(pos))
			grid_box.add_child(cell)
			row.append(cell)
		_cells.append(row)


func _style(color: Color, radius: int, border := Color.TRANSPARENT) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = color
	sb.set_corner_radius_all(radius)
	if border != Color.TRANSPARENT:
		sb.set_border_width_all(3)
		sb.border_color = border
	return sb


func _on_cell_input(event: InputEvent, pos: Vector2i) -> void:
	if _over:
		return
	var tapped := false
	if event is InputEventMouseButton:
		tapped = event.pressed and event.button_index == MOUSE_BUTTON_LEFT
	elif event is InputEventScreenTouch:
		tapped = event.pressed
	if tapped:
		_on_cell_tapped(pos)


func _on_cell_tapped(pos: Vector2i) -> void:
	if _selected == Vector2i(-1, -1):
		_selected = pos
		_refresh_board()
		return
	if pos == _selected:
		_selected = Vector2i(-1, -1)
		_refresh_board()
		return
	if not _engine.can_swap(_selected, pos):
		_selected = pos  # retarget selection to the new tile
		_refresh_board()
		return
	var from := _selected
	_selected = Vector2i(-1, -1)
	var result: Dictionary = _engine.try_swap(from, pos)
	if not result["swapped"]:
		_shake_cell(from)
		_shake_cell(pos)
		_refresh_board()
		return
	_moves -= 1
	_apply_result(result)
	_refresh_board()
	_refresh_status()
	if _boss_hp <= 0.0:
		_finish("win")
	elif _moves <= 0:
		_finish("lose")
	elif _engine.is_deadlocked():
		_engine.reshuffle()
		_refresh_board()
		_float_text("Reshuffled!", ACCENT)


func _apply_result(result: Dictionary) -> void:
	for atk in result.get("attacks", []):
		var idx: int = int(atk.get("manager_index", -1))
		if idx < 0 or idx >= _team.size():
			continue
		var dmg: float = BattleMath.manager_attack(
			_team[idx].get("def", {}), _team[idx].get("state", {})) \
			* float(atk.get("charge_mult", 1.0))
		_boss_hp = maxf(0.0, _boss_hp - dmg)
		_float_text("-%d" % int(round(dmg)), ACCENT)


func _refresh_board() -> void:
	var g: Array = _engine.grid()
	for y in 8:
		for x in 8:
			var t: int = g[y][x]
			var cell: Panel = _cells[y][x]
			var pos := Vector2i(x, y)
			var border := ACCENT if pos == _selected else Color.TRANSPARENT
			cell.add_theme_stylebox_override("panel", _style(TILE_COLORS[t], 10, border))
			(cell.get_child(0) as Label).text = GLYPHS[t]


func _refresh_status() -> void:
	_meter.value = 100.0 * _boss_hp / _boss_hp_max
	_hp_label.text = "%d/%d" % [int(ceil(_boss_hp)), int(ceil(_boss_hp_max))]
	_moves_label.text = "Moves: %d" % _moves
	var charges: Array = _engine.get_charges()
	for i in _pips.size():
		_pips[i].value = float(charges[i]) if i < charges.size() else 0.0


func _finish(result: String) -> void:
	if _over:
		return
	_over = true
	_float_text("STAGE CLEAR!" if result == "win" else "Out of moves…",
		UI.SAGE if result == "win" else UI.DANGER)
	battle_finished.emit(result)


func _shake_cell(pos: Vector2i) -> void:
	var cell: Panel = _cells[pos.y][pos.x]
	var base: Vector2 = cell.position
	var tw := create_tween()
	for i in 3:
		tw.tween_property(cell, "position:x", base.x + (6.0 if i % 2 == 0 else -6.0), 0.05)
	tw.tween_property(cell, "position:x", base.x, 0.05)


func _float_text(text: String, color: Color) -> void:
	if _float_layer == null:
		return
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 26)
	l.add_theme_color_override("font_color", color)
	l.position = Vector2(300.0 + float(randi_range(-60, 60)), 120.0)
	_float_layer.add_child(l)
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(l, "position:y", l.position.y - 60.0, 0.8)
	tw.tween_property(l, "modulate:a", 0.0, 0.8)
	tw.set_parallel(false)
	tw.tween_callback(l.queue_free)
