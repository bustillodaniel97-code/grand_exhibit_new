extends Control
## VenueView (SPEC §9, "Living Floor" pass): the Museum tab is now the live
## museum diorama (scenes/venue/floor/venue_floor.tscn) with the quests bar as
## a slim strip on top. Tapping a room on the floor opens a bottom-sheet
## upgrade card for that department (DeptPanel rows + big green buy buttons).
## Polls Economy.venue_rates every 0.5s and feeds the floor (SPEC §3.5).

const UI := preload("res://scripts/ui/ui_kit.gd")
const Chrome := preload("res://scripts/ui/museum_chrome.gd")
const Popups := preload("res://scripts/ui/popup_manager.gd")
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
var _panels_venue: String = ""
var _timer: Timer
var _sheet_tween: Tween
var _sheet_scroll: ScrollContainer
var _sheet_close_btn: Button
var _return_focus: Control
var _back_handled_frame: int = -1

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
	_floor.item_selected.connect(_open_item_sheet)
	vbox.add_child(_floor)

	_build_sheet()
	resized.connect(_resize_sheet)
	_panels_venue = GameState.current_venue
	EventBus.prestige_performed.connect(_on_venue_changed)
	EventBus.decor_focus_requested.connect(func(_v: String, _d: String) -> void: _close_sheet())
	EventBus.department_requested.connect(func(dept_id: String) -> void:
		_open_sheet(dept_id))

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
	_sheet_dim.z_index = 100
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
	_sheet.add_theme_stylebox_override("panel", Chrome.panel(16))
	_sheet.z_index = 101
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
	_sheet_title = UI.make_display_label("", 22, Chrome.INK)
	_sheet_title.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	_sheet_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(_sheet_title)
	_sheet_bottleneck = UI.make_display_label("Limits museum income", 13, Chrome.DANGER)
	_sheet_bottleneck.add_theme_color_override("font_color", Chrome.DANGER)
	_sheet_bottleneck.visible = false
	vbox.add_child(_sheet_bottleneck)
	var close_btn := UI.make_button("✕", UI.INK)
	close_btn.custom_minimum_size = Vector2(52, 48)
	close_btn.name="CloseDepartment";close_btn.tooltip_text="Close upgrades"
	Chrome.button(close_btn)
	_sheet_close_btn=close_btn
	close_btn.pressed.connect(_close_sheet)
	header.add_child(close_btn)

	_sheet_scroll=ScrollContainer.new()
	_sheet_scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED
	_sheet_scroll.vertical_scroll_mode=ScrollContainer.SCROLL_MODE_AUTO
	_sheet_scroll.custom_minimum_size=Vector2(0,360)
	vbox.add_child(_sheet_scroll)
	_panel_holder=VBoxContainer.new();_panel_holder.name="PanelHolder"
	_panel_holder.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	_sheet_scroll.add_child(_panel_holder)
	# Header wrapping and container layout settle after the panel first opens.
	# Refit when the whole sheet changes minimum size, not only its body.
	_sheet.minimum_size_changed.connect(_resize_sheet)

func _open_sheet(dept_id: String) -> void:
	_sync_panel_venue()
	if not _panels.has(dept_id):
		var p := DeptPanel.new()
		p.name = "DeptPanel"
		p.venue_id = GameState.current_venue
		p.dept_id = dept_id
		p.embedded_in_sheet = true
		# DeptPanel _ready runs on add; ids set above so it builds correctly.
		p.size_flags_horizontal=Control.SIZE_EXPAND_FILL
		_panel_holder.add_child(p)
		_panels[dept_id] = p
		p.minimum_size_changed.connect(_resize_sheet)
	for id in _panels.keys():  # only the tapped dept's card shows
		_panels[id].visible = id == dept_id
	_open_dept = dept_id
	_sheet_title.text = DataLoader.venue_dept_name(GameState.current_venue, dept_id)
	(_panels[dept_id] as DeptPanel).refresh()
	_sheet_bottleneck.visible = _floor.get_choke() == dept_id

	if not _sheet.visible:_return_focus=get_viewport().gui_get_focus_owner()
	_sheet.visible = true
	_sheet_dim.visible = true
	_sheet_scroll.scroll_vertical=0
	_sheet_scroll.custom_minimum_size.y=_sheet_body_height()
	var h: float = minf(_sheet.get_combined_minimum_size().y, maxf(size.y - 24.0, 200.0))
	if _sheet_tween and _sheet_tween.is_valid():
		_sheet_tween.kill()  # never let open/close tweens fight over offset_top
	_sheet_tween = create_tween()
	_sheet_tween.tween_property(_sheet, "offset_top", _sheet.offset_bottom-h, 0.22).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

