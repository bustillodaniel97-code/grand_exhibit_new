extends Control
## QuestsBar — compact venue meta widget: progress bar, 8 milestone pips, and the
## 3 objective chips. Embedded by venue-ui above the venue scroll (SPEC §11 note).
## Refreshes on EventBus signals and drives QuestSystem.evaluate on stat signals.
##
## The chips are real Buttons. They used to be raised cream cards that looked
## exactly like buttons and did nothing at all — tapping one changed zero pixels.
## Each now presses, routes to whatever screen or room can advance it, and shows
## an icon tile, 15px copy (13px was under the mobile legibility floor) and a
## filled progress channel carrying the fraction, so "what do I do next" is
## readable from arm's length instead of being two lines of fine print.

const QuestSystem = preload("res://scripts/meta/quest_system.gd")
const MilestoneSystem = preload("res://scripts/meta/milestone_system.gd")
const UI = preload("res://scripts/ui/ui_kit.gd")
const Popups = preload("res://scripts/ui/popup_manager.gd")

# Palette aliases (ui_kit is the single source — SPEC §2).
const PANEL := UI.PANEL
const BRASS := UI.BRASS
const SAGE := UI.SAGE
## Unearned milestone pip. A light alpha on the pill it sits in, not a dark tint
## of the shell — the old #5A4E86 fill measured 2.00:1 and read as an artefact.
const DIM := Color(1, 1, 1, 0.42)

const MILESTONE_COUNT := 8
const CHIP_COUNT := 3
const CHIP_HEIGHT := 84   # well over the 48dp floor: the whole chip is the target

const PATH_MANAGERS := "res://scenes/managers/managers_screen.tscn"
const PATH_DECOR := "res://scenes/meta/decor_screen.tscn"

## Objective type -> (icon, tile colour). Departments keep their own hue so an
## upgrade objective points at the room it belongs to without reading its label.
const TYPE_ICONS := {
	"upgrade_count": "arrow_up",
	"earn_total": "cash",
	"serve_total": "home",
	"buy_decor": "gems",
	"own_managers": "medal",
}
const TYPE_TINTS := {
	"earn_total": UI.BRASS,
	"serve_total": UI.SAGE,
	"buy_decor": UI.PLUM,
	"own_managers": UI.SLATE,
}
## The coin and gem art ship pre-coloured, so they lose on a tile of their own
## hue (a gold coin on gold is a 1.5:1 smudge). Those tiles invert: deep fill,
## saturated rim, bright artwork.
const PRECOLORED_ICONS := ["cash", "gems"]

var _bar: ProgressBar
var _pct_label: Label
var _pips: Array = []
var _chips: Array = []  # Array of {btn, tile, icon, desc, bar, frac, quest_id, skin}

func _ready() -> void:
	custom_minimum_size = Vector2(0, 158)
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
	margin.add_theme_constant_override("margin_top", 4)
	margin.add_theme_constant_override("margin_bottom", 6)
	add_child(margin)
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 5)
	margin.add_child(vbox)

	# The venue-progress header rides in its own glass pill. Bare light text and a
	# faint track drawn straight onto the shell vanish the moment something bright
	# is behind them, and this strip sits directly over the museum floor.
	var header_pill := PanelContainer.new()
	header_pill.add_theme_stylebox_override("panel", UI.make_glass(14))
	vbox.add_child(header_pill)
	var header_col := VBoxContainer.new()
	header_col.add_theme_constant_override("separation", 4)
	header_pill.add_child(header_col)

	# Row 1: title + milestone pips + percent. The pips share this row instead of
	# owning one of their own: the strip is competing with the museum for height.
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 8)
	header_col.add_child(top)
	var title := UI.make_display_label("Venue Progress", UI.TYPE_LABEL, UI.PANEL)
	top.add_child(title)

	var pip_row := HBoxContainer.new()
	pip_row.add_theme_constant_override("separation", 4)
	pip_row.alignment = BoxContainer.ALIGNMENT_CENTER
	pip_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(pip_row)
	for i in range(MILESTONE_COUNT):
		# Empty pips are an OUTLINE star, not a dark fill. A filled star tinted
		# down to the shell sat at 2.00:1 and read as a rendering artefact.
		var pip := UI.make_icon("star_outline", 16, DIM)
		pip.tooltip_text = "Milestone %d" % (i + 1)
		pip_row.add_child(pip)
		_pips.append(pip)

	_pct_label = UI.make_display_label("", UI.TYPE_LABEL, UI.BRASS)
	top.add_child(_pct_label)

	# Row 2: progress bar.
	_bar = ProgressBar.new()
	_bar.min_value = 0.0
	_bar.max_value = 1.0
	_bar.step = 0.001
	_bar.show_percentage = false
	_bar.custom_minimum_size = Vector2(0, 14)
	_bar.add_theme_stylebox_override("background", UI.make_channel())
	_bar.add_theme_stylebox_override("fill", UI.make_bar_fill("green"))
	header_col.add_child(_bar)

	# Row 3: the objective chips.
	var chip_row := HBoxContainer.new()
	chip_row.add_theme_constant_override("separation", 8)
	chip_row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(chip_row)
	for i in range(CHIP_COUNT):
		chip_row.add_child(_build_chip(i))

