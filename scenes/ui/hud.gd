extends PanelContainer
## HUD top bar — ONE dense row (IBT-style): level star with an inline progress
## bar, cash WITH its per-second rate, gems, insight.
##
## It used to be three stacked bands (currency / REP+meta / rating) plus the
## venue strip below, and the whole stack ran to ~27% of a 720x1280 phone before
## the museum began. The information density was the inverse of the footprint:
## no income rate, no store shortcut, and a full band spent on a prose sentence.
##
## What changed, and why:
##   · Level and currency share one row. The REP bar is a 10px channel inside the
##     level capsule instead of a 460px band of its own.
##   · Cash carries its rate underneath ("+1.2K/s"). In an idle game that is the
##     single most-read number and we were not showing it at all.
##   · Cash and gems ARE store buttons (the "+" badge is the affordance). The
##     whole pill is the target, so the shortcut costs no height and clears 48dp
##     by a mile — a 30px "+" glyph would not have.
##   · Rating moved to the venue strip (quests_bar) as a chip; Decor and Prestige
##     moved to the vertical side rail. Neither costs a horizontal band now.
##
## Root is a PanelContainer with an EMPTY stylebox: the bar floats over the shell
## and every element carries its own dark glass pill, so each readout keeps its
## contrast regardless of what ends up behind it.

const UI := preload("res://scripts/ui/ui_kit.gd")
const Popups := preload("res://scripts/ui/popup_manager.gd")

const STORE_PATH := "res://scenes/store/store_screen.tscn"

## One row tall. 52 holds a 26px value stacked over a 13px rate line plus the
## pill's own padding, and every tap target in the row is the full pill height.
const ROW_H := 52

var _cash_lbl: Label
var _rate_lbl: Label
var _gems_lbl: Label
var _insight_lbl: Label
var _lvl_lbl: Label
var _rep_bar: ProgressBar
var _margin: MarginContainer
var _timer: Timer

func _ready() -> void:
	UI.install_default_font()
	add_theme_stylebox_override("panel", StyleBoxEmpty.new())

	_margin = MarginContainer.new()
	_margin.add_theme_constant_override("margin_left", UI.GUTTER)
	_margin.add_theme_constant_override("margin_right", UI.GUTTER)
	_margin.add_theme_constant_override("margin_top", 8)
	_margin.add_theme_constant_override("margin_bottom", 6)
	add_child(_margin)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	_margin.add_child(row)

	row.add_child(_build_level_capsule())
	row.add_child(_build_cash_button())
	row.add_child(_build_gems_button())
	row.add_child(_build_insight_chip())

	EventBus.cash_changed.connect(_on_any_change)
	EventBus.gems_changed.connect(_on_any_change)
	EventBus.insight_changed.connect(_on_any_change)
	EventBus.reputation_changed.connect(_on_any_change)

	_timer = Timer.new()
	_timer.wait_time = 0.5
	_timer.autostart = true
	_timer.timeout.connect(refresh)
	add_child(_timer)

	get_viewport().size_changed.connect(_apply_safe_area)
	_apply_safe_area()
	refresh()

# --- Pieces --------------------------------------------------------------------

## Level star + number + the REP bar as a thin channel cut through the capsule.
## A readout, not a button: there is no "level" screen to open, and a dead tap
## target is worse than none.
func _build_level_capsule() -> PanelContainer:
	var pill := PanelContainer.new()
	pill.add_theme_stylebox_override("panel", _pill_box(ROW_H / 2))
	pill.custom_minimum_size = Vector2(152, ROW_H)
	var r := HBoxContainer.new()
	r.add_theme_constant_override("separation", 7)
	r.alignment = BoxContainer.ALIGNMENT_CENTER
	pill.add_child(r)

	r.add_child(UI.make_icon("star", 24, UI.BRASS))
	_lvl_lbl = UI.make_display_label("1", UI.TYPE_HEADING, Color.WHITE)
	_lvl_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	r.add_child(_lvl_lbl)

	_rep_bar = ProgressBar.new()
	_rep_bar.custom_minimum_size = Vector2(56, 12)
	_rep_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_rep_bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_rep_bar.max_value = 100.0
	_rep_bar.show_percentage = false
	_rep_bar.add_theme_stylebox_override("background", UI.make_channel())
	_rep_bar.add_theme_stylebox_override("fill", UI.make_bar_fill("green"))
	r.add_child(_rep_bar)
	return pill

## Cash: the widest element in the row, because it is the one being read. Value
## on top, live rate underneath, "+" badge on the right. The pill is the button.
func _build_cash_button() -> Button:
	var b := _pill_button(ROW_H / 2)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.custom_minimum_size = Vector2(176, ROW_H)
	b.pressed.connect(_on_store_pressed)

	var r := _overlay_row(b, 13)
	r.add_theme_constant_override("separation", 7)
	r.add_child(UI.make_icon("cash", 26, Color.WHITE))

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", -1)
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	r.add_child(col)

	_cash_lbl = UI.make_display_label("$0", 26, Color.WHITE)
	_cash_lbl.clip_text = true
	col.add_child(_cash_lbl)
	# The rate is the reason this row exists. Green because it is income, small
	# because it is a sub-value — the same relationship IBT draws under its cash.
	_rate_lbl = UI.make_display_label("0/s", UI.TYPE_CAPTION, UI.SAGE)
	_rate_lbl.clip_text = true
	col.add_child(_rate_lbl)

	r.add_child(_plus_badge(UI.SAGE))
	_ignore_mouse(r)
	return b

