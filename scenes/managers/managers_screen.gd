extends Control
## ManagersScreen — the staff-pass coverflow (SPEC §11).
##
## The roster used to be a vertical list of fourteen wide rows, which is a
## spreadsheet of a collection rather than a collection. It is now a carousel:
## one pass face-on in the middle at full size, its neighbours receding to either
## side — smaller, lower, dimmer and horizontally squashed so they read as turned
## away from the player. Godot 2D has no perspective, so the squash IS the angle;
## anything more elaborate would mean a Camera3D and a second render pass for
## fourteen ID cards.
##
## The centred pass is the selection. Everything the player can DO with a manager
## sits in a fixed bar below the carousel, so levelling, ranking and posting are
## one tap from the card rather than behind a modal.
##
## Only five passes exist at a time (centre plus two either side) in a ring keyed
## by index modulo the pool, so scrolling the whole roster rebuilds one card per
## half-step instead of holding fourteen live cards with fourteen portraits.

const ManagerSystem := preload("res://scripts/managers/manager_system.gd")
const UI := preload("res://scripts/ui/ui_kit.gd")
const ManagerBadge := preload("res://scenes/managers/manager_badge.gd")

# This screen is popup CONTENT on a DARK page: the deck of passes is the bright
# thing, so the ground behind it stays out of the way and the body text is light.
const BG := UI.PAGE
const INK := UI.TEXT
const DIM := UI.TEXT_DIM
const PANEL := UI.CARD
const ACCENT := UI.ACCENT
const SLATE := UI.SLATE
const PLUM := UI.PLUM
# Palette comes from ui_kit — these were private copies of the retired muted
# scheme, so this screen kept rendering in the old colours after the repaint.
const LOCKED := UI.LOCKED
const DEPT_COLORS := UI.DEPT_COLORS
const RARITY_ORDER := {"common": 0, "rare": 1, "epic": 2, "legendary": 3}

const CARD := ManagerBadge.CARD
## Action bar height: three button rows at one touch target each, plus their
## separations. Reserved whether or not the selected pass has anything to act on.
const ACTIONS_H := 3 * UI.TOUCH_MIN + 2 * 8
## Position dot diameter. Fourteen of these plus a "n of 14" read has to fit one
## row inside 692px, which caps the dot at single digits.
const DOT := 8

## Live passes: centre, plus two each side. A third neighbour is under 12% of the
## screen width by the time it is on stage and costs a whole portrait to draw.
const POOL := 5
## Cards further out than this are not drawn at all. 2.6 rather than 2.5 so a
## card is already invisible when the ring hands its slot to the next index.
const CULL := 2.6

## Drag distance, in design px, that advances the carousel by exactly one pass —
## and the gap to the first neighbour, so the deck tracks the finger exactly.
## Tuned for a thumb: a comfortable swipe across a 720px canvas is ~200px. It is
## deliberately shorter than the card is wide, so a neighbour tucks BEHIND the
## centred pass instead of standing clear of it in its own column.
const STRIDE_MIN := 170.0
const STRIDE_MAX := 230.0
const STRIDE_FRACTION := 0.30
## How far a flick coasts: seconds of its release velocity, then snap.
const GLIDE_SECS := 0.20
## Fastest flick worth honouring, in passes. Beyond this the carousel would fly
## past everything the player was looking at.
const GLIDE_MAX := 3.0
## A press that moves less than this and lasts less than this is a tap, not a
## drag. 14px is under the thumb's own wobble on a held press.
const TAP_SLOP := 14.0
const TAP_SECS := 0.5
## Settle stiffness. Higher snaps harder; 15 lands in about a fifth of a second
## without the overshoot that makes a carousel feel loose.
const SETTLE_K := 15.0

var _payload: Dictionary = {}
var _insight_chip: PanelContainer
var _roster_label: Label
var _deck: Control
var _stage: Control
var _dots: HBoxContainer
var _counter: Label
var _actions: VBoxContainer
var _viewed: Dictionary = {}        # manager_id -> true (NEW badge cleared this session)

