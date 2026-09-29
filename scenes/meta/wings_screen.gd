extends Control
## Floors & Grandeur — every wing of this museum in the order it opens: what it
## needs, what it gives, and the Renovate button. The 3D floor opens this when a
## derelict floor is tapped (payload {"focus": wing_id}); the side rail opens it
## for any museum.

const UI := preload("res://scripts/ui/ui_kit.gd")
const Chrome := preload("res://scripts/ui/museum_chrome.gd")
const Popups := preload("res://scripts/ui/popup_manager.gd")
const WingSystem := preload("res://scripts/meta/wing_system.gd")

var _body: VBoxContainer
var _scroll: ScrollContainer
var _focus := ""
var _snapshot := ""
var _cards := {}  # wing id -> PanelContainer

func setup(payload: Dictionary) -> void:
	_focus = str(payload.get("focus", ""))
	_snapshot = ""
	refresh()

func _ready() -> void:
	name = "WingsScreen"
	var bg := ColorRect.new()
	bg.color = Chrome.BG
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_%s" % side, 18)
	add_child(margin)
	var root_box := VBoxContainer.new()
	root_box.add_theme_constant_override("separation", 12)
	margin.add_child(root_box)
	root_box.add_child(UI.make_display_label("Floors & Grandeur", 30, Chrome.INK))
	_scroll = ScrollContainer.new()
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root_box.add_child(_scroll)
	_body = VBoxContainer.new()
	_body.name = "WingList"
	_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_body.add_theme_constant_override("separation", 12)
	_scroll.add_child(_body)
	var t := Timer.new()
	t.wait_time = 0.5
	t.autostart = true
	t.timeout.connect(refresh)
	add_child(t)
	EventBus.wing_renovated.connect(func(_v: String, _w: String) -> void:
		_snapshot = ""
		refresh())
	refresh()

func refresh() -> void:
	if _body == null or not GameState.ready_flag:
		return
	var vid: String = GameState.current_venue
	var key := _key(vid)
	if key == _snapshot:
		return
	_snapshot = key
	var scroll_at := _scroll.scroll_vertical
	for c in _body.get_children():
		_body.remove_child(c)
		c.queue_free()
	_cards.clear()
	_body.add_child(_grandeur_card(vid))
	for w in WingSystem.wings(vid):
		var card := _wing_card(vid, w)
		_cards[str(w["id"])] = card
		_body.add_child(card)
	if _focus != "" and _cards.has(_focus):
		var target: Control = _cards[_focus]
		_focus = ""
		await get_tree().process_frame
		if is_instance_valid(target):
			_scroll.ensure_control_visible(target)
	else:
		_scroll.set_deferred("scroll_vertical", scroll_at)

func _key(vid: String) -> String:
	var parts: Array[String] = [vid, str(WingSystem.renovated(vid)),
		str((GameState.venue_state(vid).get("milestones", []) as Array).size())]
	var nxt := WingSystem.next_wing(vid)
	if not nxt.is_empty():
		var p := WingSystem.price(vid, str(nxt["id"]))
		parts.append(p.to_notation())
		parts.append(str(not GameState.cash.lt(p)))
	return "|".join(parts)

func _grandeur_card(vid: String) -> Control:
	var card := _card(true)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	card.add_child(box)
	var tier := WingSystem.grandeur_tier(vid)
	var names := WingSystem.grandeur_names()
	box.add_child(UI.make_display_label("GRANDEUR", 12, Chrome.BRASS))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	var title := _label(WingSystem.grandeur_name(vid), 26, Chrome.INK)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(title)
	for i in names.size():
		var star := UI.make_icon("star", 22, Color("#FFD34D") if i < tier else Color(1, 1, 1, 0.18))
		star.name = "Star%d" % i
		row.add_child(star)
	box.add_child(row)
	if tier - 1 < names.size():
		box.add_child(_label(str((names[tier - 1] as Dictionary).get("blurb", "")), 16, Chrome.DIM))
	box.add_child(_label("Every wing you renovate raises the museum's grandeur and dresses the outside.", 15, Chrome.DIM))
	return card

