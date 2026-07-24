extends Control
## DecorScreen — venue decor slots + shop (SPEC §6.3, §11). UI built in code.
## setup(payload): {"venue_id": String?} — defaults to GameState.current_venue.

const DecorSystem = preload("res://scripts/meta/decor_system.gd")

# Palette (SPEC §2).
const BG := Color("#F5EFE0")
const INK := Color("#33312E")
const PANEL := Color("#FFFDF6")
const ACCENT := Color("#C4703F")
const BRASS := Color("#B08D3E")
const SAGE := Color("#7A9B76")
const SLATE := Color("#5B7B8C")
const DIM := Color("#D8CFC0")

const THEME_ORDER: Array = ["entrance", "hall", "garden"]

var _venue_id: String = ""
var _list: VBoxContainer

func setup(payload: Dictionary) -> void:
	_venue_id = str(payload.get("venue_id", GameState.current_venue))
	if is_inside_tree() and _list != null:  # setup may arrive after _ready
		refresh()

func _ready() -> void:
	if _venue_id == "":
		_venue_id = GameState.current_venue
	_build_shell()
	refresh()
	EventBus.decor_purchased.connect(func(_v, _d): refresh())
	EventBus.cash_changed.connect(func(_c): refresh())
	EventBus.gems_changed.connect(func(_g): refresh())

func _build_shell() -> void:
	var bg := ColorRect.new()
	bg.color = BG
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 16)
	margin.add_theme_constant_override("margin_right", 16)
	margin.add_theme_constant_override("margin_top", 16)
	margin.add_theme_constant_override("margin_bottom", 16)
	add_child(margin)
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	margin.add_child(vbox)
	var title := Label.new()
	title.add_theme_color_override("font_color", INK)
	title.add_theme_font_size_override("font_size", 26)
	title.name = "Title"
	vbox.add_child(title)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(scroll)
	_list = VBoxContainer.new()
	_list.add_theme_constant_override("separation", 10)
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_list)

func refresh() -> void:
	if not is_inside_tree() or _list == null:
		return
	var venue: Dictionary = DataLoader.get_venue(_venue_id)
	var title: Label = find_child("Title", true, false)
	if title:
		title.text = "Decor — %s" % str(venue.get("name", _venue_id))
	for c in _list.get_children():
		c.queue_free()
	_build_slots()
	_build_sets_summary()
	_build_shop()

func _header(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_color_override("font_color", ACCENT)
	l.add_theme_font_size_override("font_size", 20)
	return l

func _panel() -> PanelContainer:
	var p := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = PANEL
	sb.border_color = DIM
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(12)
	sb.content_margin_left = 10
	sb.content_margin_right = 10
	sb.content_margin_top = 8
	sb.content_margin_bottom = 8
	p.add_theme_stylebox_override("panel", sb)
	return p

func _label(text: String, size: int = 15, color: Color = INK) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_color_override("font_color", color)
	l.add_theme_font_size_override("font_size", size)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return l

func _build_slots() -> void:
	_list.add_child(_header("Exhibit Slots (%d/%d)" % [
		DecorSystem.slots_used(_venue_id), DecorSystem.slots_total(_venue_id)]))
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	_list.add_child(grid)
	var placed: Dictionary = GameState.venue_state(_venue_id).get("decor", {})
	for i in range(DecorSystem.slots_total(_venue_id)):
		var cell := _panel()
		cell.custom_minimum_size = Vector2(200, 92)
		cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var cv := VBoxContainer.new()
		cell.add_child(cv)
		var did: String = str(placed.get(str(i), ""))
		if did != "" and DataLoader.decor.has(did):
			var def: Dictionary = DataLoader.decor[did]
			cv.add_child(_label(str(def.get("name", did)), 15, INK))
			cv.add_child(_label("%s • +%d%% income" % [
				str(def.get("slot_theme", "")).capitalize(),
				int(round((float(def.get("income_mult", 1.0)) - 1.0) * 100.0))], 13, SAGE))
		else:
			cv.add_child(_label("Empty Slot", 15, DIM))
		grid.add_child(cell)

func _build_sets_summary() -> void:
	_list.add_child(_header("Sets"))
	for set_id in DataLoader.decor_sets.keys():
		var sp: Dictionary = DecorSystem.set_progress(str(set_id))
		var row := _panel()
		var hb := HBoxContainer.new()
		row.add_child(hb)
		var name_l := _label("%s  %d/%d" % [str(sp["name"]), int(sp["have"]), int(sp["total"])], 16, INK)
		name_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		hb.add_child(name_l)
		var bonus_text: String = "Bonus +%d%% income" % int(round((float(sp["bonus_mult"]) - 1.0) * 100.0))
		hb.add_child(_label(bonus_text + (" — ACTIVE" if bool(sp["complete"]) else ""), 15,
			SAGE if bool(sp["complete"]) else SLATE))
		_list.add_child(row)

func _build_shop() -> void:
	_list.add_child(_header("Shop"))
	var slots_full: bool = DecorSystem.first_free_slot(_venue_id) < 0
	if slots_full:
		_list.add_child(_label("All slots full in this venue.", 14, ACCENT))
	# Group defs by set, then unaffiliated pieces.
	var groups: Array = []
	for set_id in DataLoader.decor_sets.keys():
		groups.append({"name": str(DataLoader.decor_sets[set_id].get("name", set_id)),
			"pieces": DataLoader.decor_sets[set_id].get("pieces", [])})
	var loose: Array = []
	for did in DataLoader.decor.keys():
		if str(DataLoader.decor[did].get("set_id", "")) == "":
			loose.append(str(did))
	groups.append({"name": "Curiosities", "pieces": loose})
	for g in groups:
		_list.add_child(_label(str(g["name"]), 17, BRASS))
		for pid in g["pieces"]:
			_list.add_child(_shop_row(str(pid), slots_full))

func _shop_row(decor_id: String, slots_full: bool) -> PanelContainer:
	var def: Dictionary = DataLoader.get_decor(decor_id)
	var row := _panel()
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 10)
	row.add_child(hb)
	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hb.add_child(info)
	info.add_child(_label(str(def.get("name", decor_id)), 16, INK))
	var sub: String = "%s • +%d%% income" % [
		str(def.get("slot_theme", "")).capitalize(),
		int(round((float(def.get("income_mult", 1.0)) - 1.0) * 100.0))]
	if str(def.get("set_id", "")) != "":
		var set_def: Dictionary = DataLoader.decor_sets.get(str(def["set_id"]), {})
		sub += " • %s" % str(set_def.get("name", ""))
	info.add_child(_label(sub, 13, SLATE))
	if bool(def.get("event_exclusive", false)):
		info.add_child(_label("Expedition reward", 14, BRASS))
	elif DecorSystem.owned(_venue_id, decor_id):
		info.add_child(_label("Placed in this venue", 14, SAGE))
	else:
		var btn := Button.new()
		btn.text = "Buy — %s" % DecorSystem.cost_text(decor_id)
		btn.disabled = slots_full or not DecorSystem.can_afford(decor_id)
		btn.pressed.connect(func(): _on_buy(decor_id))
		hb.add_child(btn)
	return row

func _on_buy(decor_id: String) -> void:
	if DecorSystem.buy_decor(_venue_id, decor_id):
		EventBus.toast_requested.emit("Placed %s!" % str(DataLoader.get_decor(decor_id).get("name", decor_id)))
	else:
		EventBus.toast_requested.emit("Can't buy that right now.")
	refresh()