## One objective chip: a Button wearing a glass pill, with an icon tile, wrapped
## copy and a fraction-carrying progress channel laid over it.
func _build_chip(index: int) -> Button:
	var btn := Button.new()
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	btn.custom_minimum_size = Vector2(0, CHIP_HEIGHT)
	btn.add_theme_stylebox_override("normal", UI.make_glass(16))
	btn.add_theme_stylebox_override("hover", UI.make_glass(16, 0.92, Color(1, 1, 1, 0.28)))
	btn.add_theme_stylebox_override("pressed", UI.make_glass(16, 0.96, Color(1, 1, 1, 0.34)))
	btn.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	UI.add_press_squish(btn)
	btn.pressed.connect(_on_chip_pressed.bind(index))

	# Button lays out no children of its own, so the content is a full-rect
	# overlay. Everything inside must ignore the mouse or the Button never sees
	# the tap that is the whole point of this rebuild.
	var pad := MarginContainer.new()
	pad.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	pad.add_theme_constant_override("margin_left", 9)
	pad.add_theme_constant_override("margin_right", 9)
	pad.add_theme_constant_override("margin_top", 8)
	pad.add_theme_constant_override("margin_bottom", 8)
	btn.add_child(pad)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 5)
	pad.add_child(col)

	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 7)
	head.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(head)

	var tile := PanelContainer.new()
	tile.custom_minimum_size = Vector2(34, 34)
	tile.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	tile.add_theme_stylebox_override("panel", _tile_box(UI.SLATE))
	var tile_icon := UI.make_icon("question", 24, Color.WHITE)
	tile.add_child(tile_icon)
	head.add_child(tile)

	var desc := UI.make_label("", UI.TYPE_LABEL)
	desc.add_theme_color_override("font_color", Color.WHITE)
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	# Two lines is what the chip is tall enough to hold. The content is an overlay
	# on a Button, which reports no minimum size for it, so a third line would
	# push the progress channel out through the bottom of the pill.
	desc.max_lines_visible = 2
	desc.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	desc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	desc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	head.add_child(desc)

	var prog := ProgressBar.new()
	prog.min_value = 0.0
	prog.max_value = 1.0
	prog.step = 0.001
	prog.show_percentage = false
	prog.custom_minimum_size = Vector2(0, 19)
	prog.add_theme_stylebox_override("background", UI.make_channel())
	prog.add_theme_stylebox_override("fill", UI.make_bar_fill("blue"))
	col.add_child(prog)

	# The fraction rides ON the channel: at three chips across a 720 canvas there
	# is no width to spare for a column beside it.
	var frac := UI.make_display_label("", UI.TYPE_CAPTION, Color.WHITE)
	frac.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	frac.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	frac.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	UI.add_text_halo(frac, Color(0, 0, 0, 0.6), 3)
	prog.add_child(frac)

	_ignore_mouse(pad)
	_chips.append({
		"btn": btn, "tile": tile, "icon": tile_icon, "desc": desc,
		"bar": prog, "frac": frac, "quest_id": "", "skin": "",
	})
	return btn

func _tile_box(tint: Color, inverted: bool = false) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = tint.darkened(0.62) if inverted else tint
	sb.set_corner_radius_all(10)
	sb.set_content_margin_all(5)
	if inverted:
		sb.set_border_width_all(2)
		sb.border_color = tint
	return sb