var _ids: Array[String] = []
var _slots: Array[Dictionary] = []
var _pos: float = 0.0               # continuous carousel position, in passes
var _target: float = 0.0            # pass the carousel is settling onto
var _shown: int = -1                # index the dots/counter currently show
var _acted: int = -1                # index the action bar currently describes

var _dragging := false
var _drag_from := 0.0               # _pos when the press landed
var _press_x := 0.0
var _press_at := 0.0
var _travel := 0.0
var _last_x := 0.0
var _last_t := 0.0
var _vel := 0.0                     # passes per second, sign follows _pos

func setup(payload: Dictionary) -> void:
	_payload = payload

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.color = BG
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var root_box := VBoxContainer.new()
	root_box.set_anchors_preset(Control.PRESET_FULL_RECT)
	root_box.add_theme_constant_override("separation", 8)
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		margin.add_theme_constant_override(side, 14)
	margin.add_child(root_box)
	add_child(margin)
	root_box.add_child(_build_header())
	root_box.add_child(_build_stage())
	root_box.add_child(_build_dots())
	_actions = VBoxContainer.new()
	_actions.add_theme_constant_override("separation", 8)
	# Fixed height whatever it holds. A sealed pass has one line of copy where an
	# issued one has three buttons, and letting the bar collapse made the carousel
	# above it grow — so the centred card jumped up the screen every time the
	# player scrolled past a manager they had not found yet.
	_actions.custom_minimum_size = Vector2(0, ACTIONS_H)
	root_box.add_child(_actions)

	EventBus.insight_changed.connect(func(_v: Variant) -> void: _refresh_header())
	EventBus.manager_obtained.connect(func(_a: String, _b: int) -> void: refresh())
	EventBus.manager_leveled.connect(func(_a: String, _b: int) -> void: refresh())
	EventBus.manager_ranked_up.connect(func(_a: String, _b: int) -> void: refresh())
	EventBus.manager_assigned.connect(func(_a: String, _b: String) -> void: refresh())
	EventBus.manager_exchanged.connect(func(_a: String, _b: String, _c: int, _d: int) -> void: refresh())

	_ids = _sorted_ids()
	_build_dot_row()
	for k in POOL:
		_slots.append({"holder": _make_holder(), "card": null, "index": -9999,
			"x": 0.0, "y": 0.0, "w": 0.0, "h": 0.0})
	set_process(true)
	refresh()
	if _payload.has("select"):
		select_manager(str(_payload["select"]), true)
	else:
		_jump_to(0)

# ------------------------------------------------------------------ chrome

func _build_header() -> Control:
	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 12)
	var titles := VBoxContainer.new()
	titles.add_theme_constant_override("separation", 0)
	titles.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	titles.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	titles.add_child(UI.make_display_label("Staff Passes", 32, INK))
	# A collection screen has to say how much of the collection is left, or the
	# only way to count the roster is to scroll it.
	_roster_label = UI.make_label("", UI.TYPE_LABEL)
	_roster_label.add_theme_color_override("font_color", DIM)
	titles.add_child(_roster_label)
	bar.add_child(titles)
	_insight_chip = UI.make_dark_currency_chip("insight", "0", SLATE, 26)
	bar.add_child(_insight_chip)
	_refresh_header()
	return bar

func _refresh_header() -> void:
	if is_instance_valid(_insight_chip):
		UI.set_chip_value(_insight_chip, GameState.insight.to_notation())
	if is_instance_valid(_roster_label):
		var have := 0
		for id in DataLoader.managers.keys():
			if ManagerSystem.cards(id) > 0:
				have += 1
		_roster_label.text = "%d of %d passes issued" % [have, DataLoader.managers.size()]

