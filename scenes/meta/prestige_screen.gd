extends Control
## PrestigeScreen — milestone chain summary + prestige action (SPEC §7, §11).
## setup(payload): currently unused (reads GameState.current_venue).

const PrestigeSystem = preload("res://scripts/meta/prestige_system.gd")
const MilestoneSystem = preload("res://scripts/meta/milestone_system.gd")

# Palette (SPEC §2).
const BG := Color("#F5EFE0")
const INK := Color("#33312E")
const PANEL := Color("#FFFDF6")
const ACCENT := Color("#C4703F")
const BRASS := Color("#B08D3E")
const SAGE := Color("#7A9B76")
const SLATE := Color("#5B7B8C")
const DIM := Color("#D8CFC0")

var _list: VBoxContainer
var _confirm: ConfirmationDialog

func setup(_payload: Dictionary) -> void:
	if is_inside_tree() and _list != null:
		refresh()

func _ready() -> void:
	_build_shell()
	refresh()
	EventBus.milestone_completed.connect(func(_v, _m): refresh())
	EventBus.prestige_performed.connect(func(_f, _t): refresh())

func _build_shell() -> void:
	var bg := ColorRect.new()
	bg.color = BG
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 16)
	margin.add_theme_constant_override("margin_right", 16)
	margin.add_theme_constant_override("margin_top", 16)
	margin.add_theme_constant_override("margin_bottom", 16)
	add_child(margin)
	var scroll := ScrollContainer.new()
	scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_child(scroll)
	_list = VBoxContainer.new()
	_list.add_theme_constant_override("separation", 10)
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_list)
	_confirm = ConfirmationDialog.new()
	_confirm.dialog_text = "Prestige? Departments reset, but you keep cash, gems, insight, managers and decor — and unlock the next venue."
	_confirm.ok_button_text = "Prestige!"
	_confirm.cancel_button_text = "Not yet"
	_confirm.confirmed.connect(_on_prestige_confirmed)
	add_child(_confirm)

func _label(text: String, size: int = 15, color: Color = INK) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_color_override("font_color", color)
	l.add_theme_font_size_override("font_size", size)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return l

func _panel() -> PanelContainer:
	var p := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = PANEL
	sb.border_color = DIM
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(12)
	sb.content_margin_left = 10
	sb.content_margin_right = 10
	sb.content_margin_top = 8
	sb.content_margin_bottom = 8
	p.add_theme_stylebox_override("panel", sb)
	return p

func refresh() -> void:
	if not is_inside_tree() or _list == null:
		return
	for c in _list.get_children():
		c.queue_free()
	var vid: String = GameState.current_venue
	var venue: Dictionary = DataLoader.get_venue(vid)
	_list.add_child(_label("Prestige — %s" % str(venue.get("name", vid)), 26, INK))

	# Milestone chain (8 nodes with states).
	_list.add_child(_label("Milestones", 20, ACCENT))
	var defs: Array = DataLoader.milestones.get(vid, [])
	var done: Array = GameState.venue_state(vid).get("milestones", [])
	for i in range(defs.size()):
		var ms: Dictionary = defs[i]
		var row := _panel()
		var hb := HBoxContainer.new()
		row.add_child(hb)
		var state: String
		var state_color: Color
		if i < done.size():
			state = "DONE"
			state_color = SAGE
		elif i == done.size():
			state = "NEXT"
			state_color = ACCENT
		else:
			state = "LOCKED"
			state_color = DIM
		var name_l := _label("%d. %s" % [i + 1, str(ms.get("name", "?"))], 16,
			INK if i <= done.size() else DIM)
		name_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		hb.add_child(name_l)
		var reward: Dictionary = ms.get("reward", {})
		hb.add_child(_label("+%d gems, %s" % [int(reward.get("gems", 0)),
			str(DataLoader.get_lootbox(str(reward.get("box", ""))).get("name", reward.get("box", "")))], 13, SLATE))
		hb.add_child(_label(state, 14, state_color))
		_list.add_child(row)

	# Next venue card.
	_list.add_child(_label("Next Venue", 20, ACCENT))
	var next_id: String = PrestigeSystem.next_venue_id()
	if next_id != "":
		var nv: Dictionary = DataLoader.get_venue(next_id)
		var card := _panel()
		var cv := VBoxContainer.new()
		card.add_child(cv)
		cv.add_child(_label(str(nv.get("name", next_id)), 18, INK))
		cv.add_child(_label("%sx richer base value" % _richer_text(venue, nv), 15, BRASS))
		cv.add_child(_label(str(nv.get("desc", "")), 14, SLATE))
		_list.add_child(card)
	else:
		_list.add_child(_label("This is the final venue.", 15, SLATE))

	# Prestige button (+ reason when blocked).
	var reason: String = PrestigeSystem.block_reason()
	var btn := Button.new()
	btn.text = "PRESTIGE"
	btn.custom_minimum_size = Vector2(0, 56)
	btn.disabled = reason != ""
	btn.pressed.connect(func(): _confirm.popup_centered())
	_list.add_child(btn)
	if reason != "":
		_list.add_child(_label(reason, 14, ACCENT))

func _richer_text(cur: Dictionary, nxt: Dictionary) -> String:
	var a: float = float(cur.get("base_value_m", 1.0))
	var b: float = float(nxt.get("base_value_m", 1.0))
	var de: int = int(nxt.get("base_value_e", 0)) - int(cur.get("base_value_e", 0))
	var ratio: float = (b / maxf(a, 0.0001)) * pow(10.0, de)
	if ratio >= 100.0:
		return "%d" % int(round(ratio))
	return "%.1f" % ratio

func _on_prestige_confirmed() -> void:
	if PrestigeSystem.do_prestige():
		var nv: Dictionary = DataLoader.get_venue(GameState.current_venue)
		EventBus.toast_requested.emit("Welcome to %s!" % str(nv.get("name", GameState.current_venue)))
	else:
		EventBus.toast_requested.emit(PrestigeSystem.block_reason())
	refresh()
