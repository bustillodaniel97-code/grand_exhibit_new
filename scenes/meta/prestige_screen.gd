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
const Chrome = preload("res://scripts/ui/museum_chrome.gd")
const Popups = preload("res://scripts/ui/popup_manager.gd")

# Palette aliases (ui_kit is the single source — SPEC §2).
# Popup CONTENT on a DARK page. DIM is the muted ink for locked / empty states.
const BG := Chrome.BG
const INK := Chrome.INK
const PANEL := Chrome.PANEL
const ACCENT := Chrome.TEAL
const BRASS := Chrome.BRASS
const SAGE := Chrome.TEAL
const SLATE := Color("96c8df")
const DANGER := Chrome.DANGER
const DIM := Chrome.DIM

var _list: VBoxContainer
var _action_bar: VBoxContainer
var _confirm: ConfirmationDialog
var _celebrate_on_open: bool = false

func setup(payload: Dictionary) -> void:
	_celebrate_on_open = bool(payload.get("celebrate", false))
	if is_inside_tree() and _list != null:
		refresh()

func _ready() -> void:
	_build_shell()
	refresh()
	if _celebrate_on_open or PrestigeSystem.gate_met(GameState.current_venue):
		call_deferred("_play_celebration")
	EventBus.milestone_completed.connect(func(_v, _m): refresh())
	EventBus.decor_purchased.connect(func(_v, _d): refresh())
	EventBus.department_upgraded.connect(func(_v, _d, _t, _l): refresh())
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
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
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
	_confirm.title = "Open your next museum?"
	_confirm.dialog_autowrap = true
	var dialog_theme := ThemeDB.get_default_theme().duplicate() as Theme
	var surface := Chrome.panel(12, Chrome.BG)
	surface.set_content_margin_all(18)
	dialog_theme.set_stylebox("panel", "AcceptDialog", surface)
	var border := Chrome.panel(12, Chrome.PANEL)
	border.content_margin_top = 34
	border.expand_margin_top = 34
	dialog_theme.set_stylebox("embedded_border", "Window", border)
	dialog_theme.set_stylebox("embedded_unfocused_border", "Window", border)
	dialog_theme.set_color("title_color", "Window", INK)
	_confirm.theme = dialog_theme
	_confirm.ok_button_text = "Open museum"
	_confirm.cancel_button_text = "Not yet"
	_confirm.confirmed.connect(_on_move_confirmed)
	add_child(_confirm)
	_confirm.get_label().add_theme_font_size_override("font_size", 19)
	_confirm.get_label().add_theme_color_override("font_color", INK)
	for button in [_confirm.get_ok_button(), _confirm.get_cancel_button()]:
		button.add_theme_font_size_override("font_size", 18)
		Chrome.button(button, button == _confirm.get_ok_button())
		# AcceptDialog resets button custom minima while laying out its native row.
		# Give the actual button styles enough padding to retain a touch-size face.
		for state in ["normal", "hover", "pressed", "focus"]:
			var button_style := button.get_theme_stylebox(state).duplicate() as StyleBoxFlat
			button_style.content_margin_top = 16
			button_style.content_margin_bottom = 16
			button.add_theme_stylebox_override(state, button_style)
		button.custom_minimum_size = Vector2(148, 54)

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
	p.add_theme_stylebox_override("panel", Chrome.panel(16, tint))
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
		_list.remove_child(c)
		c.queue_free()
	for c in _action_bar.get_children():
		_action_bar.remove_child(c)
		c.queue_free()
	var vid: String = GameState.current_venue
	var venue: Dictionary = DataLoader.get_venue(vid)
	var preview: Dictionary = PrestigeSystem.next_venue_preview()

	var complete := PrestigeSystem.gate_met(vid)
	_list.add_child(UI.make_display_label(
		"Museum complete" if complete else "Venues", 30,
		BRASS if complete else INK))
	_list.add_child(_label(
		(("%s has completed its milestones and core operation. The collection is yours to perfect." if preview.is_empty() else
		"%s has completed its milestones and core operation. Your next chapter is ready.") % str(venue.get("name", vid)))
		if complete else
		"Curator of %s — level %d of %d" % [str(venue.get("name", vid)),
			int(venue.get("order", 1)), DataLoader.venue_order().size()],
		15, SAGE if complete else DIM))

	_list.add_child(_venue_preview(venue))
	if not complete:
		_build_gate_card(vid)
	if preview.is_empty():
		_build_final_card()
	else:
		_build_next_card(preview)
		_build_keep_leave()
	_build_milestone_chain(vid)
	_build_collection(vid)
	_build_action_bar(preview)

