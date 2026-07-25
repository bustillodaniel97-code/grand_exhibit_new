extends Control
## ManagersScreen — collection grid + detail panel (SPEC §11).
## UI built fully in code; visuals via ui_kit v2 (Kenney CC0 skin). Logic unchanged.

const ManagerSystem := preload("res://scripts/managers/manager_system.gd")
const UI := preload("res://scripts/ui/ui_kit.gd")
const ManagerBadge := preload("res://scenes/managers/manager_badge.gd")
const ManagerPortrait := preload("res://scenes/managers/manager_portrait.gd")

# This screen is popup CONTENT, so its page is a light surface, not the
# deep app shell — it draws INK body text directly on it.
const BG := UI.SURFACE
const INK := UI.INK
const PANEL := UI.PANEL
const ACCENT := UI.ACCENT
const BRASS := UI.BRASS
const SAGE := UI.SAGE
const SLATE := UI.SLATE
const PLUM := UI.PLUM
# Palette comes from ui_kit — these were private copies of the retired muted
# scheme, so this screen kept rendering in the old colours after the repaint.
const LOCKED := UI.LOCKED
const DEPT_COLORS := UI.DEPT_COLORS
const RARITY_COLORS := UI.RARITY_COLORS
const RARITY_ORDER := {"common": 0, "rare": 1, "epic": 2, "legendary": 3}

var _payload: Dictionary = {}
var _insight_chip: PanelContainer
var _roster_label: Label
var _grid: VBoxContainer
var _overlay: Control
var _viewed: Dictionary = {}        # manager_id -> true (NEW badge cleared this session)
var _selected: String = ""

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
	root_box.add_theme_constant_override("separation", 10)
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		margin.add_theme_constant_override(side, 16)
	margin.add_child(root_box)
	add_child(margin)
	root_box.add_child(_build_header())
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_grid = VBoxContainer.new()
	_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_grid.add_theme_constant_override("separation", 8)
	scroll.add_child(_grid)
	root_box.add_child(scroll)
	EventBus.insight_changed.connect(func(_v: Variant) -> void: _refresh_header())
	EventBus.manager_obtained.connect(func(_a: String, _b: int) -> void: refresh())
	EventBus.manager_leveled.connect(func(_a: String, _b: int) -> void: refresh())
	EventBus.manager_ranked_up.connect(func(_a: String, _b: int) -> void: refresh())
	EventBus.manager_assigned.connect(func(_a: String, _b: String) -> void: refresh())
	EventBus.manager_exchanged.connect(func(_a: String, _b: String, _c: int, _d: int) -> void: refresh())
	refresh()
	if _payload.has("select"):
		_open_detail(str(_payload["select"]))

func _build_header() -> Control:
	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 12)
	var titles := VBoxContainer.new()
	titles.add_theme_constant_override("separation", 0)
	titles.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	titles.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	titles.add_child(UI.make_display_label("Staff Passes", 34, INK))
	# A collection screen has to say how much of the collection is left, or the
	# only way to count the roster is to scroll it.
	_roster_label = UI.make_label("", UI.TYPE_LABEL)
	_roster_label.add_theme_color_override("font_color", INK.lerp(PANEL, 0.34))
	titles.add_child(_roster_label)
	bar.add_child(titles)
	_insight_chip = UI.make_currency_chip("insight", "0", SLATE, 26)
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

func refresh() -> void:
	_refresh_header()
	_rebuild_grid()
	if _selected != "" and _overlay != null and _overlay.visible:
		_rebuild_detail(_selected)

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

## Rarity-framed parchment card (rpg-expansion frame tinted toward rarity).
func _style(bg_color: Color, border_color: Color, radius: int = 12, border_w: int = 3) -> StyleBox:
	var tint := Color(1, 1, 1).lerp(border_color, 0.18 + 0.05 * clampi(border_w - 3, 0, 2))
	return UI.make_frame(tint)

## Rank pips: brass stars earned, outline stars spent. A dimmed FILLED star on a
## cream card sat at ~2:1 and read as a rendering fault rather than an empty slot.
func _pips(rank: int) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	row.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	for i in range(4):
		if i < rank:
			row.add_child(UI.make_icon("star", 20, BRASS))
		else:
			row.add_child(UI.make_icon("star_outline", 20, INK.lerp(PANEL, 0.48)))
	return row

func _rebuild_grid() -> void:
	for c in _grid.get_children():
		_grid.remove_child(c)
		c.queue_free()
	for id in _sorted_ids():
		var badge := ManagerBadge.new()
		# Parent before setup: the badge's photo asks PortraitBaker for a render,
		# and the baker refuses a request from a node with no tree to await on.
		_grid.add_child(badge)
		badge.setup(id, DataLoader.get_manager_def(id), ManagerSystem.state(id),
			ManagerSystem.cards(id) > 0, not _viewed.get(id, false))
		badge.tapped.connect(_open_detail)