func _build_gems_button() -> Button:
	var b := _pill_button(ROW_H / 2)
	# An explicit width, because the contents are a full-rect OVERLAY: a Button
	# reports no minimum size for those, so beside an expanding cash pill this one
	# collapsed to its icon and dropped both the count and the "+".
	b.custom_minimum_size = Vector2(116, ROW_H)
	b.pressed.connect(_on_store_pressed)
	var r := _overlay_row(b, 12)
	r.add_theme_constant_override("separation", 6)
	r.add_child(UI.make_icon("gems", 22, Color.WHITE))
	_gems_lbl = UI.make_display_label("0", UI.TYPE_HEADING, Color.WHITE)
	_gems_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	r.add_child(_gems_lbl)
	r.add_child(_plus_badge(UI.PLUM))
	_ignore_mouse(r)
	return b

## Insight has no store SKU, so it stays a plain readout at the end of the row.
func _build_insight_chip() -> PanelContainer:
	var pill := PanelContainer.new()
	pill.add_theme_stylebox_override("panel", _pill_box(ROW_H / 2))
	pill.custom_minimum_size = Vector2(0, ROW_H)
	var r := HBoxContainer.new()
	r.add_theme_constant_override("separation", 6)
	r.alignment = BoxContainer.ALIGNMENT_CENTER
	pill.add_child(r)
	r.add_child(UI.make_icon("insight", 20, UI.SLATE))
	_insight_lbl = UI.make_display_label("0", UI.TYPE_HEADING, Color.WHITE)
	_insight_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	r.add_child(_insight_lbl)
	return pill

## The "+" that says "this pill opens the store". Small on purpose: it is a
## badge on a 48dp+ target, not a target of its own.
func _plus_badge(tint: Color) -> PanelContainer:
	var p := PanelContainer.new()
	p.custom_minimum_size = Vector2(26, 26)
	p.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var sb := StyleBoxFlat.new()
	sb.bg_color = tint
	sb.set_corner_radius_all(8)
	sb.set_content_margin_all(0)
	p.add_theme_stylebox_override("panel", sb)
	var l := UI.make_display_label("+", UI.TYPE_HEADING, UI.INK)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	p.add_child(l)
	return p

# --- Skinning helpers ----------------------------------------------------------

## Glass pill with the horizontal breathing room a chip needs. make_glass'
## uniform 8px content margin is right for a square tile, too tight for a row.
func _pill_box(radius: int = 20) -> StyleBoxFlat:
	var sb := UI.make_glass(radius)
	sb.content_margin_left = 12
	sb.content_margin_right = 12
	sb.content_margin_top = 4
	sb.content_margin_bottom = 5
	return sb

## A Button wearing the same glass pill as the readouts beside it. The surface is
## chrome and the icon carries the colour, so the only saturated controls on the
## world view stay the rewarded ones.
func _pill_button(radius: int) -> Button:
	var b := Button.new()
	var normal := _pill_box(radius)
	b.add_theme_stylebox_override("normal", normal)
	b.add_theme_stylebox_override("hover", normal)
	var pressed: StyleBoxFlat = normal.duplicate()
	pressed.bg_color = UI.GLASS.lerp(Color.WHITE, 0.22)
	pressed.bg_color.a = 0.95
	pressed.shadow_size = 0
	b.add_theme_stylebox_override("pressed", pressed)
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	UI.add_press_squish(b)
	return b

## Button is not a Container, so its contents are a full-rect overlay that must
## ignore the mouse or the Button never sees the tap.
func _overlay_row(b: Button, inset: int) -> HBoxContainer:
	var r := HBoxContainer.new()
	r.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	r.offset_left = inset
	r.offset_right = -inset
	r.alignment = BoxContainer.ALIGNMENT_CENTER
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(r)
	return r

func _ignore_mouse(n: Node) -> void:
	if n is Control:
		(n as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE
	for c in n.get_children():
		_ignore_mouse(c)

# --- State ---------------------------------------------------------------------

## Push the top bar clear of a notch / status bar. Re-run on rotation or resize.
func _apply_safe_area() -> void:
	if _margin == null:
		return
	var inset: Dictionary = UI.safe_area_insets(self)
	_margin.add_theme_constant_override("margin_top", 8 + int(inset["top"]))
	_margin.add_theme_constant_override("margin_left", UI.GUTTER + int(inset["left"]))
	_margin.add_theme_constant_override("margin_right", UI.GUTTER + int(inset["right"]))

func _on_any_change(_a: Variant = null, _b: Variant = null) -> void:
	refresh()

func refresh() -> void:
	_cash_lbl.text = GameState.cash.to_notation()
	_rate_lbl.text = "+%s/s" % Economy.current_cash_per_second().to_notation()
	_gems_lbl.text = "%d" % GameState.gems
	_insight_lbl.text = GameState.insight.to_notation()
	_lvl_lbl.text = "%d" % GameState.rep_level()
	_rep_bar.value = GameState.rep_progress() * 100.0

func _on_store_pressed() -> void:
	Popups.open(STORE_PATH)
