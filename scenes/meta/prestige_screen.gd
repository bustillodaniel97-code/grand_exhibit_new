extends Control
## PrestigeScreen — milestone chain summary + prestige action (SPEC §7, §11).
## setup(payload): currently unused (reads GameState.current_venue).

const PrestigeSystem = preload("res://scripts/meta/prestige_system.gd")
const MilestoneSystem = preload("res://scripts/meta/milestone_system.gd")
const UI = preload("res://scripts/ui/ui_kit.gd")

# Palette aliases (ui_kit is the single source — SPEC §2).
# Popup CONTENT on a DARK page. DIM is the muted ink for locked / empty states;
# it used to be a pale beige, which on this page would out-shout the live rows.
const BG := UI.PAGE
const INK := UI.TEXT
const PANEL := UI.CARD
const ACCENT := UI.ACCENT
const BRASS := UI.BRASS
const SAGE := UI.SAGE
const SLATE := UI.SLATE
const DIM := UI.TEXT_MUTE

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
	p.add_theme_stylebox_override("panel", UI.make_dark_card(PANEL))
	return p

func refresh() -> void:
	if not is_inside_tree() or _list == null:
		return
	for c in _list.get_children():
		c.queue_free()
	var vid: String = GameState.current_venue
	var venue: Dictionary = DataLoader.get_venue(vid)
	_list.add_child(UI.make_display_label("Prestige — %s" % str(venue.get("name", vid)), 26, INK))

	# Milestone chain (8 nodes with states).
	_list.add_child(UI.make_display_label("Milestones", 20, ACCENT))
	var defs: Array = DataLoader.milestones.get(vid, [])
	var done: Array = GameState.venue_state(vid).get("milestones", [])
	for i in range(defs.size()):
		var ms: Dictionary = defs[i]
		var row := _panel()
		var hb := HBoxContainer.new()
		row.add_child(hb)
		var state: String
		var state_color: Color
		var state_icon: String
		if i < done.size():
			state = "DONE"
			state_color = SAGE
			state_icon = "check"
		elif i == done.size():
			state = "NEXT"
			state_color = ACCENT
			state_icon = "star"
		else:
			state = "LOCKED"
			state_color = DIM
			state_icon = "lock"
		hb.add_child(UI.make_icon(state_icon, 20, state_color))
		var name_l := _label("%d. %s" % [i + 1, str(ms.get("name", "?"))], 16,
			INK if i <= done.size() else DIM)
		name_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		hb.add_child(name_l)
		var reward: Dictionary = ms.get("reward", {})
		var reward_l := _label("+%d gems, %s" % [int(reward.get("gems", 0)),
			str(DataLoader.get_lootbox(str(reward.get("box", ""))).get("name", reward.get("box", "")))], 13, SLATE)
		reward_l.autowrap_mode = TextServer.AUTOWRAP_OFF  # squeezed by expand-fill name otherwise
		hb.add_child(reward_l)
		var state_l := _label(state, 14, state_color)
		state_l.autowrap_mode = TextServer.AUTOWRAP_OFF
		hb.add_child(state_l)
		_list.add_child(row)

	# Next venue card.
	_list.add_child(UI.make_display_label("Next Venue", 20, ACCENT))
	var next_id: String = PrestigeSystem.next_venue_id()
	if next_id != "":
		var nv: Dictionary = DataLoader.get_venue(next_id)
		var card := PanelContainer.new()
		card.add_theme_stylebox_override("panel", UI.make_dark_frame(BRASS))
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
	var btn := UI.make_button("PRESTIGE", BRASS)
	btn.icon = UI.icon_texture("trophy", 22)
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
		UI.play_sfx(self, "buy")
	else:
		EventBus.toast_requested.emit(PrestigeSystem.block_reason())
	refresh()