## The carousel stage: a clipped box holding the deck, with a transparent drag
## surface laid over the top. The surface is what receives every press — a card
## sitting under the finger would swallow the drag the moment the thumb landed on
## it, which is how a carousel ends up only responding to clean clicks.
func _build_stage() -> Control:
	_stage = Control.new()
	_stage.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_stage.custom_minimum_size = Vector2(0, 420)
	_stage.clip_contents = true
	_deck = Control.new()
	_deck.set_anchors_preset(Control.PRESET_FULL_RECT)
	_deck.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_stage.add_child(_deck)
	var touch := Control.new()
	touch.set_anchors_preset(Control.PRESET_FULL_RECT)
	touch.mouse_filter = Control.MOUSE_FILTER_STOP
	touch.gui_input.connect(_on_drag_input)
	_stage.add_child(touch)
	_stage.resized.connect(_apply_layout)
	return _stage

func _build_dots() -> Control:
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 10)
	_dots = HBoxContainer.new()
	_dots.add_theme_constant_override("separation", 5)
	_dots.alignment = BoxContainer.ALIGNMENT_CENTER
	_dots.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(_dots)
	_counter = UI.make_display_label("", UI.TYPE_CAPTION, DIM)
	_counter.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(_counter)
	return row

## One dot per pass, filled for issued and hollow for sealed, so the strip
## doubles as a map of how much of the roster is still to find.
func _build_dot_row() -> void:
	for c in _dots.get_children():
		_dots.remove_child(c)
		c.queue_free()
	for i in _ids.size():
		var owned: bool = ManagerSystem.cards(_ids[i]) > 0
		var d := UI.make_dot(DIM if owned else UI.LOCKED, DOT)
		d.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		# Set now, not in the paint pass: a dot that has never been laid out has
		# zero size, and a pivot of zero swings the active dot off its own row.
		d.pivot_offset = Vector2(DOT, DOT) / 2.0
		_dots.add_child(d)

func _paint_dots(index: int) -> void:
	for i in _dots.get_child_count():
		var d: Control = _dots.get_child(i)
		var owned: bool = ManagerSystem.cards(_ids[i]) > 0
		if i == index:
			d.scale = Vector2(1.6, 1.6)
			d.modulate = ACCENT if owned else ACCENT.lerp(PANEL, 0.35)
		else:
			d.scale = Vector2.ONE
			d.modulate = Color.WHITE
	_counter.text = "%d of %d" % [index + 1, _ids.size()]

# ------------------------------------------------------------------ data

func refresh() -> void:
	_refresh_header()
	var before := _ids.size()
	_ids = _sorted_ids()
	if _ids.size() != before:
		_build_dot_row()
	for s in _slots:
		if int(s["index"]) >= 0:
			_fill(s, int(s["index"]), true)
	_shown = -1
	_acted = -1
	_apply_layout()
	_sync_index()

func _sorted_ids() -> Array[String]:
	var ids: Array[String] = []
	for id in DataLoader.managers.keys():
		ids.append(id)
	ids.sort_custom(func(a: String, b: String) -> bool:
		var da: Dictionary = DataLoader.get_manager_def(a)
		var db: Dictionary = DataLoader.get_manager_def(b)
		var ra: int = int(RARITY_ORDER.get(str(da.get("rarity", "common")), 0))
		var rb: int = int(RARITY_ORDER.get(str(db.get("rarity", "common")), 0))
		if ra != rb:
			return ra < rb
		return str(da.get("name", a)) < str(db.get("name", b)))
	return ids

## Index of a manager in carousel order, or -1.
func index_of(id: String) -> int:
	return _ids.find(id)

## The pass currently centred. Selection is position, not a stored field: there
## is no way for the two to disagree.
func selected_id() -> String:
	var i := selected_index()
	return _ids[i] if i >= 0 else ""

func selected_index() -> int:
	if _ids.is_empty():
		return -1
	return _wrap(roundi(_target))

## Roster index for any carousel place, wrapped. The carousel counts in whole
## passes forever in both directions — a merry-go-round has no first horse — so
## place -1 is the last pass and place 14 is the first one again.
func _wrap(place: int) -> int:
	if _ids.is_empty():
		return -1
	if not _wraps():
		return clampi(place, 0, _ids.size() - 1)
	return posmod(place, _ids.size())

