extends Control
## QuestsBar — compact venue meta widget (~180px): progress bar, 8 milestone pips,
## 3 quest chips. Embedded by venue-ui above the venue scroll (SPEC §11 note).
## Refreshes on EventBus signals and drives QuestSystem.evaluate on stat signals.

const QuestSystem = preload("res://scripts/meta/quest_system.gd")
const MilestoneSystem = preload("res://scripts/meta/milestone_system.gd")
const UI = preload("res://scripts/ui/ui_kit.gd")

# Palette aliases (ui_kit is the single source — SPEC §2).
const BG := UI.BG
const INK := UI.INK
const PANEL := UI.PANEL
const ACCENT := UI.ACCENT
const BRASS := UI.BRASS
const SAGE := UI.SAGE
const DIM := Color("#D8CFC0")

const MILESTONE_COUNT := 8

var _bar: ProgressBar
var _pct_label: Label
var _pips: Array = []
var _chips: Array = []  # Array of {desc: Label, prog: Label}

func _ready() -> void:
	custom_minimum_size = Vector2(0, 180)
	_build_ui()
	_connect_signals()
	QuestSystem.ensure_active_quests(GameState.current_venue)
	QuestSystem.evaluate(GameState.current_venue)
	refresh()

func _build_ui() -> void:
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 10)
	margin.add_theme_constant_override("margin_right", 10)
	margin.add_theme_constant_override("margin_top", 6)
	margin.add_theme_constant_override("margin_bottom", 6)
	add_child(margin)
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 4)
	margin.add_child(vbox)

	# Row 1: title + percent.
	var top := HBoxContainer.new()
	vbox.add_child(top)
	var title := UI.make_display_label("Venue Progress", 16, INK)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(title)
	_pct_label = Label.new()
	_pct_label.add_theme_color_override("font_color", ACCENT)
	_pct_label.add_theme_font_size_override("font_size", 16)
	top.add_child(_pct_label)

	# Row 2: progress bar.
	_bar = ProgressBar.new()
	_bar.min_value = 0.0
	_bar.max_value = 1.0
	_bar.step = 0.001
	_bar.show_percentage = false
	_bar.custom_minimum_size = Vector2(0, 18)
	_bar.add_theme_stylebox_override("background", UI.make_bar_bg())
	_bar.add_theme_stylebox_override("fill", UI.make_bar_fill("green"))
	vbox.add_child(_bar)

	# Row 3: milestone pips (star icons: brass earned / dim empty).
	var pip_row := HBoxContainer.new()
	pip_row.add_theme_constant_override("separation", 6)
	pip_row.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_child(pip_row)
	for i in range(MILESTONE_COUNT):
		var pip := UI.make_icon("star", 18, DIM)
		pip.tooltip_text = "Milestone %d" % (i + 1)
		pip_row.add_child(pip)
		_pips.append(pip)

	# Row 4: 3 quest chips.
	var chip_row := HBoxContainer.new()
	chip_row.add_theme_constant_override("separation", 8)
	chip_row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(chip_row)
	for i in range(3):
		var chip := PanelContainer.new()
		chip.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		chip.add_theme_stylebox_override("panel",
			UI.make_frame(Color(1, 1, 1).lerp(BRASS, 0.12)))
		var cv := VBoxContainer.new()
		cv.add_theme_constant_override("separation", 2)
		chip.add_child(cv)
		var desc := Label.new()
		desc.add_theme_color_override("font_color", INK)
		desc.add_theme_font_size_override("font_size", 13)
		desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		desc.max_lines_visible = 2
		desc.size_flags_vertical = Control.SIZE_EXPAND_FILL
		cv.add_child(desc)
		var prog := Label.new()
		prog.add_theme_color_override("font_color", ACCENT)
		prog.add_theme_font_size_override("font_size", 13)
		cv.add_child(prog)
		chip_row.add_child(chip)
		_chips.append({"desc": desc, "prog": prog})

func _connect_signals() -> void:
	# Refresh-only signals.
	EventBus.venue_progress_changed.connect(func(_v, _p): refresh())
	EventBus.quest_completed.connect(func(_q): refresh())
	EventBus.milestone_completed.connect(func(_v, _m): refresh())
	EventBus.prestige_available.connect(func(_v): refresh())
	EventBus.prestige_performed.connect(func(_f, _t): refresh())
	# Stat signals: evaluate quests for the current venue, then refresh.
	EventBus.department_upgraded.connect(func(_v, _d, _t, _l): _evaluate_current())
	EventBus.cash_banked.connect(func(_a): _evaluate_current())
	EventBus.decor_purchased.connect(func(_v, _d): _evaluate_current())
	EventBus.manager_obtained.connect(func(_m, _c): _evaluate_current())

func _evaluate_current() -> void:
	QuestSystem.evaluate(GameState.current_venue)
	refresh()

func refresh() -> void:
	if not is_inside_tree():
		return
	var vid: String = GameState.current_venue
	QuestSystem.ensure_active_quests(vid)
	var vs: Dictionary = GameState.venue_state(vid)
	var progress: float = clampf(float(vs.get("progress", 0.0)), 0.0, 1.0)
	_bar.value = progress
	_pct_label.text = "%d%%" % int(round(progress * 100.0))
	var done_count: int = vs.get("milestones", []).size()
	for i in range(_pips.size()):
		_pips[i].modulate = BRASS if i < done_count else DIM
	var active: Array = vs.get("active_quests", [])
	for i in range(_chips.size()):
		var desc: Label = _chips[i]["desc"]
		var prog: Label = _chips[i]["prog"]
		if i < active.size() and DataLoader.quests.has(str(active[i])):
			var qdef: Dictionary = DataLoader.quests[str(active[i])]
			desc.text = str(qdef.get("desc", active[i]))
			var cur: BigNumber = QuestSystem.current_value(vid, qdef)
			var tgt: BigNumber = QuestSystem.target_value(qdef)
			if cur.gt(tgt):
				cur = tgt
			prog.text = "%s / %s" % [cur.to_notation(), tgt.to_notation()]
		else:
			desc.text = "All quests done!"
			prog.text = ""
