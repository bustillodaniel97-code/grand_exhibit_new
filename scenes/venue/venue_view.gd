extends Control
## VenueView (SPEC §9, "Living Floor" pass): the Museum tab is now the live
## museum diorama (scenes/venue/floor/venue_floor.tscn) with the quests bar as
## a slim strip on top. Tapping a room on the floor opens a bottom-sheet
## upgrade card for that department (DeptPanel rows + big green buy buttons).
## Polls Economy.venue_rates every 0.5s and feeds the floor (SPEC §3.5).

const UI := preload("res://scripts/ui/ui_kit.gd")
const DeptPanel := preload("res://scenes/venue/dept_panel.gd")
const FloorScene := preload("res://scenes/venue/floor/venue_floor.tscn")

const QUESTS_BAR_PATH := "res://scenes/meta/quests_bar.tscn"

var _floor: Control
var _sheet_dim: ColorRect
var _sheet: PanelContainer
var _sheet_title: Label
var _panel_holder: Control
var _sheet_bottleneck: Label
var _panels := {}  # dept_id -> DeptPanel (lazily created, reused)
var _open_dept: String = ""
var _timer: Timer
var _sheet_tween: Tween

func _ready() -> void:
	name = "VenueView"

	var vbox := VBoxContainer.new()
	vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	vbox.add_theme_constant_override("separation", 0)
	add_child(vbox)

	# Quests bar from the meta branch — slim strip over the floor top
	# (embed by path only; no cross-branch preload).
	if ResourceLoader.exists(QUESTS_BAR_PATH):
		var qb: Control = (load(QUESTS_BAR_PATH) as PackedScene).instantiate()
		qb.custom_minimum_size = Vector2(0, 132)
		vbox.add_child(qb)

	_floor = FloorScene.instantiate()
	_floor.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_floor.dept_selected.connect(_open_sheet)
	vbox.add_child(_floor)

	_build_sheet()

	_timer = Timer.new()
	_timer.wait_time = 0.5
	_timer.autostart = true
	_timer.timeout.connect(_poll_rates)
	add_child(_timer)

	_poll_rates()

# --- Bottom-sheet upgrade card -------------------------------------------------

func _build_sheet() -> void:
	# Dim behind the sheet — VISUAL ONLY. It must never consume input:
	# with a STOP filter it swallowed every tap while a sheet was open, so
	# tapping another room closed the sheet instead of switching to it
	# (player bug: "room taps unreliable"). The floor stays tappable; the
	# sheet's ✕ button closes it.
	_sheet_dim = ColorRect.new()
	_sheet_dim.color = Color(0, 0, 0, 0.35)
	_sheet_dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_sheet_dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_sheet_dim.visible = false
	# Above every layer the floor draws (cast 0, cash floats 1, plaques 2).
	_sheet_dim.z_index = 8
	add_child(_sheet_dim)

	_sheet = PanelContainer.new()
	_sheet.name = "DeptSheet"
	_sheet.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_sheet.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_sheet.offset_left = 10
	_sheet.offset_right = -10
	_sheet.offset_bottom = -8
	_sheet.offset_top = 0  # zero height while closed
	_sheet.visible = false
	_sheet.add_theme_stylebox_override("panel", UI.make_panel(UI.PANEL, UI.RADIUS_CARD, 3))
	_sheet.z_index = 9
	add_child(_sheet)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 14)
	margin.add_theme_constant_override("margin_right", 14)
	margin.add_theme_constant_override("margin_top", 10)
	margin.add_theme_constant_override("margin_bottom", 12)
	_sheet.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	margin.add_child(vbox)

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 10)
	vbox.add_child(header)
	_sheet_title = UI.make_label("", 26)
	_sheet_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(_sheet_title)
	_sheet_bottleneck = UI.make_label("BOTTLENECK", 18)
	_sheet_bottleneck.add_theme_color_override("font_color", UI.DANGER)
	_sheet_bottleneck.visible = false
	header.add_child(_sheet_bottleneck)
	var close_btn := UI.make_button("✕", UI.INK)
	close_btn.custom_minimum_size = Vector2(52, 48)
	close_btn.pressed.connect(_close_sheet)
	header.add_child(close_btn)

	_panel_holder = Control.new()
	_panel_holder.name = "PanelHolder"
	_panel_holder.custom_minimum_size = Vector2(0, 356)
	vbox.add_child(_panel_holder)

func _open_sheet(dept_id: String) -> void:
	if not _panels.has(dept_id):
		var p := DeptPanel.new()
		p.name = "DeptPanel"
		p.venue_id = GameState.current_venue
		p.dept_id = dept_id
		p.embedded_in_sheet = true
		# DeptPanel _ready runs on add; ids set above so it builds correctly.
		p.set_anchors_preset(Control.PRESET_FULL_RECT)
		_panel_holder.add_child(p)
		_panels[dept_id] = p
	for id in _panels.keys():  # only the tapped dept's card shows
		_panels[id].visible = id == dept_id
	_open_dept = dept_id
	var def: Dictionary = DataLoader.dept_def(dept_id)
	_sheet_title.text = str(def.get("name", dept_id))
	(_panels[dept_id] as DeptPanel).refresh()
	_sheet_bottleneck.visible = _floor.get_choke() == dept_id

	_sheet.visible = true
	_sheet_dim.visible = true
	var h: float = minf(_sheet.get_combined_minimum_size().y, maxf(size.y - 24.0, 200.0))
	if _sheet_tween and _sheet_tween.is_valid():
		_sheet_tween.kill()  # never let open/close tweens fight over offset_top
	_sheet_tween = create_tween()
	_sheet_tween.tween_property(_sheet, "offset_top", -h, 0.22).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

func _close_sheet() -> void:
	if not _sheet.visible:
		return
	_open_dept = ""
	if _sheet_tween and _sheet_tween.is_valid():
		_sheet_tween.kill()
	_sheet_tween = create_tween()
	_sheet_tween.tween_property(_sheet, "offset_top", 0.0, 0.18).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	_sheet_tween.tween_callback(func() -> void:
		_sheet.visible = false
		_sheet_dim.visible = false)

# --- Rates poll -----------------------------------------------------------------

func _poll_rates() -> void:
	if not GameState.ready_flag:
		return
	var rates: Dictionary = Economy.venue_rates(GameState.current_venue)
	_floor.set_rates(rates)
	if _open_dept != "" and _panels.has(_open_dept):
		_sheet_bottleneck.visible = str(rates.get("choke_id", "")) == _open_dept
