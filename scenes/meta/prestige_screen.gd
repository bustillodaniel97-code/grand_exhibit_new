extends Control
## MoveOnScreen (file: prestige_screen.gd) — the one-way graduation to the next
## museum (SPEC §7, §11). setup(payload): unused; reads GameState.current_venue.
##
## The file and scene keep the prestige_screen name because the HUD entry point
## and the integration playthrough reference the path, and neither is this
## track's file. Nothing the player reads says "prestige".
##
## THE JOB OF THIS SCREEN is to sell an irreversible step. So it is laid out as
## an offer, not as a confirmation: what the new place is worth, what you carry
## through the door, what you leave bolted to the floor. The keep/leave lists are
## rendered from PrestigeSystem.carry_over() / left_behind(), which is also where
## the behaviour is decided — copy and code cannot drift apart.
##
## The action bar is PINNED below the scroll so the button is always under a
## thumb, and it is NEVER disabled: a disabled button eats the tap and explains
## nothing. When the gate is not met it is dressed dead, wears a lock, and a tap
## toasts exactly how many milestones remain.

const PrestigeSystem = preload("res://scripts/meta/prestige_system.gd")
const MilestoneSystem = preload("res://scripts/meta/milestone_system.gd")
const UI = preload("res://scripts/ui/ui_kit.gd")

# Palette aliases (ui_kit is the single source — SPEC §2).
# Popup CONTENT on a DARK page. DIM is the muted ink for locked / empty states.
const BG := UI.PAGE
const INK := UI.TEXT
const PANEL := UI.CARD
const ACCENT := UI.ACCENT
const BRASS := UI.BRASS
const SAGE := UI.SAGE
const SLATE := UI.SLATE
const DANGER := UI.DANGER
const DIM := UI.TEXT_MUTE

var _list: VBoxContainer
var _action_bar: VBoxContainer
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
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	margin.add_child(vbox)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(scroll)
	_list = VBoxContainer.new()
	_list.add_theme_constant_override("separation", 10)
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_list)
	_action_bar = VBoxContainer.new()
	_action_bar.add_theme_constant_override("separation", 6)
	vbox.add_child(_action_bar)
	_confirm = ConfirmationDialog.new()
	_confirm.ok_button_text = "Open it"
	_confirm.cancel_button_text = "Not yet"
	_confirm.confirmed.connect(_on_move_confirmed)
	add_child(_confirm)

# ------------------------------------------------------------------- builders

func _label(text: String, size: int = 15, color: Color = INK) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_color_override("font_color", color)
	l.add_theme_font_size_override("font_size", size)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return l

func _panel(tint: Color = PANEL) -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", UI.make_dark_card(tint))
	return p

func _section(title: String, color: Color) -> void:
	_list.add_child(UI.make_display_label(title, 20, color))

## One {icon,label,detail} row of the keep / leave lists. Icons draw at their own
## colour: these are solid Kenney glyphs, and tinting a coin green turns it into
## an unreadable blob. The keep/leave semantics ride on the LABEL colour instead.
func _fact_row(fact: Dictionary, tint: Color) -> Control:
	var row := _panel()
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 10)
	row.add_child(hb)
	hb.add_child(UI.make_icon(str(fact.get("icon", "star")), 22))
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 1)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hb.add_child(col)
	col.add_child(_label(str(fact.get("label", "")), 16, tint))
	col.add_child(_label(str(fact.get("detail", "")), 13, DIM))
	return row

# -------------------------------------------------------------------- refresh

func refresh() -> void:
	if not is_inside_tree() or _list == null:
		return
	for c in _list.get_children():
		c.queue_free()
	for c in _action_bar.get_children():
		c.queue_free()
	var vid: String = GameState.current_venue
	var venue: Dictionary = DataLoader.get_venue(vid)
	var preview: Dictionary = PrestigeSystem.next_venue_preview()

	_list.add_child(UI.make_display_label("Move On", 26, INK))
	_list.add_child(_label("Curator of %s — museum %d of %d" % [str(venue.get("name", vid)),
		int(venue.get("order", 1)), DataLoader.venue_order().size()], 14, DIM))

	_build_gate_card(vid)
	if preview.is_empty():
		_build_final_card()
	else:
		_build_next_card(preview)
		_build_keep_leave()
	_build_milestone_chain(vid)
	_build_action_bar(preview)

## The gate, stated as a count and a bar rather than a sentence — the player
## should be able to read "how far off am I" without parsing prose.
func _build_gate_card(vid: String) -> void:
	var done: int = PrestigeSystem.milestones_done(vid)
	var need: int = PrestigeSystem.milestones_required(vid)
	var ready: bool = PrestigeSystem.gate_met(vid)
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel",
		UI.make_dark_frame(SAGE if ready else ACCENT))
	var cv := VBoxContainer.new()
	cv.add_theme_constant_override("separation", 6)
	card.add_child(cv)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 8)
	cv.add_child(head)
	head.add_child(UI.make_icon("trophy" if ready else "lock", 22, SAGE if ready else ACCENT))
	var head_l := _label("Milestones %d / %d" % [done, need], 18, INK)
	head_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(head_l)
	# No wrap: beside an expand-fill title this label gets one glyph of width and
	# spells itself down the card, which is what stretched it to half a screen.
	var state_l := _label("READY" if ready else "IN PROGRESS", 13, SAGE if ready else ACCENT)
	state_l.autowrap_mode = TextServer.AUTOWRAP_OFF
	head.add_child(state_l)
	var bar := ProgressBar.new()
	bar.min_value = 0.0
	bar.max_value = 1.0
	bar.value = clampf(float(done) / maxf(float(need), 1.0), 0.0, 1.0)
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(0, 16)
	bar.add_theme_stylebox_override("background", UI.make_bar_bg())
	bar.add_theme_stylebox_override("fill", UI.make_bar_fill("green" if ready else "yellow"))
	cv.add_child(bar)
	if ready:
		cv.add_child(_label("The chain is complete. The next museum will take you.", 13, DIM))
	else:
		var nxt: Dictionary = MilestoneSystem.next_milestone(vid)
		cv.add_child(_label("Next: %s" % str(nxt.get("name", "—")), 13, DIM))
	_list.add_child(card)