## A roster too short to fill the stage cannot wrap without showing the same
## pass twice on screen, so it runs as a plain bounded strip instead.
func _wraps() -> bool:
	return _ids.size() >= POOL

## Centre a manager. `immediate` skips the glide — used when the screen opens on
## a manager the player tapped somewhere else.
func select_manager(id: String, immediate: bool = false) -> void:
	var i := index_of(id)
	if i < 0:
		return
	if immediate:
		_jump_to(i)
	else:
		_set_target(_nearest_place(i))

## The carousel place holding roster index `i` that is closest to where the deck
## is now. Selecting the last pass while sitting on the first should turn one
## step backwards, not thirteen forwards.
func _nearest_place(i: int) -> int:
	var here := roundi(_pos)
	if not _wraps():
		return clampi(i, 0, _ids.size() - 1)
	var n: int = _ids.size()
	var delta: int = posmod(i - _wrap(here), n)
	if delta > n / 2:
		delta -= n
	return here + delta

func _jump_to(i: int) -> void:
	_target = float(_nearest_place(i))
	_set_pos(_target)
	_sync_index()

# ------------------------------------------------------------------ ring

func _make_holder() -> Control:
	var h := Control.new()
	h.size = CARD
	h.custom_minimum_size = CARD
	h.pivot_offset = CARD / 2.0
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.visible = false
	_deck.add_child(h)
	return h

## Bind slot `s` to roster index `i`, rebuilding its card. `force` re-binds even
## when the index has not moved, which is what a level-up or a new recruit needs.
func _fill(s: Dictionary, i: int, force: bool = false) -> void:
	if int(s["index"]) == i and not force:
		return
	s["index"] = i
	var holder: Control = s["holder"]
	if s["card"] != null and is_instance_valid(s["card"]):
		holder.remove_child(s["card"])
		s["card"].queue_free()
	s["card"] = null
	var slot_id := _wrap(i)
	if slot_id < 0:
		holder.visible = false
		return
	var id: String = _ids[slot_id]
	var card := ManagerBadge.new()
	card.size = CARD
	card.custom_minimum_size = CARD
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Parent before setup: the pass's photo asks PortraitBaker for a render, and
	# the baker refuses a request from a node with no tree to await on.
	holder.add_child(card)
	card.setup(id, DataLoader.get_manager_def(id), ManagerSystem.state(id),
		ManagerSystem.cards(id) > 0, not _viewed.get(id, false))
	card.set_anchors_preset(Control.PRESET_FULL_RECT)
	s["card"] = card

## Hand each slot the index it should be showing for the current position. The
## ring is keyed by index modulo POOL, so exactly one slot changes hands per
## half-step and the other four keep their built cards.
func _rebind() -> void:
	var centre := roundi(_pos)
	var reach: int = POOL / 2
	for i in range(centre - reach, centre + reach + 1):
		_fill(_slots[posmod(i, POOL)], i)

# ------------------------------------------------------------------ layout

## Where a pass sits, given how many places it is from the centre. Everything the
## recede is made of lives here: offset, scale, the horizontal squash that stands
## in for turning away, a small drop, and dimming.
func _apply_layout() -> void:
	if _deck == null or _slots.is_empty():
		return
	var box: Vector2 = _deck.size
	if box.x <= 0.0 or box.y <= 0.0:
		return
	# Short viewports (20:9 with a tall safe area) shrink the whole carousel
	# rather than clipping the centred pass.
	var fit: float = clampf(minf((box.y - 16.0) / CARD.y, 1.0), 0.60, 1.0)
	var step: float = _stride() * fit
	var edge: float = step * 0.46
	for s in _slots:
		var holder: Control = s["holder"]
		var i: int = int(s["index"])
		var d: float = float(i) - _pos
		var ad: float = absf(d)
		if _wrap(i) < 0 or ad > CULL:
			holder.visible = false
			s["w"] = 0.0
			continue
		holder.visible = true
		var lin: float = minf(ad, 1.0)
		var ext: float = maxf(ad - 1.0, 0.0)
		var sc: float = fit * (1.0 - 0.26 * lin - 0.115 * ext)
		var squash: float = 1.0 - 0.44 * lin - 0.14 * ext
		var x: float = signf(d) * (step * lin + edge * ext)
		var y: float = 24.0 * lin + 14.0 * ext
		holder.scale = Vector2(sc * squash, sc)
		holder.position = Vector2(box.x * 0.5 + x, box.y * 0.5 + y) - CARD / 2.0
		var v: float = 1.0 - 0.28 * lin - 0.14 * ext
		holder.modulate = Color(v, v, v, 1.0 - 0.08 * lin - 0.30 * ext)
		s["x"] = box.x * 0.5 + x
		s["y"] = box.y * 0.5 + y
		s["w"] = CARD.x * sc * squash
		s["h"] = CARD.y * sc
	_restack()

