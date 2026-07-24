extends PanelContainer
## Department panel (SPEC §9): zone wall in dept color, floating badge, visual strip
## (ticket queue dots bobbing / archive cart dots tweening / staff dots elsewhere),
## 3 upgrade rows (Staff/Speed/Value), tap body = manual_collect with floating "+N".

const UI := preload("res://scripts/ui/ui_kit.gd")

const TRACKS: Array[String] = ["staff", "speed", "value"]
const MAX_DOTS := 12

var venue_id: String = ""
var dept_id: String = ""

var _row_level := {}   # track -> Label
var _row_effect := {}  # track -> Label
var _row_btn := {}     # track -> Button
var _tag: Label
var _strip: Control
var _queue_dots: Array[Control] = []
var _cart_dots: Array[Control] = []
var _cart_tweens: Array[Tween] = []
var _staff_dot_box: HBoxContainer
var _bob_t: float = 0.0

func _ready() -> void:
	var def: Dictionary = DataLoader.dept_def(dept_id)
	var col: Color = UI.DEPT_COLORS.get(dept_id, UI.ACCENT)

	# Zone wall: tinted floor + 3px dept-color border, radius 12 (SPEC §2/§9).
	var wall := UI.make_panel(col.lerp(UI.PANEL, 0.86), 12, 3)
	wall.border_color = col
	add_theme_stylebox_override("panel", wall)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 14)
	margin.add_theme_constant_override("margin_right", 14)
	margin.add_theme_constant_override("margin_top", 12)
	margin.add_theme_constant_override("margin_bottom", 12)
	add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	margin.add_child(vbox)

	# Header: floating circular badge + dept name + bottleneck tag.
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 12)
	header.mouse_filter = Control.MOUSE_FILTER_STOP
	header.gui_input.connect(_on_body_input)
	vbox.add_child(header)

	header.add_child(UI.make_badge(str(def.get("icon", "?")), col))
	var name_l := UI.make_label(str(def.get("name", dept_id)), 24)
	name_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	header.add_child(name_l)
	_tag = UI.make_label("BOTTLENECK", 18)
	_tag.add_theme_color_override("font_color", UI.DANGER)
	_tag.visible = false
	header.add_child(_tag)

	# Visual strip (tap body for manual collect).
	_strip = Control.new()
	_strip.custom_minimum_size = Vector2(0, 56)
	_strip.clip_contents = true
	_strip.mouse_filter = Control.MOUSE_FILTER_STOP
	_strip.gui_input.connect(_on_body_input)
	_strip.resized.connect(_restart_cart_tweens)
	vbox.add_child(_strip)
	var strip_bg := ColorRect.new()
	strip_bg.color = col.lerp(UI.PANEL, 0.7)
	strip_bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	strip_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_strip.add_child(strip_bg)

	_staff_dot_box = HBoxContainer.new()
	_staff_dot_box.add_theme_constant_override("separation", 6)
	_staff_dot_box.position = Vector2(10, 20)
	_staff_dot_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_strip.add_child(_staff_dot_box)

	# 3 upgrade rows.
	for track in TRACKS:
		vbox.add_child(_make_upgrade_row(track, col))

	EventBus.cash_changed.connect(_on_econ_change)
	EventBus.department_upgraded.connect(_on_department_upgraded)

	refresh()

func _make_upgrade_row(track: String, col: Color) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	var name_l := UI.make_label(track.capitalize(), 20)
	name_l.custom_minimum_size = Vector2(80, 0)
	row.add_child(name_l)
	var lv_l := UI.make_label("Lv 1", 20)
	lv_l.custom_minimum_size = Vector2(70, 0)
	row.add_child(lv_l)
	var fx_l := UI.make_label("", 18)
	fx_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(fx_l)
	var btn := UI.make_button("$0", UI.UPGRADE_GREEN)
	btn.custom_minimum_size = Vector2(170, 56)
	btn.add_theme_font_size_override("font_size", 22)
	btn.pressed.connect(_on_buy.bind(track))
	row.add_child(btn)
	_row_level[track] = lv_l
	_row_effect[track] = fx_l
	_row_btn[track] = btn
	return row

## Cost for the next level of a track (mirrors Economy._cost; SPEC §4 upgrade_cost).
func _cost_for(track: String) -> BigNumber:
	var venue: Dictionary = DataLoader.get_venue(venue_id)
	var level: int = GameState.dept_level(venue_id, dept_id, track)
	return DataLoader.upgrade_cost(dept_id, track, level,
		float(venue.get("cost_mult", 1.0)), int(venue.get("cost_exp", 0)))

func _is_maxed(track: String) -> bool:
	if track != "staff":
		return false
	var def: Dictionary = DataLoader.dept_def(dept_id)
	return GameState.dept_level(venue_id, dept_id, "staff") >= int(def.get("max_staff", 99))

func refresh() -> void:
	if venue_id == "" or dept_id == "":
		return
	var def: Dictionary = DataLoader.dept_def(dept_id)
	for track in TRACKS:
		var level: int = GameState.dept_level(venue_id, dept_id, track)
		(_row_level[track] as Label).text = "Lv %d" % level
		(_row_effect[track] as Label).text = _effect_text(track, def, level)
		var btn: Button = _row_btn[track]
		if _is_maxed(track):
			btn.text = "MAX"
			btn.disabled = true
			btn.remove_theme_color_override("font_disabled_color")
		else:
			var cost: BigNumber = _cost_for(track)
			btn.text = "$" + cost.to_notation()
			var affordable: bool = GameState.cash.gte(cost)
			btn.disabled = not affordable
			if affordable:
				btn.remove_theme_color_override("font_disabled_color")
			else:
				btn.add_theme_color_override("font_disabled_color", UI.DANGER)
	_update_staff_dots()

