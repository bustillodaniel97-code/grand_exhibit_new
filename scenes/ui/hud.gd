extends PanelContainer
## HUD top bar (SPEC §9): Cash (big, notation), Gems, Insight, REP badge + progress bar.
## Also hosts the small Decor and Prestige meta buttons (mission item 5).
## Refreshes on EventBus signals + a 0.5s timer.
##
## Root is a PanelContainer, not a Control with a hardcoded 136px floor: the old
## fixed height was smaller than the content it held, so the REP row painted over
## the Venue Progress strip below it. A PanelContainer reports its children's
## minimum size to the parent VBox, so the bar is always exactly tall enough.
##
## The root stylebox is EMPTY on purpose. It used to be an opaque cream slab
## which, with the bottom nav, rendered a fifth of the portrait canvas as a light
## band — and since the currency chips are the same cream, they read only by
## their drop shadow (1.00:1 against their own backing). Every element now
## carries its own dark glass pill, so the bar floats over the shell and each
## readout keeps its contrast no matter what ends up behind it.

const UI := preload("res://scripts/ui/ui_kit.gd")
const Popups := preload("res://scripts/ui/popup_manager.gd")

const DECOR_PATH := "res://scenes/meta/decor_screen.tscn"
const PRESTIGE_PATH := "res://scenes/meta/prestige_screen.tscn"

var _cash_chip: PanelContainer
var _gems_chip: PanelContainer
var _insight_chip: PanelContainer
var _rep_lbl: Label
var _rep_bar: ProgressBar
var _decor_btn: Button
var _prestige_btn: Button
var _margin: MarginContainer
var _timer: Timer

