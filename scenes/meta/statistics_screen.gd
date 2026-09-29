extends Control
## One truthful view of the whole venue flow. IBT uses this screen to teach
## balancing; ours also distinguishes a physical limiter from an actionable
## upgrade so a capped room is never presented as a broken task.

const UI := preload("res://scripts/ui/ui_kit.gd")
const Chrome := preload("res://scripts/ui/museum_chrome.gd")
const Popups := preload("res://scripts/ui/popup_manager.gd")
const ManagerSystem := preload("res://scripts/managers/manager_system.gd")
const MANAGERS_PATH := "res://scenes/managers/managers_screen.tscn"

var _body: VBoxContainer
var _scroll: ScrollContainer
var _venue_label: Label
var _timer: Timer
var _last_snapshot: String = ""

func _ready() -> void:
	var bg := ColorRect.new()
	bg.color = Chrome.BG
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_%s" % side, 20)
	add_child(margin)
	var root_box := VBoxContainer.new()
	root_box.add_theme_constant_override("separation", 14)
	margin.add_child(root_box)
	var heading := VBoxContainer.new()
	heading.add_theme_constant_override("separation", 4)
	root_box.add_child(heading)
	heading.add_child(UI.make_display_label("Museum overview", 30, Chrome.INK))
	_venue_label = _label("", 17, Chrome.BRASS)
	heading.add_child(_venue_label)
	var scroll := ScrollContainer.new()
	_scroll = scroll
	scroll.name = "StatisticsScroll"
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root_box.add_child(scroll)
	_body = VBoxContainer.new()
	_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_body.add_theme_constant_override("separation", 14)
	scroll.add_child(_body)
	_timer = Timer.new()
	_timer.wait_time = 1.0
	_timer.autostart = true
	_timer.timeout.connect(refresh)
	add_child(_timer)
	refresh()

func refresh() -> void:
	if _body == null:
		return
	var vid: String = GameState.current_venue
	var venue: Dictionary = DataLoader.get_venue(vid)
	var rates: Dictionary = Economy.venue_rates(vid)
	var guide: Dictionary = Economy.flow_guidance(vid)
	var snapshot := _snapshot_key(vid, rates, guide)
	if snapshot == _last_snapshot:
		return
	_last_snapshot = snapshot
	# Rebuild only when one of the displayed values changes. Recreating the
	# entire scroll every second reset the reader's position and allocated a
	# fresh tree even while the venue was idle.
	var scroll_position := _scroll.scroll_vertical
	for child in _body.get_children():
		_body.remove_child(child)
		child.queue_free()
	_venue_label.text = str(venue.get("name", vid))
	_body.add_child(_guidance_card(guide))
	_body.add_child(_earnings_card(rates))
	_body.add_child(_flow_card(rates))
	_body.add_child(_management_card())
	_body.add_child(_rating_card(rates))
	# Apply after the replacement cards have queued their layout. Removing the
	# old cards immediately also avoids a frame of doubled content height.
	_scroll.set_deferred("scroll_vertical", scroll_position)

func _snapshot_key(vid: String, rates: Dictionary, guide: Dictionary) -> String:
	var parts: Array[String] = [
		vid,
		str(guide.get("title", "")),
		str(guide.get("detail", "")),
		str(guide.get("actionable", false)),
		str(guide.get("ready_to_move", false)),
		str(guide.get("dept", "")),
		str(GameState.feature_unlocked("managers")),
		"%.4f" % float(rates.get("arrival_per_s", 0.0)),
		"%.4f" % float(rates.get("serve_per_s", 0.0)),
		"%.4f" % float(rates.get("transport_per_s", 0.0)),
		str(rates.get("actual_choke_id", "")),
		(rates.get("value_per_visitor", BigNumber.zero()) as BigNumber).to_notation(),
		(rates.get("pending_per_s", BigNumber.zero()) as BigNumber).to_notation(),
		(rates.get("banked_per_s", BigNumber.zero()) as BigNumber).to_notation(),
	]
	var sat: Dictionary = rates.get("satisfaction", {})
	parts.append("%.3f" % float(sat.get("stars", 0.0)))
	parts.append("%.3f" % float(sat.get("income_mult", 1.0)))
	parts.append(str(sat.get("reason", "")))
	for dept in ManagerSystem.DEPTS:
		parts.append("%s:%.4f:%d" % [
			dept, Economy.manager_multiplier_for(dept),
			ManagerSystem.assignment_slots(dept)])
		for id in ManagerSystem.assigned_ids(dept):
			parts.append("%s:%d:%d" % [
				id, ManagerSystem.level(id), ManagerSystem.rank(id)])
	return "|".join(parts)

