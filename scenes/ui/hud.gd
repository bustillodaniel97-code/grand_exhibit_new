extends Control
## HUD top bar (SPEC §9): Cash (big, notation), Gems, Insight, REP badge + progress bar.
## Also hosts the small Decor and Prestige meta buttons (mission item 5).
## Refreshes on EventBus signals + a 0.5s timer.

const UI := preload("res://scripts/ui/ui_kit.gd")
const Popups := preload("res://scripts/ui/popup_manager.gd")

const DECOR_PATH := "res://scenes/meta/decor_screen.tscn"
const PRESTIGE_PATH := "res://scenes/meta/prestige_screen.tscn"

var _cash_lbl: Label
var _gems_lbl: Label
var _insight_lbl: Label
var _rep_lbl: Label
var _rep_bar: ProgressBar
var _decor_btn: Button
var _prestige_btn: Button
var _timer: Timer

func _ready() -> void:
	custom_minimum_size = Vector2(0, 136)

	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	panel.add_theme_stylebox_override("panel", UI.make_panel(UI.PANEL, 0, 0))
	add_child(panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 16)
	margin.add_theme_constant_override("margin_right", 16)
	margin.add_theme_constant_override("margin_top", 8)
	margin.add_theme_constant_override("margin_bottom", 8)
	panel.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)
	margin.add_child(vbox)

	# Row 1: Cash big + gems + insight
	var row1 := HBoxContainer.new()
	row1.add_theme_constant_override("separation", 18)
	vbox.add_child(row1)

	_cash_lbl = UI.make_label("$0", 42)
	row1.add_child(_cash_lbl)

	var spacer1 := Control.new()
	spacer1.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row1.add_child(spacer1)

	_gems_lbl = UI.make_label("GEMS 0", 24)
	_gems_lbl.add_theme_color_override("font_color", UI.BRASS)
	row1.add_child(_gems_lbl)

	_insight_lbl = UI.make_label("INSIGHT 0", 24)
	_insight_lbl.add_theme_color_override("font_color", UI.SLATE)
	row1.add_child(_insight_lbl)

	# Row 2: REP badge + progress bar + meta buttons
	var row2 := HBoxContainer.new()
	row2.add_theme_constant_override("separation", 12)
	vbox.add_child(row2)

	var rep_badge := PanelContainer.new()
	rep_badge.add_theme_stylebox_override("panel", UI.make_panel(UI.BRASS, 8, 0))
	_rep_lbl = UI.make_label("REP 1", 20)
	_rep_lbl.add_theme_color_override("font_color", Color.WHITE)
	rep_badge.add_child(_rep_lbl)
	row2.add_child(rep_badge)

	_rep_bar = ProgressBar.new()
	_rep_bar.custom_minimum_size = Vector2(200, 26)
	_rep_bar.max_value = 100.0
	_rep_bar.show_percentage = false
	_rep_bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_rep_bar.add_theme_stylebox_override("background", UI.make_panel(UI.BG.darkened(0.08), 8, 0))
	_rep_bar.add_theme_stylebox_override("fill", UI.make_panel(UI.SAGE, 8, 0))
	row2.add_child(_rep_bar)

	var spacer2 := Control.new()
	spacer2.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row2.add_child(spacer2)

	_decor_btn = UI.make_button("Decor", UI.SAGE)
	_decor_btn.custom_minimum_size = Vector2(110, 44)
	_decor_btn.pressed.connect(_on_decor_pressed)
	row2.add_child(_decor_btn)

	_prestige_btn = UI.make_button("Prestige", UI.BRASS)
	_prestige_btn.custom_minimum_size = Vector2(130, 44)
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

	refresh()

func _on_any_change(_a: Variant = null, _b: Variant = null) -> void:
	refresh()

func refresh() -> void:
	_cash_lbl.text = "$" + GameState.cash.to_notation()
	_gems_lbl.text = "GEMS %d" % GameState.gems
	_insight_lbl.text = "INSIGHT " + GameState.insight.to_notation()
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