## Nearest pass in front. Done by sibling order rather than z_index: z_index is
## global inside a canvas layer, and this screen shares one with the popup frame
## and the dept sheet, so five cards claiming a band here is a debt somebody else
## pays later.
func _restack() -> void:
	var order := _slots.duplicate()
	order.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return absf(float(a["index"]) - _pos) > absf(float(b["index"]) - _pos))
	for i in order.size():
		var holder: Control = order[i]["holder"]
		if holder.get_index() != i:
			_deck.move_child(holder, i)

func _set_pos(p: float) -> void:
	_pos = p
	_rebind()
	_apply_layout()
	var shown := maxi(_wrap(roundi(_pos)), 0)
	if shown != _shown:
		_shown = shown
		_paint_dots(shown)

# ------------------------------------------------------------------ input

func _on_drag_input(ev: InputEvent) -> void:
	# Touch on Android arrives as BOTH a screen event and an emulated mouse
	# event. Both paths are driven from the absolute press position, so handling
	# a duplicate re-derives the same answer instead of doubling the travel.
	if ev is InputEventMouseButton and ev.button_index == MOUSE_BUTTON_LEFT:
		if ev.pressed:
			_press(ev.position)
		else:
			_release(ev.position)
	elif ev is InputEventScreenTouch:
		if ev.pressed:
			_press(ev.position)
		else:
			_release(ev.position)
	elif ev is InputEventScreenDrag:
		_move(ev.position)
	elif ev is InputEventMouseMotion and (ev.button_mask & MOUSE_BUTTON_MASK_LEFT) != 0:
		_move(ev.position)

func _press(at: Vector2) -> void:
	_dragging = true
	_drag_from = _pos
	_press_x = at.x
	_last_x = at.x
	_press_at = _now()
	_last_t = _press_at
	_travel = 0.0
	_vel = 0.0

func _move(at: Vector2) -> void:
	if not _dragging:
		return
	var dx: float = at.x - _press_x
	_travel = maxf(_travel, absf(dx))
	var t: float = _now()
	var dt: float = t - _last_t
	if dt > 0.004:
		# Weighted toward the newest sample: a flick is decided by the last few
		# milliseconds of the swipe, not by its average speed.
		_vel = lerpf(_vel, -(at.x - _last_x) / _stride() / dt, 0.6)
		_last_x = at.x
		_last_t = t
	_set_pos(_bound(_drag_from - dx / _stride()))

func _release(at: Vector2) -> void:
	if not _dragging:
		return
	_dragging = false
	if _travel < TAP_SLOP and _now() - _press_at < TAP_SECS:
		_tap(at)
		return
	if _now() - _last_t > 0.12:
		_vel = 0.0        # finger stopped and held before lifting: no throw
	var glide: float = clampf(_vel * GLIDE_SECS, -GLIDE_MAX, GLIDE_MAX)
	_set_target(roundi(_pos + glide))