func _guidance_card(guide: Dictionary) -> Control:
	var ready := bool(guide.get("ready_to_move", false))
	var card := _card(true)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 9)
	card.add_child(box)
	box.add_child(UI.make_display_label("READY FOR YOUR NEXT MUSEUM" if ready else "NEXT IMPROVEMENT", 12, Chrome.BRASS))
	box.add_child(_label(str(guide.get("title", "Flow")), 23, Chrome.INK))
	box.add_child(_label(str(guide.get("detail", "")), 17, Chrome.DIM))
	if bool(guide.get("actionable", false)):
		var dept: String = str(guide.get("dept", ""))
		var btn := _button("Improve %s" % _dept_display_name(dept), true)
		btn.pressed.connect(func() -> void:
			Popups.close_top()
			EventBus.department_requested.emit(dept))
		box.add_child(btn)
	elif ready:
		box.add_child(_label("Use the trophy button to open the next museum.", 17, Chrome.TEAL))
	return card

func _flow_card(rates: Dictionary) -> Control:
	var card := _card()
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 14)
	card.add_child(box)
	box.add_child(UI.make_display_label("Visitor flow", 22, Chrome.INK))
	box.add_child(_label("Capacity per second · your slowest step sets the pace", 15, Chrome.DIM))
	var values := {
		"promotions": float(rates.get("arrival_per_s", 0.0)),
		"ticket": float(rates.get("serve_per_s", 0.0)),
		"archive": float(rates.get("transport_per_s", 0.0)),
	}
	var peak: float = maxf(maxf(float(values["promotions"]), float(values["ticket"])),
		maxf(float(values["archive"]), 0.001))
	for dept in ["promotions", "ticket", "archive"]:
		box.add_child(_rate_row(dept, float(values[dept]), peak,
			str(rates.get("actual_choke_id", "")) == dept))
	return card

func _management_card() -> Control:
	var card := _card()
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	card.add_child(box)
	box.add_child(UI.make_display_label("Management", 22, Chrome.INK))
	for dept in ManagerSystem.DEPTS:
		var assigned := ManagerSystem.assigned_ids(dept)
		var slots := ManagerSystem.assignment_slots(dept)
		var mult := Economy.manager_multiplier_for(dept)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 12)
		var title := _label(DataLoader.venue_dept_name(
			GameState.current_venue, dept), 17, Chrome.DIM)
		title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(title)
		var coverage := "%d/%d posts" % [assigned.size(), slots]
		var benefit := "x%.2f" % mult if mult > 1.0001 else "No boost"
		row.add_child(_nowrap_label("%s  ·  %s" % [coverage, benefit], 16,
			Chrome.TEAL if mult > 1.0001 else Chrome.DIM, 178.0))
		box.add_child(row)
	var open := _button(
		"Manage staff" if GameState.feature_unlocked("managers")
		else "Staff unlock at Rep %d" % int(
			DataLoader.core.get("unlocks", {}).get("managers_rep", 3)))
	open.pressed.connect(func() -> void:
		if GameState.feature_unlocked("managers"):
			Popups.open(MANAGERS_PATH)
		else:
			EventBus.toast_requested.emit("Managers unlock at Rep %d" % int(
				DataLoader.core.get("unlocks", {}).get("managers_rep", 3))))
	box.add_child(open)
	return card