func _ignore_mouse(n: Node) -> void:
	if n is Control:
		(n as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE
	for c in n.get_children():
		_ignore_mouse(c)

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
		var earned: bool = i < done_count
		_pips[i].texture = UI.icon_texture("star" if earned else "star_outline", 16)
		_pips[i].modulate = BRASS if earned else DIM
	var active: Array = vs.get("active_quests", [])
	for i in range(_chips.size()):
		if i < active.size() and DataLoader.quests.has(str(active[i])):
			_paint_chip(_chips[i], vid, str(active[i]))
		else:
			_paint_done(_chips[i])

func _paint_chip(chip: Dictionary, vid: String, qid: String) -> void:
	var qdef: Dictionary = DataLoader.quests[qid]
	chip["quest_id"] = qid
	(chip["btn"] as Button).visible = true
	(chip["desc"] as Label).text = str(qdef.get("desc", qid))
	var qtype: String = str(qdef.get("type", ""))
	var cur: BigNumber = QuestSystem.current_value(vid, qdef)
	var tgt: BigNumber = QuestSystem.target_value(qdef)
	if cur.gt(tgt):
		cur = tgt
	var complete: bool = cur.gte(tgt)
	var icon_name: String = "check" if complete else str(TYPE_ICONS.get(qtype, "question"))
	var tint: Color = SAGE if complete else _tile_tint(qdef, qtype)
	_set_skin(chip, icon_name, tint, "green" if complete else "blue")
	(chip["bar"] as ProgressBar).value = _ratio(cur, tgt)
	(chip["frac"] as Label).text = "Done!" if complete else "%s / %s" % [
		cur.to_notation(), tgt.to_notation()]

func _paint_done(chip: Dictionary) -> void:
	chip["quest_id"] = ""
	(chip["desc"] as Label).text = "All objectives cleared"
	_set_skin(chip, "check", SAGE, "green")
	(chip["bar"] as ProgressBar).value = 1.0
	(chip["frac"] as Label).text = ""

## Icon, tile and fill colour, applied only when they actually change. refresh()
## runs off cash_banked, which fires twice a second forever; rebuilding six
## styleboxes on every one of those was pure allocation churn.
func _set_skin(chip: Dictionary, icon_name: String, tint: Color, fill: String) -> void:
	var key := "%s|%s|%s" % [icon_name, tint.to_html(false), fill]
	if str(chip.get("skin", "")) == key:
		return
	chip["skin"] = key
	(chip["icon"] as TextureRect).texture = UI.icon_texture(icon_name, 24)
	(chip["tile"] as PanelContainer).add_theme_stylebox_override("panel",
		_tile_box(tint, icon_name in PRECOLORED_ICONS))
	(chip["bar"] as ProgressBar).add_theme_stylebox_override("fill", UI.make_bar_fill(fill))

func _tile_tint(qdef: Dictionary, qtype: String) -> Color:
	if qtype == "upgrade_count":
		return UI.DEPT_COLORS.get(str(qdef.get("dept", "")), UI.SLATE)
	return TYPE_TINTS.get(qtype, UI.SLATE)

## Fraction of target. Divides in BigNumber space first: the raw values are
## routinely past float range by mid-game, so cur/tgt as floats is not safe.
func _ratio(cur: BigNumber, tgt: BigNumber) -> float:
	if tgt.is_zero():
		return 1.0
	if cur.gte(tgt):
		return 1.0
	return clampf(cur.div(tgt).to_float_approx(), 0.0, 1.0)

# --- Tap routing ---------------------------------------------------------------

## An objective chip is a shortcut to the thing that advances it: the room's
## upgrade sheet, or the screen that owns the currency it wants. Where no screen
## can advance it (earn/serve totals just accrue), it says so out loud rather
## than swallowing the tap.
func _on_chip_pressed(index: int) -> void:
	if index >= _chips.size():
		return
	var qid: String = str(_chips[index].get("quest_id", ""))
	if qid == "" or not DataLoader.quests.has(qid):
		EventBus.toast_requested.emit("Every objective here is done — prestige when you are ready")
		return
	var qdef: Dictionary = DataLoader.quests[qid]
	match str(qdef.get("type", "")):
		"upgrade_count":
			_open_dept(str(qdef.get("dept", "")))
		"own_managers":
			if GameState.feature_unlocked("managers"):
				Popups.open(PATH_MANAGERS)
			else:
				EventBus.toast_requested.emit(str(qdef.get("desc", "")))
		"buy_decor":
			if GameState.feature_unlocked("decor"):
				Popups.open(PATH_DECOR)
			else:
				EventBus.toast_requested.emit(str(qdef.get("desc", "")))
		_:
			EventBus.toast_requested.emit("%s — keep the museum running" % str(qdef.get("desc", "")))

## Ask the floor to select the room, which is what a tap on that room does. The
## floor's dept_selected is the public, already-wired route: VenueView owns the
## upgrade sheet and this widget must not reach into it.
func _open_dept(dept_id: String) -> void:
	var dept_name: String = str(DataLoader.dept_def(dept_id).get("name", dept_id.capitalize()))
	var floor_node: Node = get_tree().root.find_child("VenueFloor", true, false)
	if floor_node != null and floor_node.has_signal("dept_selected"):
		floor_node.dept_selected.emit(dept_id)
	else:
		EventBus.toast_requested.emit("Tap %s on the floor to upgrade it" % dept_name)
