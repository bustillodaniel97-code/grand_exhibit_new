extends Control
## Daily Gifts: the week's seven gifts as toy cards. Gifts already opened this
## week are ticked, today's glows with a Claim button, later ones wait.

const UI := preload("res://scripts/ui/ui_kit.gd")
const Chrome := preload("res://scripts/ui/museum_chrome.gd")
const Juice := preload("res://scripts/ui/juice.gd")
const DailyGifts := preload("res://scripts/meta/daily_gifts.gd")

var _grid: GridContainer
var _claim: Button
var _note: Label

func setup(_payload: Dictionary) -> void:
	pass

func _ready() -> void:
	name = "DailyGiftsScreen"
	var bg := ColorRect.new()
	bg.color = Chrome.BG
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_%s" % side, 18)
	add_child(margin)
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 12)
	margin.add_child(body)
	body.add_child(UI.make_display_label("Daily Gifts", 30, Chrome.INK))
	body.add_child(_label("A gift every day. Miss a day and your next gift simply waits for you.", 15, Chrome.DIM))
	_grid = GridContainer.new()
	_grid.name = "Days"
	_grid.columns = 3
	_grid.add_theme_constant_override("h_separation", 10)
	_grid.add_theme_constant_override("v_separation", 10)
	body.add_child(_grid)
	_claim = Button.new()
	_claim.name = "ClaimGift"
	_claim.custom_minimum_size = Vector2(0, 64)
	_claim.add_theme_font_override("font", UI.font())
	_claim.add_theme_font_size_override("font_size", 22)
	_claim.pressed.connect(_on_claim)
	body.add_child(_claim)
	_note = _label("", 15, Chrome.TEAL)
	_note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	body.add_child(_note)
	_build()

func _build() -> void:
	for c in _grid.get_children():
		c.queue_free()
	var today := DailyGifts.day_index()
	var open := DailyGifts.available()
	var gifts := DailyGifts.days()
	for i in gifts.size():
		var state := "done" if i < today else ("today" if i == today and open else "later")
		if i == today and not open:
			state = "next"
		_grid.add_child(_card(i, gifts[i], state))
	if open:
		_claim.text = "Claim Day %d gift" % (today + 1)
		Chrome.button(_claim, true, 16)
		_note.text = ""
	else:
		_claim.text = "Come back tomorrow"
		Chrome.button(_claim, false, 16)
		_note.text = "Gifts claimed: %d" % DailyGifts.total()

func _card(i: int, gift: Dictionary, state: String) -> Control:
	var card := PanelContainer.new()
	card.name = "Day%d" % (i + 1)
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.custom_minimum_size = Vector2(0, 150)
	var sb := Chrome.panel(16, Chrome.RAISED if state == "today" else Chrome.PANEL)
	sb.set_content_margin_all(8)
	if state == "today":
		sb.border_color = Chrome.ACTION
		sb.set_border_width_all(4)
	elif i == DailyGifts.days().size() - 1:
		sb.border_color = Color("#E8B83A")
		sb.set_border_width_all(3)
	card.add_theme_stylebox_override("panel", sb)
	var col := VBoxContainer.new()
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_theme_constant_override("separation", 4)
	card.add_child(col)
	var day := UI.make_display_label("Day %d" % (i + 1), 17, Chrome.BRASS if state != "done" else Chrome.DIM)
	day.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(day)
	var icon := TextureRect.new()
	icon.texture = UI.icon_texture("check" if state == "done" else _icon_for(gift), 40)
	icon.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
	icon.custom_minimum_size = Vector2(0, 44)
	# The glyph icons are white masks; tint them so they read on a light card.
	var tints := {"trophy": Color("#E8A21A"), "arrow_up": Chrome.ACTION, "star": Chrome.BRASS}
	icon.modulate = Chrome.TEAL if state == "done" else tints.get(_icon_for(gift), Color.WHITE)
	col.add_child(icon)
	var what := _label(DailyGifts.describe(gift), 14, Chrome.INK if state != "done" else Chrome.DIM)
	what.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(what)
	if state == "next":
		var tomorrow := _label("Tomorrow", 13, Chrome.TEAL)
		tomorrow.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		col.add_child(tomorrow)
	card.modulate = Color(1, 1, 1, 0.65) if state == "done" else Color.WHITE
	return card

func _icon_for(gift: Dictionary) -> String:
	if gift.has("cards_box"):
		return "trophy"
	if gift.has("gems"):
		return "gems"
	if gift.has("cash_minutes"):
		return "cash"
	if gift.has("boost_hours"):
		return "arrow_up"
	return "star"

func _on_claim() -> void:
	if not DailyGifts.available():
		EventBus.toast_requested.emit("Your next gift is ready tomorrow")
		return
	var got := DailyGifts.claim()
	var from := _claim.get_global_rect().get_center()
	if got.has("gems"):
		Juice.coin_burst(from, "gems", 7)
	if got.has("cash"):
		Juice.coin_burst(from, "cash", 9)
	EventBus.toast_requested.emit("Day %d gift: %s" % [int(got.get("day", 1)), DailyGifts.describe(DailyGifts.days()[int(got.get("day", 1)) - 1])])
	UI.play_sfx(self, "buy")
	_build()

func _label(text: String, size_px: int, color: Color) -> Label:
	var l := UI.make_label(text, size_px)
	l.add_theme_color_override("font_color", color)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return l