func _open_item_sheet(dept_id: String, index: int) -> void:
	_open_sheet(dept_id)
	if _panels.has(dept_id):
		(_panels[dept_id] as DeptPanel).select_item(index)
	# The selected unit is titled inside the panel; the sheet retains its department.
	_sheet_scroll.scroll_vertical=0

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
		_sheet_dim.visible = false
		if is_instance_valid(_return_focus) and _return_focus.is_visible_in_tree():_return_focus.grab_focus())

func _sheet_body_height() -> float:
	var available:=clampf(size.y*.66-100.0,170.0,440.0)
	if _panels.has(_open_dept):
		return minf(available,maxf(_panels[_open_dept].get_combined_minimum_size().y,140.0))
	return available

func _resize_sheet() -> void:
	if not is_instance_valid(_sheet) or not _sheet.visible:return
	if _sheet_tween and _sheet_tween.is_valid():_sheet_tween.kill()
	_sheet_scroll.custom_minimum_size.y=_sheet_body_height()
	call_deferred("_fit_open_sheet")

func _fit_open_sheet() -> void:
	if _sheet.visible:
		var height:=minf(_sheet.get_combined_minimum_size().y,maxf(size.y-24.0,200.0))
		_sheet.offset_top=_sheet.offset_bottom-height

func focus_upgrade_track(dept_id: String,track: String) -> void:
	if _open_dept!=dept_id or not _panels.has(dept_id):return
	var panel: Node=_panels[dept_id]
	if not panel._row_btn.has(track):return
	panel._show_tab(false)
	await get_tree().process_frame
	if _open_dept==dept_id and is_instance_valid(panel):
		_sheet_scroll.ensure_control_visible(panel._row_btn[track])
		panel._row_btn[track].grab_focus()

func _unhandled_input(event: InputEvent) -> void:
	if _sheet.visible and not Popups.is_open() and event.is_action_pressed("ui_cancel"):
		if Engine.get_process_frames() == _back_handled_frame:
			return
		# A Back press that already dismissed a popup this frame (via the
		# broadcast notification) must not also dismiss the sheet.
		if Engine.get_process_frames() == Popups.last_back_close_frame:
			return
		_close_sheet();get_viewport().set_input_as_handled()

## Second step of the central Back policy (popup_manager owns the first):
## with no popup open, Back closes the department sheet instead of quitting.
## Main-screen Back with nothing open stays in the game. The shared
## last_back_close_frame guard keeps one press to exactly one layer regardless
## of notification propagation order.
func _notification(what: int) -> void:
	if what == Node.NOTIFICATION_WM_GO_BACK_REQUEST:
		if Engine.get_process_frames() == Popups.last_back_close_frame:
			return
		if _sheet.visible and not Popups.is_open():
			_close_sheet()
			_back_handled_frame = Engine.get_process_frames()

## A panel contains venue-bound purchase callbacks and selected item indices.
## Retire it on graduation; relabelling a cached panel leaves its old target live.
func _on_venue_changed(_from: String, _to: String) -> void:
	_sync_panel_venue()

func _sync_panel_venue() -> void:
	if _panels_venue == GameState.current_venue:
		return
	if _sheet_tween and _sheet_tween.is_valid():
		_sheet_tween.kill()
	_open_dept = ""
	_sheet.visible = false
	_sheet_dim.visible = false
	_sheet.offset_top = 0
	for panel in _panels.values():
		_panel_holder.remove_child(panel)
		panel.queue_free()
	_panels.clear()
	_panels_venue = GameState.current_venue

# --- Rates poll -----------------------------------------------------------------

func _poll_rates() -> void:
	if not GameState.ready_flag:
		return
	_sync_panel_venue()
	var rates: Dictionary = Economy.venue_rates(GameState.current_venue)
	_floor.set_rates(rates)
	if _open_dept != "" and _panels.has(_open_dept):
		_sheet_bottleneck.visible = str(rates.get("choke_id", "")) == _open_dept
		_panels[_open_dept].refresh()
