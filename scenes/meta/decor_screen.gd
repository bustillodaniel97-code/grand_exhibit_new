extends Control
## DecorScreen — venue decor slots + shop (SPEC §6.3, §11). UI built in code.
## setup(payload): {"venue_id": String?} — defaults to GameState.current_venue.

const DecorSystem = preload("res://scripts/meta/decor_system.gd")
const UI = preload("res://scripts/ui/ui_kit.gd")

# Palette aliases (ui_kit is the single source — SPEC §2).
# Popup CONTENT on a DARK page. DIM is the muted ink for locked / empty states;
# it used to be a pale beige, which on this page would out-shout the live rows.
const BG := UI.PAGE
const INK := UI.TEXT
const PANEL := UI.CARD
const ACCENT := UI.ACCENT
const BRASS := UI.BRASS
const SAGE := UI.SAGE
const SLATE := UI.SLATE
const DIM := UI.TEXT_MUTE

const THEME_ORDER: Array = ["entrance", "hall", "garden"]

var _venue_id: String = ""
var _list: VBoxContainer
var _rating_box: VBoxContainer

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
	var title := UI.make_display_label("", 26, INK)
	title.name = "Title"
	vbox.add_child(title)
	# The rating panel is PINNED above the scroll, not the first row inside it.
	# It is the reason the player opened this screen — "why am I on 3 stars" —
	# and it has to stay legible while they scroll the shop looking for the fix.
	var rating_card := _panel()
	_rating_box = VBoxContainer.new()
	_rating_box.add_theme_constant_override("separation", 6)
	rating_card.add_child(_rating_box)
	vbox.add_child(rating_card)
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
	_build_rating()
	_build_slots()
	_build_sets_summary()
	_build_shop()

func _header(text: String) -> Label:
	return UI.make_display_label(text, 20, ACCENT)

func _panel() -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", UI.make_dark_card(PANEL))
	return p

## Recessed well for empty decor slots.
func _inset_panel() -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", UI.make_dark_inset())
	return p

func _label(text: String, size: int = 15, color: Color = INK) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_color_override("font_color", color)
	l.add_theme_font_size_override("font_size", size)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return l

## Venue rating breakdown. Three bars, one per input, with the input costing the
## most stars called out by name — "you are at 3 stars because your queues are
## slow" is the whole point, so the sentence comes before the numbers.
func _build_rating() -> void:
	if _rating_box == null:
		return
	for c in _rating_box.get_children():
		c.queue_free()
	var sat: Dictionary = Economy.venue_satisfaction(_venue_id)

	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 6)
	_rating_box.add_child(head)
	var stars: float = float(sat["stars_rounded"])
	for i in range(5):
		var tint: Color = UI.LOCKED
		if stars >= float(i) + 1.0:
			tint = BRASS
		elif stars >= float(i) + 0.5:
			tint = BRASS.lerp(UI.LOCKED, 0.5)
		head.add_child(UI.make_icon("star", 22, tint))
	var score_l := UI.make_display_label("%.1f / 5" % float(sat["stars"]), 20, INK)
	score_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	score_l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	head.add_child(score_l)
	var mult: float = float(sat["income_mult"])
	var mult_l := UI.make_display_label("Visitors pay x%.2f" % mult, 18, SAGE if mult >= 1.0 else UI.DANGER)
	mult_l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	head.add_child(mult_l)

	var reason := _label(str(sat["reason"]), 14, ACCENT)
	_rating_box.add_child(reason)

	var inputs: Dictionary = sat["inputs"]
	for key in ["decor", "speed", "rest"]:
		var d: Dictionary = inputs[key]
		var limiting: bool = str(sat["limiting"]) == key and float(d["score"]) < 0.999
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		_rating_box.add_child(row)
		var name_l := _label(str(d["label"]), 14, ACCENT if limiting else INK)
		name_l.custom_minimum_size = Vector2(84, 0)
		name_l.autowrap_mode = TextServer.AUTOWRAP_OFF
		row.add_child(name_l)
		var bar := ProgressBar.new()
		bar.custom_minimum_size = Vector2(100, 14)
		bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		bar.max_value = 100.0
		bar.value = float(d["score"]) * 100.0
		bar.show_percentage = false
		bar.add_theme_stylebox_override("background", UI.make_channel())
		bar.add_theme_stylebox_override("fill", UI.make_bar_fill(_bar_kind(float(d["score"]))))
		row.add_child(bar)
		var detail := _label(str(d["detail"]), 13, SLATE if not limiting else ACCENT)
		detail.autowrap_mode = TextServer.AUTOWRAP_OFF
		detail.clip_text = true
		detail.custom_minimum_size = Vector2(212, 0)  # right-aligned + clipped eats the LEFT end
		detail.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		row.add_child(detail)