func _ready() -> void:
	UI.install_default_font()
	add_theme_stylebox_override("panel", StyleBoxEmpty.new())

	_margin = MarginContainer.new()
	_margin.add_theme_constant_override("margin_left", UI.GUTTER)
	_margin.add_theme_constant_override("margin_right", UI.GUTTER)
	_margin.add_theme_constant_override("margin_top", 10)
	_margin.add_theme_constant_override("margin_bottom", 8)
	add_child(_margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	_margin.add_child(vbox)

	# Row 1: Cash big + gems + insight (currency chips with icons)
	var row1 := HBoxContainer.new()
	row1.add_theme_constant_override("separation", 10)
	vbox.add_child(row1)

	_cash_chip = _glass_chip("cash", "$0", Color.WHITE, UI.TYPE_HERO - 6)
	row1.add_child(_cash_chip)

	var spacer1 := Control.new()
	spacer1.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spacer1.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row1.add_child(spacer1)

	_gems_chip = _glass_chip("gems", "0", Color.WHITE, UI.TYPE_HEADING)
	row1.add_child(_gems_chip)

	_insight_chip = _glass_chip("insight", "0", UI.SLATE, UI.TYPE_HEADING)
	row1.add_child(_insight_chip)

	# Row 2: REP pill (badge + progress in one surface) + meta buttons.
	# The divider that used to separate the rows is gone with the slab: a rule
	# only reads as a rule when it is cutting something.
	var row2 := HBoxContainer.new()
	row2.add_theme_constant_override("separation", 10)
	vbox.add_child(row2)

	var rep_pill := PanelContainer.new()
	rep_pill.add_theme_stylebox_override("panel", _pill_box(22))
	rep_pill.custom_minimum_size = Vector2(0, UI.TOUCH_MIN - 4)
	rep_pill.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var rep_row := HBoxContainer.new()
	rep_row.add_theme_constant_override("separation", 8)
	rep_pill.add_child(rep_row)
	rep_row.add_child(UI.make_icon("star", 20, UI.BRASS))
	_rep_lbl = UI.make_display_label("REP 1", UI.TYPE_LABEL, UI.BRASS)
	_rep_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	rep_row.add_child(_rep_lbl)
	row2.add_child(rep_pill)

	# The bar lives INSIDE the pill, so an empty track is a channel cut into a
	# surface rather than a 460px void floating on the shell (which read as a
	# half-loaded element).
	_rep_bar = ProgressBar.new()
	_rep_bar.custom_minimum_size = Vector2(120, 16)
	_rep_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_rep_bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_rep_bar.max_value = 100.0
	_rep_bar.show_percentage = false
	_rep_bar.add_theme_stylebox_override("background", UI.make_channel())
	_rep_bar.add_theme_stylebox_override("fill", UI.make_bar_fill("green"))
	rep_row.add_child(_rep_bar)

	_decor_btn = UI.make_button("Decor", UI.SAGE)
	_decor_btn.custom_minimum_size = Vector2(112, UI.TOUCH_MIN)
	_decor_btn.icon = UI.icon_texture("star", 18)
	_decor_btn.pressed.connect(_on_decor_pressed)
	row2.add_child(_decor_btn)

	_prestige_btn = UI.make_button("Prestige", UI.BRASS)
	_prestige_btn.custom_minimum_size = Vector2(128, UI.TOUCH_MIN)
	_prestige_btn.icon = UI.icon_texture("trophy", 18)
	_prestige_btn.pressed.connect(_on_prestige_pressed)
	row2.add_child(_prestige_btn)

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

## Glass pill with the horizontal breathing room a chip needs. make_glass'
## uniform 8px content margin is right for a square tile, too tight for a row.
func _pill_box(radius: int = 20) -> StyleBoxFlat:
	var sb := UI.make_glass(radius)
	sb.content_margin_left = 14
	sb.content_margin_right = 14
	sb.content_margin_top = 5
	sb.content_margin_bottom = 6
	return sb

## Currency chip restyled for a floating bar: dark surface, white value. No text
## halo — the pill is the guarantee (white on it measures 18:1), and an outline
## costs a draw call per label for contrast the surface already provides.
func _glass_chip(icon_name: String, value: String, tint: Color, font_size: int) -> PanelContainer:
	var chip := UI.make_currency_chip(icon_name, value, tint, font_size)
	chip.add_theme_stylebox_override("panel", _pill_box())
	var l: Label = UI.chip_value_label(chip)
	l.add_theme_color_override("font_color", Color.WHITE)
	return chip

## Push the top bar clear of a notch / status bar. Re-run on rotation or resize.
func _apply_safe_area() -> void:
	if _margin == null:
		return
	var inset: Dictionary = UI.safe_area_insets(self)
	_margin.add_theme_constant_override("margin_top", 10 + int(inset["top"]))
	_margin.add_theme_constant_override("margin_left", UI.GUTTER + int(inset["left"]))
	_margin.add_theme_constant_override("margin_right", UI.GUTTER + int(inset["right"]))

func _on_any_change(_a: Variant = null, _b: Variant = null) -> void:
	refresh()

func refresh() -> void:
	UI.set_chip_value(_cash_chip, GameState.cash.to_notation())  # coin icon = cash
	UI.set_chip_value(_gems_chip, "%d" % GameState.gems)
	UI.set_chip_value(_insight_chip, GameState.insight.to_notation())
	_rep_lbl.text = "REP %d" % GameState.rep_level()
	_rep_bar.value = GameState.rep_progress() * 100.0
	var milestones_done: int = GameState.venue_state(GameState.current_venue).get("milestones", []).size()
	_prestige_btn.visible = GameState.feature_unlocked("prestige") or milestones_done >= 8

func _on_decor_pressed() -> void:
	if GameState.feature_unlocked("decor"):
		Popups.open(DECOR_PATH)
	else:
		var req: int = int(DataLoader.core.get("unlocks", {}).get("decor_rep", 2))
		EventBus.toast_requested.emit("Unlocks at Rep %d" % req)

func _on_prestige_pressed() -> void:
	Popups.open(PRESTIGE_PATH)