func _open_detail(id: String) -> void:
	_selected = id
	_viewed[id] = true
	_rebuild_detail(id)
	_rebuild_grid()  # clears the NEW badge

func _close_detail() -> void:
	_selected = ""
	if _overlay != null:
		_overlay.queue_free()
		_overlay = null

func _rebuild_detail(id: String) -> void:
	if _overlay != null:
		_overlay.queue_free()
	var def: Dictionary = DataLoader.get_manager_def(id)
	var rarity: String = str(def.get("rarity", "common"))
	var specialty: String = str(def.get("specialty", ""))
	var locked: bool = ManagerSystem.cards(id) <= 0
	_overlay = Control.new()
	_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_overlay)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.5)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.gui_input.connect(func(ev: InputEvent) -> void:
		if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
			_close_detail())
	_overlay.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_overlay.add_child(center)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(640, 0)
	panel.add_theme_stylebox_override("panel", _style(PANEL, RARITY_COLORS.get(rarity, LOCKED), 12, 4))
	center.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	panel.add_child(box)
	# title row + close
	var top := HBoxContainer.new()
	box.add_child(top)
	var title := Label.new()
	title.text = str(def.get("name", id)) if not locked else "Personnel File Sealed"
	UI.apply_display_font(title, title.text)
	title.add_theme_font_size_override("font_size", 30)
	title.add_theme_color_override("font_color", INK)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(title)
	var close := UI.make_icon_button("cross", ACCENT, 52)
	close.pressed.connect(_close_detail)
	top.add_child(close)
	# Identity block — the badge, blown up. Same portrait, same fields, so the
	# detail sheet reads as the pass the player just tapped rather than a
	# different document about the same person.
	var dept: Color = DEPT_COLORS.get(specialty, LOCKED)
	var id_row := HBoxContainer.new()
	id_row.add_theme_constant_override("separation", 14)
	box.add_child(id_row)
	var photo := ManagerPortrait.new()
	id_row.add_child(photo)
	photo.setup(def, 148, not locked)
	var id_col := VBoxContainer.new()
	id_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	id_col.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	id_col.add_theme_constant_override("separation", 6)
	id_row.add_child(id_col)
	var tags := HBoxContainer.new()
	tags.add_theme_constant_override("separation", 8)
	id_col.add_child(tags)
	tags.add_child(ManagerBadge.pill(rarity.to_upper(), RARITY_COLORS.get(rarity, LOCKED)))
	tags.add_child(ManagerBadge.pill(specialty.to_upper(), dept))
	id_col.add_child(UI.make_display_label(
		str(def.get("post", "")), UI.TYPE_HEADING, INK))
	id_col.add_child(UI.make_display_label(
		"PASS NO. %s" % ManagerBadge.service_no(def), UI.TYPE_CAPTION,
		INK.lerp(PANEL, 0.44)))
	if not locked:
		id_col.add_child(_pips(ManagerSystem.rank(id)))
	var traits: Array = def.get("traits", [])
	if not traits.is_empty():
		var trait_row := HBoxContainer.new()
		trait_row.add_theme_constant_override("separation", 6)
		id_col.add_child(trait_row)
		for t in traits:
			trait_row.add_child(ManagerBadge.trait_chip(str(t), dept))
	# flavor
	var flavor := Label.new()
	flavor.text = str(def.get("flavor", ""))
	flavor.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	flavor.add_theme_font_size_override("font_size", 17)
	flavor.add_theme_color_override("font_color", INK.lerp(PANEL, 0.26))
	box.add_child(flavor)
	# stats
	var st: Dictionary = ManagerSystem.state(id)
	var base_mult: float = float(def.get("base_mult", 0.03))
	var rank_mults: Array = def.get("rank_mults", [1.0, 1.5, 2.25, 3.5])
	var dept_mult: float = 1.0 + base_mult * float(ManagerSystem.level(id)) * float(rank_mults[ManagerSystem.rank(id) - 1])
	var stats := Label.new()
	stats.text = "Level %d / %d    Rank %d    Dept bonus x%.2f    Cards %d\nBattle power: %.1f" % [
		ManagerSystem.level(id), int(def.get("level_cap", 50)), ManagerSystem.rank(id),
		dept_mult, ManagerSystem.cards(id),
		ManagerSystem.battle_attack(def, st)]
	stats.add_theme_font_size_override("font_size", 18)
	stats.add_theme_color_override("font_color", INK)
	box.add_child(stats)
	if locked:
		var lock_l := Label.new()
		lock_l.text = "Find cards in lootboxes to recruit this manager."
		lock_l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		lock_l.add_theme_color_override("font_color", LOCKED)
		box.add_child(lock_l)
		return
	# level up button
	var lvl_btn := UI.make_button("", SLATE)
	lvl_btn.icon = UI.icon_texture("insight", 20)
	var capped: bool = ManagerSystem.level(id) >= int(def.get("level_cap", 50))
	if capped:
		lvl_btn.text = "Level Up — MAX LEVEL"
		lvl_btn.disabled = true
	else:
		lvl_btn.text = "Level Up — %s Insight" % ManagerSystem.level_up_cost(id).to_notation()
		lvl_btn.disabled = not ManagerSystem.can_level_up(id)
	lvl_btn.pressed.connect(func() -> void:
		if ManagerSystem.level_up(id):
			_rebuild_detail(id))
	box.add_child(lvl_btn)
	# rank up button
	var rank_btn := UI.make_button("", PLUM)
	rank_btn.icon = UI.icon_texture("star", 20)
	var dup_cost: int = ManagerSystem.rank_up_cost(id)
	if dup_cost <= 0:
		rank_btn.text = "Rank Up — MAX RANK"
		rank_btn.disabled = true
	else:
		rank_btn.text = "Rank Up — %d cards (have %d)" % [dup_cost, ManagerSystem.cards(id)]
		rank_btn.disabled = not ManagerSystem.can_rank_up(id)
	rank_btn.pressed.connect(func() -> void:
		if ManagerSystem.rank_up(id):
			_rebuild_detail(id))
	box.add_child(rank_btn)
	# assign row: 4 dept buttons; only the specialty department actually works
	var assign_l := Label.new()
	assign_l.text = "Assign to department:"
	assign_l.add_theme_color_override("font_color", INK)
	box.add_child(assign_l)
	var assign_row := HBoxContainer.new()
	assign_row.add_theme_constant_override("separation", 6)
	box.add_child(assign_row)
	for dept_id in ManagerSystem.DEPTS:
		var b := UI.make_button("", DEPT_COLORS.get(dept_id, LOCKED))
		b.add_theme_font_size_override("font_size", 17)
		var is_specialty: bool = dept_id == specialty
		var is_current: bool = ManagerSystem.assigned_to(id) == dept_id
		b.text = str(dept_id).capitalize().substr(0, 4) + (" [ON]" if is_current else "")
		b.disabled = not is_specialty
		if is_specialty:
			b.tooltip_text = "Specialty department"
		var did: String = dept_id
		b.pressed.connect(func() -> void:
			if ManagerSystem.assigned_to(id) == did:
				ManagerSystem.unassign(id)
			else:
				ManagerSystem.assign(id, did)
			_rebuild_detail(id))
		assign_row.add_child(b)
	# exchange
	var ex_btn := Button.new()
	ex_btn.text = "Exchange cards (%d:1, same rarity)" % ManagerSystem.exchange_ratio()
	ex_btn.pressed.connect(func() -> void: _open_exchange(id))
	box.add_child(ex_btn)