func _bar_kind(score: float) -> String:
	if score >= 0.85:
		return "green"
	if score >= 0.5:
		return "yellow"
	return "red"

## "+6 seats" tag — the second thing a piece is worth, and the only reason to
## give a slot to a bench instead of a chandelier.
func _seats_note(decor_id: String) -> String:
	var seats: int = DecorSystem.piece_rest_seats(decor_id)
	return " • +%d seats" % seats if seats > 0 else ""

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
		var did: String = str(placed.get(str(i), ""))
		var occupied: bool = did != "" and DataLoader.decor.has(did)
		var cell := _panel() if occupied else _inset_panel()
		cell.custom_minimum_size = Vector2(200, 92)
		cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var cv := VBoxContainer.new()
		cell.add_child(cv)
		if occupied:
			var def: Dictionary = DataLoader.decor[did]
			cv.add_child(_label(str(def.get("name", did)), 15, INK))
			cv.add_child(_label("%s • +%d%% income%s" % [
				str(def.get("slot_theme", "")).capitalize(),
				int(round((float(def.get("income_mult", 1.0)) - 1.0) * 100.0)),
				_seats_note(did)], 13, SAGE))
			cv.add_child(_label("%d decor pts" % int(round(DecorSystem.piece_decor_points(did))), 12, SLATE))
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
		var bonus_l := _label(bonus_text + (" — ACTIVE" if bool(sp["complete"]) else ""), 15,
			SAGE if bool(sp["complete"]) else SLATE)
		bonus_l.autowrap_mode = TextServer.AUTOWRAP_OFF  # squeezed by expand-fill name otherwise
		hb.add_child(bonus_l)
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
	# Rest areas get their own group: they are bought for a different reason than
	# every other piece (seats, not spectacle) and burying them under
	# "Curiosities" hides the only fix for a low rest-area rating.
	var loose: Array = []
	var rest_pieces: Array = []
	for did in DataLoader.decor.keys():
		if str(DataLoader.decor[did].get("set_id", "")) != "":
			continue
		if DecorSystem.piece_rest_seats(str(did)) > 0:
			rest_pieces.append(str(did))
		else:
			loose.append(str(did))
	groups.append({"name": "Rest Areas", "pieces": rest_pieces})
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
	var sub: String = "%s • +%d%% income • %d pts%s" % [
		str(def.get("slot_theme", "")).capitalize(),
		int(round((float(def.get("income_mult", 1.0)) - 1.0) * 100.0)),
		int(round(DecorSystem.piece_decor_points(decor_id))),
		_seats_note(decor_id)]
	if str(def.get("set_id", "")) != "":
		var set_def: Dictionary = DataLoader.decor_sets.get(str(def["set_id"]), {})
		sub += " • %s" % str(set_def.get("name", ""))
	info.add_child(_label(sub, 13, SLATE))
	if bool(def.get("event_exclusive", false)):
		info.add_child(_label("Expedition reward", 14, BRASS))
	elif DecorSystem.owned(_venue_id, decor_id):
		info.add_child(_label("Placed in this venue", 14, SAGE))
	else:
		var btn := UI.make_button("Buy — %s" % DecorSystem.cost_text(decor_id), SAGE)
		btn.add_theme_font_size_override("font_size", 18)
		btn.disabled = slots_full or not DecorSystem.can_afford(decor_id)
		btn.pressed.connect(func(): _on_buy(decor_id))
		hb.add_child(btn)
	return row

func _on_buy(decor_id: String) -> void:
	if DecorSystem.buy_decor(_venue_id, decor_id):
		EventBus.toast_requested.emit("Placed %s!" % str(DataLoader.get_decor(decor_id).get("name", decor_id)))
		UI.play_sfx(self, "buy")
	else:
		EventBus.toast_requested.emit("Can't buy that right now.")
	refresh()
