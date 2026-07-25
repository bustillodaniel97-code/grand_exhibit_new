extends Control
## QuestsBar — the venue strip: rating chip + segmented venue-progress bar on one
## 48dp row, then the three objective chips.
##
## This used to be three bands (rating sentence in the HUD, "Venue Progress"
## title + 8 star pips + fat bar, then 84px chips). The rework, IBT-style:
##
##   · The milestone pips ARE the bar. A thin 8-segment channel where each
##     segment is one milestone — gold once earned, green while filling — says
##     everything the separate pip row said, in a strip 12px tall with no title.
##   · Rating collapsed from a prose sentence to a chip (stars + value + income
##     multiplier). The full breakdown already lives in the decor screen, which
##     is where the chip taps through to, so the HUD only needs the state.
##   · Objective chips lost 20px of padding they were not using.
##
## The chips are real Buttons: each presses, routes to whatever screen or room
## can advance it, and shows an icon tile, 15px copy (13px is under the mobile
## legibility floor) and a filled channel carrying the fraction.

const QuestSystem = preload("res://scripts/meta/quest_system.gd")
const MilestoneSystem = preload("res://scripts/meta/milestone_system.gd")
const UI = preload("res://scripts/ui/ui_kit.gd")
const Popups = preload("res://scripts/ui/popup_manager.gd")

# Palette aliases (ui_kit is the single source — SPEC §2).
const BRASS := UI.BRASS
const SAGE := UI.SAGE

const MILESTONE_COUNT := 8
const CHIP_COUNT := 3
## 84 -> 68. Exactly what the chip draws: two lines of 15px copy beside a 30px
## icon tile, a 14px channel, 4px of pad. The other 16px was air, and air at the
## top of the screen is museum the player never gets to see.
const CHIP_HEIGHT := 68
const HEAD_HEIGHT := 48   # one 48dp row carrying both the rating chip and the bar

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


## Venue progress drawn as MILESTONE_COUNT segments instead of a solid bar with a
## separate row of star pips above it. One widget, one row, same two facts:
## how far along the venue is, and how many milestones are banked.
class SegBar extends Control:
	const K = preload("res://scripts/ui/ui_kit.gd")
	const GAP := 4.0

	var segments: int = 8
	var progress: float = 0.0
	var earned: int = 0

	# Built once. _draw runs on every visual frame the strip is dirty, and
	# refresh() fires twice a second forever — allocating styleboxes in there is
	# exactly the churn _set_skin was written to avoid.
	var _trough: StyleBoxFlat = _box(Color(1, 1, 1, 0.14), Color(0, 0, 0, 0.35))
	var _gold: StyleBoxFlat = _box(K.BRASS)
	var _green: StyleBoxFlat = _box(K.SAGE)

	static func _box(fill: Color, rim: Color = Color(0, 0, 0, 0)) -> StyleBoxFlat:
		var sb := StyleBoxFlat.new()
		sb.bg_color = fill
		sb.set_corner_radius_all(5)
		if rim.a > 0.0:
			sb.set_border_width_all(1)
			sb.border_color = rim
		return sb

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		custom_minimum_size = Vector2(80, 14)

	func set_state(p: float, e: int) -> void:
		if is_equal_approx(p, progress) and e == earned:
			return
		progress = p
		earned = e
		queue_redraw()

	func _draw() -> void:
		var n: int = maxi(segments, 1)
		var w: float = (size.x - GAP * float(n - 1)) / float(n)
		if w <= 1.0:
			return
		for i in range(n):
			var x: float = float(i) * (w + GAP)
			draw_style_box(_trough, Rect2(x, 0.0, w, size.y))
			var f: float = clampf(progress * float(n) - float(i), 0.0, 1.0)
			if f <= 0.0:
				continue
			# Banked milestones go gold, the segment being filled stays green:
			# progress and reward read as two different states at a glance.
			var box: StyleBoxFlat = _gold if i < earned else _green
			draw_style_box(box, Rect2(x + 1.0, 1.0, maxf((w - 2.0) * f, 3.0), size.y - 2.0))