## Tapping a receded pass brings it to the front; tapping the centred one is a
## no-op, because it is already showing everything it has.
func _tap(at: Vector2) -> void:
	# A place, not a roster index: places run negative once the carousel has been
	# turned backwards, so there is no "no hit" value to be read out of the number
	# itself and the hit needs its own flag.
	var best := 0
	var best_d := 1e9
	var hit := false
	for s in _slots:
		var w: float = float(s["w"])
		if w <= 0.0:
			continue
		if absf(at.x - float(s["x"])) > w * 0.5 or absf(at.y - float(s["y"])) > float(s["h"]) * 0.5:
			continue
		# Nearest wins, which is the one drawn on top: the neighbours tuck behind
		# the centred pass, so their middles belong to the card in front of them.
		var d: float = absf(float(s["index"]) - _pos)
		if d < best_d:
			best_d = d
			best = int(s["index"])
			hit = true
	if hit and best != roundi(_target):
		_set_target(best)

func _stride() -> float:
	var box: float = _deck.size.x if _deck != null else 692.0
	return clampf(box * STRIDE_FRACTION, STRIDE_MIN, STRIDE_MAX)

## A wrapping carousel has no ends to defend. A short one does: past either end
## it still moves, at a third of the finger, and springs back on release, because
## a hard stop reads as a broken swipe.
func _bound(p: float) -> float:
	if _wraps():
		return p
	var last: float = float(maxi(_ids.size() - 1, 0))
	if p < 0.0:
		return p * 0.34
	if p > last:
		return last + (p - last) * 0.34
	return p

func _set_target(place: int) -> void:
	var t: float = float(place) if _wraps() else float(clampi(place, 0, maxi(_ids.size() - 1, 0)))
	if t != _target:
		UI.play_sfx(self, "tap")
	_target = t
	_sync_index()

func _now() -> float:
	return float(Time.get_ticks_msec()) / 1000.0

func _process(delta: float) -> void:
	if _dragging or is_equal_approx(_pos, _target):
		return
	# Exponential settle: frame-rate independent, and it cannot overshoot, so a
	# fast flick never bounces the centred pass back out of frame.
	var p: float = _target + (_pos - _target) * exp(-SETTLE_K * delta)
	if absf(p - _target) < 0.0008:
		p = _target
	_set_pos(p)

# ------------------------------------------------------------------ actions

## Rebuild the action bar when the SETTLED selection changes. It deliberately
## does not follow the finger: rebuilding four buttons every frame of a drag is
## both jank and a moving target under the thumb.
func _sync_index() -> void:
	var i := selected_index()
	if i == _acted:
		return
	_acted = i
	if i >= 0:
		_viewed[_ids[i]] = true
	_rebuild_actions()