func _build_next_card(preview: Dictionary) -> void:
	_section("The next museum", BRASS)
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", UI.make_dark_frame(BRASS))
	var cv := VBoxContainer.new()
	cv.add_theme_constant_override("separation", 6)
	card.add_child(cv)
	cv.add_child(UI.make_display_label(str(preview["name"]), 20, INK))
	cv.add_child(_label(str(preview["desc"]), 14, DIM))
	cv.add_child(UI.make_divider())
	# Both sides of the deal on one card. The cost line is not hidden: the owner's
	# model is that difficulty scales, and a player who is surprised by it at the
	# first upgrade will read the whole step as a punishment.
	cv.add_child(_stat_row("cash", "Visitors pay",
		"%s more per head" % PrestigeSystem.ratio_text(float(preview["value_ratio"])), SAGE))
	cv.add_child(_stat_row("arrow_up", "Upgrades cost",
		"%s more — a bigger hall is a harder job" % PrestigeSystem.ratio_text(float(preview["cost_ratio"])),
		ACCENT))
	var slots: int = int(preview["decor_slots"])
	var delta: int = int(preview["decor_slots_delta"])
	var slot_text: String = "%d empty slots" % slots
	if delta > 0:
		slot_text += " (%d more than here)" % delta
	cv.add_child(_stat_row("star", "Decor", slot_text, BRASS))
	_list.add_child(card)

func _stat_row(icon: String, label: String, detail: String, tint: Color) -> Control:
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 8)
	hb.add_child(UI.make_icon(icon, 20))
	var name_l := _label(label, 15, DIM)
	name_l.custom_minimum_size = Vector2(120, 0)
	name_l.autowrap_mode = TextServer.AUTOWRAP_OFF
	hb.add_child(name_l)
	var val_l := _label(detail, 15, tint)
	val_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hb.add_child(val_l)
	return hb

func _build_keep_leave() -> void:
	_section("You take this with you", SAGE)
	for fact in PrestigeSystem.carry_over():
		_list.add_child(_fact_row(fact, SAGE))
	_section("This stays behind", DANGER)
	for fact in PrestigeSystem.left_behind():
		_list.add_child(_fact_row(fact, DANGER))

func _build_final_card() -> void:
	_section("The end of the road", BRASS)
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", UI.make_dark_frame(BRASS))
	var cv := VBoxContainer.new()
	card.add_child(cv)
	cv.add_child(_label("There is no bigger museum. This one is yours to perfect.", 15, INK))
	_list.add_child(card)

func _build_milestone_chain(vid: String) -> void:
	_section("Milestones", ACCENT)
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

## Pinned bar. The button stays live in every state (see header) — a locked step
## still has to answer "why not yet?" when the player taps it.
func _build_action_bar(preview: Dictionary) -> void:
	var reason: String = PrestigeSystem.block_reason()
	var ready: bool = reason == ""
	var final_venue: bool = preview.is_empty()
	var label: String = "FINAL MUSEUM"
	if not final_venue:
		label = "OPEN %s" % str(preview.get("name", "")).to_upper()
	var btn := UI.make_button(label, BRASS if ready else UI.DEAD)
	btn.icon = UI.icon_texture("arrow_right" if ready else "lock", 22)
	btn.custom_minimum_size = Vector2(0, 64)
	# Live buttons keep the kit's white-with-dark-outline face, which is what
	# holds up on gold. Only the dead state is repainted, to recede on the page.
	if not ready:
		btn.add_theme_color_override("font_color", DIM)
	btn.pressed.connect(_on_action_pressed)
	_action_bar.add_child(btn)
	if ready:
		_action_bar.add_child(_label("One way. There is no coming back to %s." %
			str(DataLoader.get_venue(GameState.current_venue).get("name", "")), 13, DIM))
	else:
		_action_bar.add_child(_label(reason, 13, ACCENT))

# --------------------------------------------------------------------- actions

func _on_action_pressed() -> void:
	var reason: String = PrestigeSystem.block_reason()
	if reason != "":
		EventBus.toast_requested.emit(reason)
		UI.play_sfx(self, "click")
		return
	var preview: Dictionary = PrestigeSystem.next_venue_preview()
	var here: String = str(DataLoader.get_venue(GameState.current_venue).get("name", ""))
	_confirm.dialog_text = ("Open %s?\n\nYou keep every coin, gem, manager and reputation "
		+ "level you have earned. %s and everything installed in it stays shut behind you.") % [
		str(preview.get("name", "")), here]
	_confirm.popup_centered()

func _on_move_confirmed() -> void:
	if PrestigeSystem.graduate():
		var nv: Dictionary = DataLoader.get_venue(GameState.current_venue)
		EventBus.toast_requested.emit("Welcome to %s!" % str(nv.get("name", GameState.current_venue)))
		UI.play_sfx(self, "buy")
	else:
		EventBus.toast_requested.emit(PrestigeSystem.block_reason())
	refresh()