var _seg: SegBar
var _pct_label: Label
var _chips: Array = []  # Array of {btn, tile, icon, desc, bar, frac, quest_id, skin}
var _rating_btn: Button
var _rating_stars: Array[TextureRect] = []
var _rating_value: Label
var _rating_mult: Label

func _ready() -> void:
	custom_minimum_size = Vector2(0, 4 + HEAD_HEIGHT + 6 + CHIP_HEIGHT + 6)
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
	vbox.add_theme_constant_override("separation", 6)
	margin.add_child(vbox)

	# Row 1: rating chip + venue progress, side by side. Both used to own a full
	# band; neither needs one, and the strip is competing with the museum.
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 8)
	vbox.add_child(head)
	head.add_child(_build_rating_chip())
	head.add_child(_build_progress_pill())

	# Row 2: the objective chips.
	var chip_row := HBoxContainer.new()
	chip_row.add_theme_constant_override("separation", 8)
	chip_row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(chip_row)
	for i in range(CHIP_COUNT):
		chip_row.add_child(_build_chip(i))

## Rating as a chip: five stars, the score, and the income multiplier it is
## worth. The sentence that used to sit here ("The halls look bare — 0 of 30
## decor points") is the decor screen's job; the HUD needs the state and a way in.
func _build_rating_chip() -> Button:
	_rating_btn = Button.new()
	_rating_btn.custom_minimum_size = Vector2(202, HEAD_HEIGHT)
	_glass_button_skin(_rating_btn, 16)
	_rating_btn.pressed.connect(_on_rating_pressed)

	var row := HBoxContainer.new()
	row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	row.offset_left = 11
	row.offset_right = -11
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 4)
	_rating_btn.add_child(row)

	_rating_stars.clear()
	for i in range(5):
		var s: TextureRect = UI.make_icon("star", 15, BRASS)
		_rating_stars.append(s)
		row.add_child(s)

	_rating_value = UI.make_display_label("0.0", UI.TYPE_LABEL, Color.WHITE)
	_rating_value.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_rating_value.custom_minimum_size = Vector2(30, 0)
	row.add_child(_rating_value)

	_rating_mult = UI.make_display_label("x1.00", UI.TYPE_LABEL, SAGE)
	_rating_mult.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_rating_mult.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_rating_mult.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(_rating_mult)

	_ignore_mouse(row)
	return _rating_btn

func _build_progress_pill() -> PanelContainer:
	var pill := PanelContainer.new()
	pill.add_theme_stylebox_override("panel", _pill_box(16))
	pill.custom_minimum_size = Vector2(0, HEAD_HEIGHT)
	pill.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	pill.add_child(row)

	row.add_child(UI.make_icon("trophy", 20, BRASS))

	_seg = SegBar.new()
	_seg.segments = MILESTONE_COUNT
	_seg.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_seg.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(_seg)

	_pct_label = UI.make_display_label("0%", UI.TYPE_LABEL, BRASS)
	_pct_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_pct_label.custom_minimum_size = Vector2(44, 0)
	_pct_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(_pct_label)
	return pill