func _effect_text(track: String, def: Dictionary, level: int) -> String:
	if track == "staff":
		if _is_maxed(track):
			return "units %d (max)" % level
		return "units %d → %d" % [level, level + 1]
	var t: Dictionary = def.get("tracks", {}).get(track, {})
	var cur: float = Economy.dept_stat(venue_id, dept_id, track)
	var nxt: float = (float(t.get("base_stat", 1.0)) + float(t.get("per_level", 0.0)) * float(level)) \
		* DataLoader.track_step_multiplier(dept_id, track, level + 1)
	if track in ["speed", "value"]:
		nxt *= Economy.manager_multiplier_for(dept_id)
	return "%.2f → %.2f" % [cur, nxt]

func _on_buy(track: String) -> void:
	Economy.purchase_upgrade(venue_id, dept_id, track)
	# Signals (cash_changed / department_upgraded) trigger refresh; call directly too.
	refresh()

func _on_econ_change(_v: Variant = null) -> void:
	refresh()

func _on_department_upgraded(v_id: String, d_id: String, _track: String, _level: int) -> void:
	if v_id == venue_id and d_id == dept_id:
		refresh()

# --- Visual strip -----------------------------------------------------------

func set_bottleneck(on: bool) -> void:
	_tag.visible = on

## Ticket: queue dots = waiting visitors, slight bob. Count from arrival/serve deficit.
func update_queue(arrival_per_s: float, serve_per_s: float) -> void:
	if dept_id != "ticket":
		return
	var count: int = clampi(int(maxf(0.0, arrival_per_s - serve_per_s) * 20.0), 0, MAX_DOTS)
	if count == _queue_dots.size():
		return
	for d in _queue_dots:
		d.queue_free()
	_queue_dots.clear()
	var col: Color = UI.DEPT_COLORS.get(dept_id, UI.ACCENT)
	for i in count:
		var dot := UI.make_dot(col, 14)
		dot.position = Vector2(12 + i * 20, 24)
		_strip.add_child(dot)
		_queue_dots.append(dot)

func _process(delta: float) -> void:
	if dept_id == "ticket" and not _queue_dots.is_empty():
		_bob_t += delta
		for i in _queue_dots.size():
			_queue_dots[i].position.y = 24.0 + sin(_bob_t * 4.0 + float(i) * 0.7) * 4.0

func _update_staff_dots() -> void:
	if dept_id in ["ticket", "archive"]:
		_staff_dot_box.visible = false
	else:
		_staff_dot_box.visible = true
		var staff: int = GameState.dept_level(venue_id, dept_id, "staff")
		while _staff_dot_box.get_child_count() > mini(staff, MAX_DOTS):
			_staff_dot_box.get_child(_staff_dot_box.get_child_count() - 1).queue_free()
		var col: Color = UI.DEPT_COLORS.get(dept_id, UI.ACCENT)
		while _staff_dot_box.get_child_count() < mini(staff, MAX_DOTS):
			_staff_dot_box.add_child(UI.make_dot(col, 14))
	if dept_id == "archive":
		_rebuild_cart_dots()

## Archive: cart dots moving left → right (looping tweens), count = staff.
func _rebuild_cart_dots() -> void:
	var staff: int = clampi(GameState.dept_level(venue_id, dept_id, "staff"), 0, MAX_DOTS)
	if staff == _cart_dots.size() and not _cart_dots.is_empty():
		return  # refresh() runs often; only rebuild when staff count changes
	for tw in _cart_tweens:
		if tw and tw.is_valid():
			tw.kill()
	_cart_tweens.clear()
	for d in _cart_dots:
		d.queue_free()
	_cart_dots.clear()
	var col: Color = UI.DEPT_COLORS.get("archive", UI.SLATE)
	for i in staff:
		var dot := UI.make_dot(col, 16)
		dot.position = Vector2(-20, 22)
		_strip.add_child(dot)
		_cart_dots.append(dot)
	_start_cart_tweens()

func _start_cart_tweens() -> void:
	var travel: float = maxf(_strip.size.x, 620.0)
	for i in _cart_dots.size():
		var dot := _cart_dots[i]
		var tw := dot.create_tween().set_loops()
		tw.tween_interval(float(i) * 0.55)
		tw.tween_property(dot, "position:x", travel, 3.2).from(-20.0)
		_cart_tweens.append(tw)

func _restart_cart_tweens() -> void:
	if dept_id != "archive" or _cart_dots.is_empty():
		return
	for tw in _cart_tweens:
		if tw and tw.is_valid():
			tw.kill()
	_cart_tweens.clear()
	for dot in _cart_dots:
		dot.position.x = -20.0
	_start_cart_tweens()

# --- Tap to collect ----------------------------------------------------------

func _on_body_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_tap_collect(_strip.get_local_mouse_position())

func _tap_collect(pos: Vector2) -> void:
	var amount: BigNumber = Economy.manual_collect(venue_id)
	if amount.is_zero():
		return
	var col: Color = UI.DEPT_COLORS.get(dept_id, UI.ACCENT)
	var fl := UI.make_label("+" + amount.to_notation(), 26)
	fl.add_theme_color_override("font_color", col.darkened(0.15))
	fl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_strip.add_child(fl)
	fl.position = Vector2(clampf(pos.x - 20.0, 4.0, maxf(_strip.size.x - 90.0, 4.0)), 8.0)
	var tw := fl.create_tween()
	tw.set_parallel(true)
	tw.tween_property(fl, "position:y", fl.position.y - 44.0, 1.1)
	tw.tween_property(fl, "modulate:a", 0.0, 1.1)
	tw.chain().tween_callback(fl.queue_free)