func _open_exchange(from_id: String) -> void:
	var def: Dictionary = DataLoader.get_manager_def(from_id)
	var rarity: String = str(def.get("rarity", "common"))
	var dlg := Control.new()
	dlg.set_anchors_preset(Control.PRESET_FULL_RECT)
	_overlay.add_child(dlg)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.4)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dlg.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	dlg.add_child(center)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(600, 0)
	panel.add_theme_stylebox_override("panel", _style(PANEL, ACCENT, 12, 3))
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
	note.add_theme_color_override("font_color", INK.lightened(0.2))
	box.add_child(note)
	for tid in _sorted_ids():
		if tid == from_id:
			continue
		var td: Dictionary = DataLoader.get_manager_def(tid)
		if str(td.get("rarity", "")) != rarity:
			continue
		var b := UI.make_button("%s  (%d cards owned)" % [str(td.get("name", tid)), ManagerSystem.cards(tid)], SLATE)
		b.add_theme_font_size_override("font_size", 18)
		b.disabled = not ManagerSystem.can_exchange(from_id, tid)
		var target: String = tid
		b.pressed.connect(func() -> void:
			if ManagerSystem.exchange(from_id, target):
				dlg.queue_free()
				_rebuild_detail(from_id))
		box.add_child(b)
	var cancel := UI.make_button("Cancel", LOCKED)
	cancel.pressed.connect(func() -> void: dlg.queue_free())
	box.add_child(cancel)