func _rebuild_actions() -> void:
	for c in _actions.get_children():
		_actions.remove_child(c)
		c.queue_free()
	var id := selected_id()
	if id == "":
		return
	var def: Dictionary = DataLoader.get_manager_def(id)
	if ManagerSystem.cards(id) <= 0:
		var hint := UI.make_label(
			"Sealed. %s cards turn up in lootboxes — find one to open this file." %
			str(def.get("rarity", "common")).capitalize(), UI.TYPE_BODY)
		hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		hint.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		hint.size_flags_vertical = Control.SIZE_EXPAND_FILL
		hint.add_theme_color_override("font_color", DIM)
		_actions.add_child(hint)
		return

	# Colour carries affordability; the buttons stay live. A disabled button eats
	# the press without moving a pixel, which reads as a broken screen rather
	# than as "you cannot afford this yet".
	var capped: bool = ManagerSystem.level(id) >= int(def.get("level_cap", 50))
	var can_level: bool = ManagerSystem.can_level_up(id)
	var lvl_btn := UI.make_button(
		"Level Up — MAX LEVEL" if capped
		else "Level Up — %s Insight" % ManagerSystem.level_up_cost(id).to_notation(),
		SLATE if can_level else LOCKED)
	lvl_btn.icon = UI.icon_texture("insight", 20)
	lvl_btn.pressed.connect(func() -> void: ManagerSystem.level_up(id))
	_actions.add_child(lvl_btn)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	_actions.add_child(row)
	var dup_cost: int = ManagerSystem.rank_up_cost(id)
	var can_rank: bool = ManagerSystem.can_rank_up(id)
	var rank_btn := UI.make_button(
		"Rank Up — MAX" if dup_cost <= 0
		else "Rank Up — %d cards (have %d)" % [dup_cost, ManagerSystem.cards(id)],
		PLUM if can_rank else LOCKED)
	rank_btn.icon = UI.icon_texture("star", 20)
	rank_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rank_btn.pressed.connect(func() -> void: ManagerSystem.rank_up(id))
	row.add_child(rank_btn)
	var ex_btn := UI.make_button("Trade", LOCKED)
	ex_btn.pressed.connect(func() -> void: _open_exchange(id))
	row.add_child(ex_btn)

	# One post, one button. Only the specialty department accepts a manager, so
	# the old row of four department buttons was three dead controls and a live
	# one, and the player had to work out which by tapping them.
	var specialty: String = str(def.get("specialty", ""))
	var dept: Color = DEPT_COLORS.get(specialty, LOCKED)
	var holder := _holder_of(specialty)
	var post_btn := UI.make_button("", dept)
	post_btn.add_theme_font_size_override("font_size", UI.TYPE_HEADING)
	if ManagerSystem.assigned_to(id) == specialty:
		post_btn.text = "On duty — %s (stand down)" % specialty.capitalize()
		post_btn.pressed.connect(func() -> void: ManagerSystem.unassign(id))
	elif holder != "":
		# Swapping is the only thing the player could have meant, and refusing
		# the tap would leave them staring at a button that does nothing.
		post_btn.text = "Take the %s post from %s" % [
			specialty.capitalize(), str(DataLoader.get_manager_def(holder).get("name", holder)).split(" ")[0]]
		post_btn.pressed.connect(func() -> void:
			ManagerSystem.unassign(holder)
			ManagerSystem.assign(id, specialty))
	else:
		post_btn.text = "Post to %s" % specialty.capitalize()
		post_btn.pressed.connect(func() -> void: ManagerSystem.assign(id, specialty))
	_actions.add_child(post_btn)

## Who currently holds `dept`, or "".
func _holder_of(dept: String) -> String:
	if dept == "":
		return ""
	for id in _ids:
		if ManagerSystem.assigned_to(id) == dept:
			return id
	return ""

func _open_exchange(from_id: String) -> void:
	var def: Dictionary = DataLoader.get_manager_def(from_id)
	var rarity: String = str(def.get("rarity", "common"))
	var dlg := Control.new()
	dlg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(dlg)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.62)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	dlg.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	dlg.add_child(center)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(600, 0)
	panel.add_theme_stylebox_override("panel", UI.make_dark_frame(ACCENT))
	center.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	panel.add_child(box)
	var ratio: int = ManagerSystem.exchange_ratio()
	var head := Label.new()
	head.text = "Trade %d cards of %s for 1 card of:" % [ratio, str(def.get("name", from_id))]
	head.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	head.add_theme_font_size_override("font_size", 20)
	head.add_theme_color_override("font_color", INK)
	box.add_child(head)
	var note := Label.new()
	note.text = "You keep at least 1 card. You have %d." % ManagerSystem.cards(from_id)
	note.add_theme_font_size_override("font_size", 16)
	note.add_theme_color_override("font_color", DIM)
	box.add_child(note)
	for tid in _ids:
		if tid == from_id:
			continue
		var td: Dictionary = DataLoader.get_manager_def(tid)
		if str(td.get("rarity", "")) != rarity:
			continue
		var b := UI.make_button("%s  (%d cards owned)" % [str(td.get("name", tid)), ManagerSystem.cards(tid)],
			SLATE if ManagerSystem.can_exchange(from_id, tid) else LOCKED)
		b.add_theme_font_size_override("font_size", 18)
		var target: String = tid
		b.pressed.connect(func() -> void:
			if ManagerSystem.exchange(from_id, target):
				dlg.queue_free())
		box.add_child(b)
	var cancel := UI.make_button("Cancel", LOCKED)
	cancel.pressed.connect(func() -> void: dlg.queue_free())
	box.add_child(cancel)