## The gate, stated as a count and a bar rather than a sentence — the player
## should be able to read "how far off am I" without parsing prose.
func _build_gate_card(vid: String) -> void:
	var done: int = PrestigeSystem.milestones_done(vid)
	var need: int = PrestigeSystem.milestones_required(vid)
	var ready: bool = PrestigeSystem.gate_met(vid)
	var milestone_ready: bool = PrestigeSystem.milestone_gate_met(vid)
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel",
		Chrome.panel(16))
	var cv := VBoxContainer.new()
	cv.add_theme_constant_override("separation", 6)
	card.add_child(cv)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 8)
	cv.add_child(head)
	head.add_child(UI.make_icon("trophy" if ready else "lock", 22, SAGE if ready else ACCENT))
	var head_l := _label("Venue readiness", 18, INK)
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
	bar.add_theme_stylebox_override("background", Chrome.channel(Chrome.BG))
	bar.add_theme_stylebox_override("fill", Chrome.channel(SAGE if milestone_ready else BRASS))
	cv.add_child(bar)
	cv.add_child(_label("Milestones %d / %d" % [done, need], 13, DIM))
	var operations := ProgressBar.new()
	operations.min_value = 0.0
	operations.max_value = 1.0
	operations.value = PrestigeSystem.operations_progress(vid)
	operations.show_percentage = false
	operations.custom_minimum_size = Vector2(0, 16)
	operations.add_theme_stylebox_override("background", Chrome.channel(Chrome.BG))
	operations.add_theme_stylebox_override("fill",
		Chrome.channel(SAGE if PrestigeSystem.operations_met(vid) else BRASS))
	cv.add_child(operations)
	cv.add_child(_label("Core operation %d%%" % int(round(operations.value * 100.0)), 13, DIM))
	var furnishing := ProgressBar.new()
	furnishing.max_value = 1.0
	furnishing.value = PrestigeSystem.decor_progress(vid)
	furnishing.show_percentage = false
	furnishing.custom_minimum_size = Vector2(0, 16)
	furnishing.add_theme_stylebox_override("background", Chrome.channel(Chrome.BG))
	furnishing.add_theme_stylebox_override("fill", Chrome.channel(SAGE if PrestigeSystem.decor_met(vid) else BRASS))
	cv.add_child(furnishing)
	cv.add_child(_label(PrestigeSystem.decor_summary(vid), 13, DIM))
	var furnish := UI.make_button("Furnish museum", SAGE)
	furnish.pressed.connect(func() -> void:
		Popups.close_top()
		Popups.open("res://scenes/meta/decor_screen.tscn", {"venue_id": vid}))
	cv.add_child(furnish)
	if ready:
		cv.add_child(_label("The operation is complete. The next museum awaits.", 13, DIM))
	elif milestone_ready:
		cv.add_child(_label(PrestigeSystem.block_reason(), 13, DIM))
	else:
		var nxt: Dictionary = MilestoneSystem.next_milestone(vid)
		cv.add_child(_label("Next: %s" % str(nxt.get("name", "—")), 13, DIM))
	_list.add_child(card)

func _build_next_card(preview: Dictionary) -> void:
	_section("Your next museum", BRASS)
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", Chrome.panel(16))
	var cv := VBoxContainer.new()
	cv.add_theme_constant_override("separation", 6)
	card.add_child(cv)
	cv.add_child(_venue_preview(preview))
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

func _play_celebration() -> void:
	if not is_inside_tree():
		return
	UI.play_sfx(self, "buy")
	var colors := [BRASS, SAGE, UI.PLUM, UI.SLATE, Color.WHITE]
	for i in 28:
		var bit := ColorRect.new()
		bit.color = colors[i % colors.size()]
		bit.mouse_filter = Control.MOUSE_FILTER_IGNORE
		bit.size = Vector2(5 + (i % 3) * 3, 10 + (i % 4) * 2)
		bit.position = Vector2(
			18.0 + fmod(float(i * 83), maxf(size.x - 36.0, 40.0)),
			-18.0 - float((i * 29) % 130))
		bit.rotation = float(i) * 0.37
		bit.z_index = 20
		add_child(bit)
		var tw := bit.create_tween()
		tw.set_parallel(true)
		tw.tween_property(bit, "position:y", size.y + 30.0,
			1.15 + float(i % 7) * 0.08).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		tw.tween_property(bit, "rotation", bit.rotation + PI * 2.0,
			1.15 + float(i % 7) * 0.08)
		tw.chain().tween_callback(bit.queue_free)