func _rate_row(dept: String, value: float, peak: float, physical_limit: bool) -> Control:
	var row := VBoxContainer.new()
	row.add_theme_constant_override("separation", 7)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 10)
	row.add_child(head)
	# The venue names its own rooms — "Harbor Cafe", not "Promotions". Reading
	# them from DataLoader keeps Statistics agreeing with the floor and the
	# department sheet; a local table here silently reverted every venue to the
	# generic labels the moment Tidewater renamed its arrivals hall.
	var title := _label(_dept_display_name(dept), 17,
		Chrome.BRASS if physical_limit else Chrome.INK)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	head.add_child(_nowrap_label("%.2f/s%s" % [
		value, " · LIMIT" if physical_limit else ""], 16,
		Chrome.BRASS if physical_limit else Chrome.DIM, 140.0))
	var bar := ProgressBar.new()
	bar.max_value = peak
	bar.value = value
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(0, 9)
	bar.add_theme_stylebox_override("background", Chrome.channel(Chrome.BG))
	bar.add_theme_stylebox_override("fill", Chrome.channel(Chrome.BRASS if physical_limit else Chrome.TEAL))
	row.add_child(bar)
	return row

func _earnings_card(rates: Dictionary) -> Control:
	var card := _card()
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	card.add_child(box)
	box.add_child(_label("BANKED INCOME", 12, Chrome.TEAL))
	box.add_child(UI.make_display_label("$%s / sec" % (rates["banked_per_s"] as BigNumber).to_notation(), 32, Chrome.INK))
	var rule := Panel.new()
	rule.custom_minimum_size.y = 1
	rule.add_theme_stylebox_override("panel", Chrome.channel(Chrome.BORDER))
	box.add_child(rule)
	box.add_child(_stat("Per visitor", "$%s" % (rates["value_per_visitor"] as BigNumber).to_notation()))
	box.add_child(_stat("Produced", "$%s/s" % (rates["pending_per_s"] as BigNumber).to_notation()))
	return card

func _rating_card(rates: Dictionary) -> Control:
	var sat: Dictionary = rates.get("satisfaction", {})
	var card := _card()
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	card.add_child(box)
	box.add_child(UI.make_display_label("Visitor experience", 22, Chrome.INK))
	box.add_child(_stat("Rating", "%.1f / 5" % float(sat.get("stars", 0.0))))
	box.add_child(_stat("Deposit multiplier", "x%.2f" % float(sat.get("income_mult", 1.0))))
	box.add_child(_label(str(sat.get("reason", "")), 17, Chrome.DIM))
	return card

func _stat(name_text: String, value_text: String) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	var name_label := _label(name_text, 17, Chrome.DIM)
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(name_label)
	row.add_child(_nowrap_label(value_text, 18, Chrome.INK, 150.0))
	return row

func _card(emphasized: bool = false) -> PanelContainer:
	var card := PanelContainer.new()
	var surface := Chrome.panel(16, Chrome.RAISED if emphasized else Chrome.PANEL)
	surface.set_content_margin_all(16)
	if emphasized:
		surface.border_color = Chrome.TEAL.darkened(0.25)
	card.add_theme_stylebox_override("panel", surface)
	return card

func _button(text: String, primary: bool = false) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size.y = 52
	button.add_theme_font_override("font", UI.font())
	button.add_theme_font_size_override("font_size", 18)
	button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	Chrome.button(button, primary)
	return button

func _label(text: String, size: int, color: Color) -> Label:
	var label := UI.make_label(text, size)
	label.add_theme_color_override("font_color", color)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return label

## Numeric/stat values live on the trailing edge of HBox rows. Giving those the
## paragraph helper's autowrap lets the expanding label beside them squeeze them
## to one glyph wide, producing a vertical column and a card hundreds of pixels
## tall. They are deliberately compact single-line reads.
func _nowrap_label(text: String, size: int, color: Color,
		min_width: float = 150.0) -> Label:
	var label := UI.make_label(text, size)
	label.add_theme_color_override("font_color", color)
	label.autowrap_mode = TextServer.AUTOWRAP_OFF
	label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	label.custom_minimum_size.x = min_width
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	label.size_flags_horizontal = Control.SIZE_SHRINK_END
	return label

## Player-facing name for a department in the venue on screen. Falls back to the
## shared role label, never to a hardcoded per-venue string.
func _dept_display_name(dept: String) -> String:
	var authored: String = DataLoader.venue_dept_name(GameState.current_venue, dept)
	if authored != "":
		return authored
	return dept.capitalize()