func _wing_card(vid: String, w: Dictionary) -> Control:
	var id := str(w["id"])
	var status := WingSystem.status(vid, id)
	var is_next := str(WingSystem.next_wing(vid).get("id", "")) == id
	var card := _card(is_next and status == WingSystem.STATUS_READY)
	card.name = "Wing_%s" % id
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	card.add_child(box)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 10)
	var badge := _label(str(w.get("label", "")), 20, Chrome.BG)
	badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	badge.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	badge.autowrap_mode = TextServer.AUTOWRAP_OFF
	badge.custom_minimum_size = Vector2(52, 40)
	var pill := PanelContainer.new()
	var ps := Chrome.panel(10, Chrome.TEAL if status == WingSystem.STATUS_OPEN else Chrome.BRASS)
	ps.set_content_margin_all(2)
	pill.add_theme_stylebox_override("panel", ps)
	pill.add_child(badge)
	head.add_child(pill)
	var name_l := _label(str(w.get("name", id)), 22, Chrome.INK)
	name_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(name_l)
	box.add_child(head)
	box.add_child(_label(str(w.get("blurb", "")), 15, Chrome.DIM))
	box.add_child(_label(_bonus_text(vid, w), 15, Chrome.TEAL))
	match status:
		WingSystem.STATUS_OPEN:
			box.add_child(_label("Open", 17, Chrome.TEAL))
		WingSystem.STATUS_LOCKED:
			box.add_child(_label(tr("Locked · %s") % WingSystem.requirement_text(vid, w), 16, Chrome.BRASS))
		_:
			if not is_next:
				box.add_child(_label("Opens after the floor below", 16, Chrome.BRASS))
			else:
				var price := WingSystem.price(vid, id)
				var btn := Button.new()
				btn.name = "Renovate"
				btn.text = tr("Renovate  $%s") % price.to_notation()
				btn.custom_minimum_size.y = 56
				btn.add_theme_font_override("font", UI.font())
				btn.add_theme_font_size_override("font_size", 20)
				Chrome.button(btn, true)
				btn.disabled = GameState.cash.lt(price)
				btn.pressed.connect(func() -> void:
					if WingSystem.renovate(vid, id):
						UI.play_sfx(self, "buy")
						Popups.close_top()
					else:
						EventBus.toast_requested.emit("Not enough cash yet"))
				box.add_child(btn)
	return card

func _bonus_text(vid: String, w: Dictionary) -> String:
	var bits: Array[String] = []
	bits.append(tr("x%s income") % str(snappedf(float(w.get("income_mult", 1.0)), 0.01)))
	for dept in (w.get("staff_bonus", {}) as Dictionary).keys():
		bits.append(tr("+%d %s slots") % [int(w["staff_bonus"][dept]), tr(DataLoader.venue_dept_name(vid, str(dept)))])
	var base_cap := int(DataLoader.get_venue(vid).get("track_level_cap", 100))
	var cap := int(w["cap_bonus"]) if w.has("cap_bonus") else int(round(base_cap * float(w.get("cap_bonus_frac", 0.0))))
	if cap > 0:
		bits.append(tr("+%d upgrade levels") % cap)
	return " · ".join(bits)

func _card(emphasized: bool = false) -> PanelContainer:
	var card := PanelContainer.new()
	var surface := Chrome.panel(16, Chrome.RAISED if emphasized else Chrome.PANEL)
	surface.set_content_margin_all(16)
	if emphasized:
		surface.border_color = Color("#FFD34D")
		surface.set_border_width_all(2)
	card.add_theme_stylebox_override("panel", surface)
	return card

func _label(text: String, size: int, color: Color) -> Label:
	var label := UI.make_label(text, size)
	label.add_theme_color_override("font_color", color)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return label