## Static previews are rendered from each real venue, never from a player save.
## Keeping the aspect ratio avoids cropping upper floors out of the image.
func _venue_preview(venue: Dictionary, compact: bool = false) -> Control:
	var id := str(venue.get("id", ""))
	var frame := VBoxContainer.new()
	frame.add_theme_constant_override("separation", 7)
	var image := TextureRect.new()
	image.name = "VenueArtwork_" + id
	image.custom_minimum_size = Vector2(0, 172 if compact else 310)
	image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	image.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	image.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var path := "res://art/venue_previews/%s.png" % id
	if ResourceLoader.exists(path):
		image.texture = load(path)
	frame.add_child(image)
	var caption := _label("%02d  %s" % [int(venue.get("order", 1)), str(venue.get("name", "Museum"))], 16 if compact else 21, INK)
	frame.add_child(caption)
	if not compact:
		frame.add_child(_label("Venue preview · developed museum", 12, DIM))
	return frame

func _build_collection(current_id: String) -> void:
	var toggle := UI.make_button("Explore all 12 museums", Chrome.PANEL)
	toggle.custom_minimum_size.y = 52
	toggle.toggle_mode = true
	Chrome.button(toggle)
	_list.add_child(toggle)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 10)
	grid.visible = false
	_list.add_child(grid)
	toggle.toggled.connect(func(open: bool):
		grid.visible = open
		toggle.text = "Close museum collection" if open else "Explore all 12 museums"
		if open:
			_populate_collection(grid, current_id)
		else:
			for child in grid.get_children():
				grid.remove_child(child)
				child.queue_free())

func _populate_collection(grid: GridContainer, current_id: String) -> void:
	var current_order := int(DataLoader.get_venue(current_id).get("order", 1))
	for id in DataLoader.venue_order():
		var venue := DataLoader.get_venue(id)
		var card := _panel()
		card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var col := VBoxContainer.new()
		card.add_child(col)
		col.add_child(_venue_preview(venue, true))
		var order := int(venue.get("order", 1))
		var state := "CURRENT MUSEUM" if id == current_id else ("CHAPTER COMPLETE" if order < current_order else "UPCOMING CHAPTER")
		col.add_child(_label(state, 12, SAGE if id == current_id else DIM))
		grid.add_child(card)

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
	card.add_theme_stylebox_override("panel", Chrome.panel(16))
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
		var name_l := _label("%d. %s" % [i + 1, str(ms.get("name", "?")).replace(" (PRESTIGE)", "")], 16,
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
		label = "OPEN LEVEL %d — %s" % [
			int(preview.get("order", 0)), str(preview.get("name", "")).to_upper()]
	var btn := UI.make_button(label, BRASS if ready else UI.DEAD)
	btn.icon = UI.icon_texture("arrow_right" if ready else "lock", 22)
	btn.custom_minimum_size = Vector2(0, 64)
	Chrome.button(btn, ready)
	btn.add_theme_font_size_override("font_size", 18)
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
	var viewport_size := get_viewport_rect().size
	_confirm.popup_centered(Vector2i(mini(600, int(viewport_size.x) - 48), 280))

func _on_move_confirmed() -> void:
	if PrestigeSystem.graduate():
		var nv: Dictionary = DataLoader.get_venue(GameState.current_venue)
		EventBus.toast_requested.emit("Welcome to %s!" % str(nv.get("name", GameState.current_venue)))
		UI.play_sfx(self, "buy")
		# Keep this completed screen over the world for one render frame while
		# VenueFloor replaces the old plan, props, cast and navigation. Closing it
		# immediately exposed the intermediate half-rebuilt attraction state.
		await get_tree().process_frame
		Popups.close_top()
	else:
		EventBus.toast_requested.emit(PrestigeSystem.block_reason())
	refresh()
