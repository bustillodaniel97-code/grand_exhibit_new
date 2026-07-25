extends PanelContainer
## HUD top bar (SPEC §9): Cash (big, notation), Gems, Insight, REP badge + progress bar.
## Also hosts the small Decor and Prestige meta buttons (mission item 5).
## Refreshes on EventBus signals + a 0.5s timer.
##
## Root is a PanelContainer, not a Control with a hardcoded 136px floor: the old
## fixed height was smaller than the content it held, so the REP row painted over
## the Venue Progress strip below it. A PanelContainer reports its children's
## minimum size to the parent VBox, so the bar is always exactly tall enough.

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
	add_theme_stylebox_override("panel", UI.make_panel(UI.PANEL, 0, 0))

	_margin = MarginContainer.new()
	_margin.add_theme_constant_override("margin_left", UI.GUTTER)
	_margin.add_theme_constant_override("margin_right", UI.GUTTER)
	_margin.add_theme_constant_override("margin_top", 10)
	_margin.add_theme_constant_override("margin_bottom", 10)
	add_child(_margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	_margin.add_child(vbox)

	# Row 1: Cash big + gems + insight (currency chips with icons)
	var row1 := HBoxContainer.new()
	row1.add_theme_constant_override("separation", 10)
	vbox.add_child(row1)

	_cash_chip = UI.make_currency_chip("cash", "$0", Color.WHITE, UI.TYPE_HERO - 6)
	row1.add_child(_cash_chip)

	var spacer1 := Control.new()
	spacer1.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row1.add_child(spacer1)

	_gems_chip = UI.make_currency_chip("gems", "0", Color.WHITE, UI.TYPE_HEADING)
	row1.add_child(_gems_chip)

	_insight_chip = UI.make_currency_chip("insight", "0", UI.SLATE, UI.TYPE_HEADING)
	row1.add_child(_insight_chip)

	vbox.add_child(UI.make_divider())

	# Row 2: REP badge + progress bar + meta buttons
	var row2 := HBoxContainer.new()
	row2.add_theme_constant_override("separation", 10)
	vbox.add_child(row2)

	var rep_badge := PanelContainer.new()
	rep_badge.add_theme_stylebox_override("panel", UI.make_panel(UI.BRASS, 10, 0))
	rep_badge.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var rep_row := HBoxContainer.new()
	rep_row.add_theme_constant_override("separation", 6)
	rep_row.alignment = BoxContainer.ALIGNMENT_CENTER
	rep_badge.add_child(rep_row)
	rep_row.add_child(UI.make_icon("star", 18, Color.WHITE))
	_rep_lbl = UI.make_display_label("REP 1", UI.TYPE_LABEL, Color.WHITE)
	rep_row.add_child(_rep_lbl)
	row2.add_child(rep_badge)

	_rep_bar = ProgressBar.new()
	_rep_bar.custom_minimum_size = Vector2(120, 20)
	_rep_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_rep_bar.max_value = 100.0
	_rep_bar.show_percentage = false
	_rep_bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_rep_bar.add_theme_stylebox_override("background", UI.make_bar_bg())
	_rep_bar.add_theme_stylebox_override("fill", UI.make_bar_fill("green"))
	row2.add_child(_rep_bar)

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