## One objective chip: a Button wearing a glass pill, with an icon tile, wrapped
## copy and a fraction-carrying progress channel laid over it.
func _build_chip(index: int) -> Button:
	var btn := Button.new()
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	btn.custom_minimum_size = Vector2(0, CHIP_HEIGHT)
	_glass_button_skin(btn, 14)
	btn.pressed.connect(_on_chip_pressed.bind(index))

	# Button lays out no children of its own, so the content is a full-rect
	# overlay. Everything inside must ignore the mouse or the Button never sees
	# the tap that is the whole point of this rebuild.
	var pad := MarginContainer.new()
	pad.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	pad.add_theme_constant_override("margin_left", 7)
	pad.add_theme_constant_override("margin_right", 7)
	pad.add_theme_constant_override("margin_top", 4)
	pad.add_theme_constant_override("margin_bottom", 4)
	btn.add_child(pad)

	# A VBox that FILLS the pad, with the copy row expanding and the channel at a
	# fixed 14px. Hanging the label off a shrink-to-fit column instead let the
	# Button (which reports no minimum size for an overlay) squeeze the copy to
	# nothing: the chips rendered as an icon and a bar with the text gone.
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 2)
	pad.add_child(col)

	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 6)
	head.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(head)

	var tile := PanelContainer.new()
	tile.custom_minimum_size = Vector2(30, 30)
	tile.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	tile.add_theme_stylebox_override("panel", _tile_box(UI.SLATE))
	var tile_icon := UI.make_icon("question", 20, Color.WHITE)
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
	desc.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	head.add_child(desc)

	var prog := ProgressBar.new()
	prog.min_value = 0.0
	prog.max_value = 1.0
	prog.step = 0.001
	prog.show_percentage = false
	prog.custom_minimum_size = Vector2(0, 14)
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

# --- Skinning ------------------------------------------------------------------

func _pill_box(radius: int) -> StyleBoxFlat:
	var sb := UI.make_glass(radius)
	sb.content_margin_left = 11
	sb.content_margin_right = 11
	sb.content_margin_top = 4
	sb.content_margin_bottom = 4
	return sb

func _glass_button_skin(b: Button, radius: int) -> void:
	b.add_theme_stylebox_override("normal", UI.make_glass(radius))
	b.add_theme_stylebox_override("hover", UI.make_glass(radius, 0.92, Color(1, 1, 1, 0.28)))
	b.add_theme_stylebox_override("pressed", UI.make_glass(radius, 0.96, Color(1, 1, 1, 0.34)))
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	UI.add_press_squish(b)

func _tile_box(tint: Color, inverted: bool = false) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = tint.darkened(0.62) if inverted else tint
	sb.set_corner_radius_all(9)
	sb.set_content_margin_all(4)
	if inverted:
		sb.set_border_width_all(2)
		sb.border_color = tint
	return sb

func _ignore_mouse(n: Node) -> void:
	if n is Control:
		(n as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE
	for c in n.get_children():
		_ignore_mouse(c)

# --- State ---------------------------------------------------------------------

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
	var done_count: int = vs.get("milestones", []).size()
	_seg.set_state(progress, done_count)
	_pct_label.text = "%d%%" % int(round(progress * 100.0))
	_refresh_rating()
	var active: Array = vs.get("active_quests", [])
	for i in range(_chips.size()):
		if i < active.size() and DataLoader.quests.has(str(active[i])):
			_paint_chip(_chips[i], vid, str(active[i]))
		else:
			_paint_done(_chips[i])

func _refresh_rating() -> void:
	if _rating_value == null:
		return
	var sat: Dictionary = Economy.venue_satisfaction(GameState.current_venue)
	var stars: float = float(sat["stars_rounded"])
	for i in range(_rating_stars.size()):
		var tint: Color = UI.LOCKED
		if stars >= float(i) + 1.0:
			tint = BRASS
		elif stars >= float(i) + 0.5:
			tint = BRASS.lerp(UI.LOCKED, 0.5)  # half star, without a second texture
		_rating_stars[i].modulate = tint
	_rating_value.text = "%.1f" % float(sat["stars"])
	var mult: float = float(sat["income_mult"])
	_rating_mult.text = "x%.2f" % mult
	_rating_mult.add_theme_color_override("font_color", SAGE if mult >= 1.0 else UI.DANGER)

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
	(chip["icon"] as TextureRect).texture = UI.icon_texture(icon_name, 20)
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

## The rating chip is the way into the screen that changes the rating. Never
## disabled: an unavailable decor screen toasts what unlocks it.
func _on_rating_pressed() -> void:
	if GameState.feature_unlocked("decor"):
		Popups.open(PATH_DECOR)
	else:
		var req: int = int(DataLoader.core.get("unlocks", {}).get("decor_rep", 2))
		EventBus.toast_requested.emit("Decor unlocks at Rep %d — it drives your rating" % req)

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
