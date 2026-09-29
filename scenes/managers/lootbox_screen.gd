extends Control
## LootboxScreen — 3 lootbox tiers with published drop rates (SPEC §4, §11).
## Owns the "free_lootbox" RV charge logic (5 charges, +1 every 2h) per SPEC §8.
## UI built fully in code; visuals via ui_kit v2 (Kenney CC0 skin). Logic unchanged.

const LootboxSystem := preload("res://scripts/managers/lootbox_system.gd")
const UI := preload("res://scripts/ui/ui_kit.gd")
const Chrome := preload("res://scripts/ui/museum_chrome.gd")
const ManagerBadge := preload("res://scenes/managers/manager_badge.gd")
const ManagerPortrait := preload("res://scenes/managers/manager_portrait.gd")

# Popup CONTENT on a DARK page: the tier cards and the reveal are the bright
# things here, so the ground behind them is deep and the body text is light.
const BG := Chrome.BG
const INK := Chrome.INK
const DIM := Chrome.DIM
const PANEL := Chrome.PANEL
const ACCENT := Chrome.TEAL
const BRASS := Chrome.BRASS
const SAGE := Chrome.TEAL
const SLATE := Chrome.DIM
const PLUM := Chrome.BRASS
# Was a private copy of the retired muted palette; ui_kit is the source now.
const RARITY_COLORS := ManagerBadge.RARITY_TINTS
const RV_PLACEMENT := "free_lootbox"
const FIELD_BOX := "field_case"

var _payload: Dictionary = {}
var _rng := RandomNumberGenerator.new()
var _gems_chip: PanelContainer
var _box_list: VBoxContainer
var _refresh_timer: Timer
var _tier_controls: Dictionary = {} # box_id -> stable card/price/open controls

func setup(payload: Dictionary) -> void:
	_payload = payload

func _ready() -> void:
	_rng.randomize()
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.color = BG
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		margin.add_theme_constant_override(side, 16)
	add_child(margin)
	var root_box := VBoxContainer.new()
	root_box.add_theme_constant_override("separation", 12)
	margin.add_child(root_box)
	# header
	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 12)
	root_box.add_child(bar)
	var title := UI.make_display_label("Recruitment Cases", 36, INK)
	bar.add_child(title)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.add_child(spacer)
	_gems_chip = UI.make_dark_currency_chip("gems", "0", Color(1, 1, 1), 26)
	_gems_chip.add_theme_stylebox_override("panel", Chrome.panel(12))
	bar.add_child(_gems_chip)
	var intro := UI.make_label(
		"Open cases to recruit managers and collect duplicates for rank-ups and trades.",
		UI.TYPE_BODY)
	intro.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	intro.add_theme_color_override("font_color", DIM)
	root_box.add_child(intro)
	# tier list
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root_box.add_child(scroll)
	_box_list = VBoxContainer.new()
	_box_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_box_list.add_theme_constant_override("separation", 12)
	scroll.add_child(_box_list)
	# signals
	EventBus.gems_changed.connect(func(_v: int) -> void: _refresh_status())
	EventBus.lootbox_opened.connect(func(_b: String, _r: Dictionary) -> void: _refresh_status())
	AdService.ad_result.connect(_on_ad_result)
	_refresh_timer = Timer.new()
	_refresh_timer.wait_time = 1.0
	_refresh_timer.timeout.connect(_refresh_status)
	add_child(_refresh_timer)
	_refresh_timer.start()
	_build_boxes()
	_refresh_status()

## Framed tier card: dark stock, saturated rim. The rim used to be the whole
## card — a near-white panel washed with 16% of the tier colour — which on a dark
## page was a sheet of paper with a hint of tint rather than a lootbox.
func _style(bg_color: Color, border_color: Color, _radius: int = 12, border_w: int = 3) -> StyleBox:
	var sb := Chrome.panel(_radius, bg_color)
	sb.border_color = border_color.lerp(Chrome.BORDER, 0.45)
	sb.set_border_width_all(2 if border_w >= 4 else 1)
	sb.set_content_margin_all(12)
	return sb

static func _case_button(text: String, tint: Color) -> Button:
	var button := UI.make_button(text, tint)
	button.custom_minimum_size.y = UI.TOUCH_MIN
	button.expand_icon = true
	button.add_theme_constant_override("icon_max_width", 20)
	button.add_theme_constant_override("outline_size", 0)
	Chrome.button(button, tint != SLATE)
	return button

## --- free_lootbox charge logic (owned here per SPEC §8) ------------------------

func _rv_config() -> Dictionary:
	return DataLoader.get_lootbox(FIELD_BOX).get("rv_free", {"max": 5, "recharge_hours": 2})

func _max_charges() -> int:
	return int(_rv_config().get("max", 5))

func _recharge_seconds() -> int:
	return int(float(_rv_config().get("recharge_hours", 2)) * 3600.0)

## Charge state in GameState.rv_state["free_lootbox"]:
## {count:int, day:"YYYY-MM-DD", ready_at:unix}. Grants up to max charges;
## while below max, +1 charge every recharge_hours tracked via ready_at.
func charge_state() -> Dictionary:
	var maxc := _max_charges()
	var now := ClockGuard.now()
	var st: Dictionary = GameState.rv_state.get(RV_PLACEMENT, {})
	if st.is_empty():
		st = {"count": maxc, "day": Time.get_date_string_from_system(), "ready_at": 0}
		GameState.rv_state[RV_PLACEMENT] = st
		return st
	var count := clampi(int(st.get("count", 0)), 0, maxc)
	var ready_at := int(st.get("ready_at", 0))
	if count < maxc:
		if ready_at <= 0:
			ready_at = now + _recharge_seconds()
		elif now >= ready_at:
			var gained := int((now - ready_at) / _recharge_seconds()) + 1
			count = mini(count + gained, maxc)
			ready_at = 0 if count >= maxc else ready_at + gained * _recharge_seconds()
	else:
		ready_at = 0
	st["count"] = count
	st["ready_at"] = ready_at
	st["day"] = Time.get_date_string_from_system()
	return st

func _consume_charge() -> bool:
	var st: Dictionary = charge_state()
	if int(st.get("count", 0)) <= 0:
		return false
	st["count"] = int(st["count"]) - 1
	if int(st["count"]) < _max_charges() and int(st.get("ready_at", 0)) <= 0:
		st["ready_at"] = ClockGuard.now() + _recharge_seconds()
	st["day"] = Time.get_date_string_from_system()
	return true

func _next_charge_text() -> String:
	var st: Dictionary = charge_state()
	if int(st.get("count", 0)) >= _max_charges():
		return ""
	var secs: int = maxi(int(st.get("ready_at", 0)) - ClockGuard.now(), 0)
	return tr("Next free charge in %d:%02d") % [secs / 3600, (secs % 3600) / 60]

## --- tier cards ---------------------------------------------------------------

func _sorted_boxes() -> Array[String]:
	var ids: Array[String] = []
	for id in DataLoader.lootboxes.keys():
		ids.append(id)
	ids.sort_custom(func(a: String, b: String) -> bool:
		return int(DataLoader.get_lootbox(a).get("tier", 0)) < int(DataLoader.get_lootbox(b).get("tier", 0)))
	return ids

func _build_boxes() -> void:
	_tier_controls.clear()
	for box_id in _sorted_boxes():
		var entry := _build_tier_card(box_id)
		_box_list.add_child(entry["card"])
		_tier_controls[box_id] = entry

## Currency, countdown and affordance text change in place. Keeping cards and
## buttons mounted preserves keyboard/controller focus and an in-progress press.
func _refresh_status() -> void:
	if is_instance_valid(_gems_chip):
		UI.set_chip_value(_gems_chip, "%d" % GameState.gems)
	for box_id in _tier_controls.keys():
		var controls: Dictionary = _tier_controls[box_id]
		var price_l: Label = controls["price"]
		var open_btn: Button = controls["open"]
		if not is_instance_valid(price_l) or not is_instance_valid(open_btn):
			continue
		if box_id == FIELD_BOX:
			var count := int(charge_state().get("count", 0))
			price_l.text = tr("FREE %d/%d") % [count, _max_charges()]
			var next := _next_charge_text()
			if next != "":
				price_l.text += "   (%s)" % next
			open_btn.text = "Open (watch ad)" if count > 0 else "Recharging — tap for details"
		else:
			var price := int(DataLoader.get_lootbox(box_id).get("price_gems", 0))
			price_l.text = tr("%d Gems") % price
			open_btn.text = "Buy & Open" if GameState.gems >= price else tr("Need %d Gems") % price
		# Blocked actions stay live: their handlers explain the exact reason.
		open_btn.disabled = false

func _build_tier_card(box_id: String) -> Dictionary:
	var def: Dictionary = DataLoader.get_lootbox(box_id)
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", _style(PANEL, ACCENT if box_id != FIELD_BOX else SAGE, 12, 3))
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	card.add_child(box)
	var name_l := Label.new()
	name_l.text = str(def.get("name", box_id))
	UI.apply_display_font(name_l, name_l.text)
	name_l.add_theme_font_size_override("font_size", 28)
	name_l.add_theme_color_override("font_color", INK)
	box.add_child(name_l)
	var desc := Label.new()
	desc.text = tr("%d manager cards  ·  +%s Insight  ·  +%d Gems") % [
		int(def.get("cards_total", 0)),
		BigNumber.from_float(float(def.get("insight_bonus_m", 0.0))).to_notation(),
		int(def.get("gems_bonus", 0))]
	desc.add_theme_font_size_override("font_size", 18)
	desc.add_theme_color_override("font_color", DIM)
	box.add_child(desc)
	var odds := Label.new()
	odds.text = tr("Published odds: %s") % LootboxSystem.rates_text(box_id)
	odds.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	odds.add_theme_font_size_override("font_size", 16)
	odds.add_theme_color_override("font_color", SLATE)
	box.add_child(odds)
	# price / free-charge line
	var price_l := Label.new()
	price_l.add_theme_font_size_override("font_size", 20)
	price_l.add_theme_color_override("font_color", BRASS)
	if box_id == FIELD_BOX:
		price_l.text = "FREE"
	else:
		price_l.text = tr("%d Gems") % int(def.get("price_gems", 0))
	box.add_child(price_l)
	# buttons row
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	box.add_child(row)
	var rates_btn := _case_button("Drop rates", SLATE)
	rates_btn.icon = UI.icon_texture("question", 18)
	rates_btn.add_theme_font_size_override("font_size", 18)
	rates_btn.pressed.connect(func() -> void: _show_rates(box_id))
	row.add_child(rates_btn)
	var open_btn := _case_button("", SAGE if box_id == FIELD_BOX else BRASS)
	open_btn.add_theme_font_size_override("font_size", 20)
	if box_id == FIELD_BOX:
		open_btn.text = "Open (watch ad)"
		open_btn.pressed.connect(_open_field_free)
	else:
		open_btn.text = "Buy & Open"
		open_btn.icon = UI.icon_texture("gems", 20)
		open_btn.pressed.connect(func() -> void: _open_with_gems(box_id))
	open_btn.set_meta("box_id", box_id)
	row.add_child(open_btn)
	return {"card": card, "price": price_l, "open": open_btn, "rates": rates_btn,
		"odds": odds}

## --- open flows ---------------------------------------------------------------

func _open_with_gems(box_id: String) -> void:
	var price := int(DataLoader.get_lootbox(box_id).get("price_gems", 0))
	if not GameState.spend_gems(price):
		EventBus.toast_requested.emit("Not enough gems")
		return
	_show_reveal(box_id, LootboxSystem.open_box(box_id, _rng))

func _open_field_free() -> void:
	if int(charge_state().get("count", 0)) <= 0:
		EventBus.toast_requested.emit("No free cases left — recharging")
		return
	if not AdService.is_ready(RV_PLACEMENT):
		EventBus.toast_requested.emit("Ad unavailable")
		return
	AdService.show_rewarded(RV_PLACEMENT)

func _on_ad_result(placement_id: String, success: bool, _context: Dictionary) -> void:
	if placement_id != RV_PLACEMENT:
		return
	if not success:
		EventBus.toast_requested.emit("Ad unavailable")
		return
	if not _consume_charge():
		return
	var results: Dictionary = LootboxSystem.open_box(FIELD_BOX, _rng)
	EventBus.rv_reward_granted.emit(RV_PLACEMENT, {"box_id": FIELD_BOX})
	Analytics.rv_impression(RV_PLACEMENT)
	_show_reveal(FIELD_BOX, results)

## --- popups -------------------------------------------------------------------

func _popup_panel(border_color: Color) -> Dictionary:
	var dlg := Control.new()
	dlg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(dlg)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.62)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dlg.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	dlg.add_child(center)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(620, 0)
	panel.add_theme_stylebox_override("panel", _style(PANEL, border_color, 12, 4))
	center.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	panel.add_child(box)
	return {"dlg": dlg, "box": box}

func _show_rates(box_id: String) -> void:
	var def: Dictionary = DataLoader.get_lootbox(box_id)
	var p: Dictionary = _popup_panel(SLATE)
	var box: VBoxContainer = p["box"]
	var title := Label.new()
	title.text = tr("%s — published drop rates") % tr(str(def.get("name", box_id)))
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	title.add_theme_font_size_override("font_size", 22)
	title.add_theme_color_override("font_color", INK)
	box.add_child(title)
	var rates := Label.new()
	rates.text = LootboxSystem.rates_text(box_id)
	rates.add_theme_font_size_override("font_size", 20)
	rates.add_theme_color_override("font_color", INK)
	rates.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(rates)
	var close := _case_button("Close", SLATE)
	close.pressed.connect(func() -> void: (p["dlg"] as Control).queue_free())
	box.add_child(close)

func _show_reveal(box_id: String, results: Dictionary) -> void:
	var p: Dictionary = _popup_panel(BRASS)
	var dlg: Control = p["dlg"]
	var box: VBoxContainer = p["box"]
	UI.play_sfx(self, "buy")
	var title := Label.new()
	title.text = tr("%s opened!") % tr(str(DataLoader.get_lootbox(box_id).get("name", box_id)))
	UI.apply_display_font(title, title.text)
	title.add_theme_font_size_override("font_size", 26)
	title.add_theme_color_override("font_color", INK)
	box.add_child(title)
	# A reveal shows the FACE. The roster is a wall of ID photos now, so a won
	# manager arriving as a coloured line of text was the one place the player
	# met someone new and never saw them. The portrait comes out of the same
	# authored texture cache the badges fill, so a reveal needs no live render.
	var rows: Array[Control] = []
	for entry in results.get("cards", []):
		var def: Dictionary = DataLoader.get_manager_def(str(entry.get("id", "")))
		var rarity: String = str(def.get("rarity", "common"))
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		var photo := ManagerPortrait.new()
		row.add_child(photo)
		photo.setup(def, 64, true)
		var text := VBoxContainer.new()
		text.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		text.add_theme_constant_override("separation", 2)
		row.add_child(text)
		text.add_child(UI.make_display_label("%dx  %s" % [
			int(entry.get("n", 1)), str(def.get("name", entry.get("id", "?")))],
			UI.TYPE_HEADING, INK))
		text.add_child(ManagerBadge.pill(ManagerBadge.rarity_name(rarity).to_upper(),
			RARITY_COLORS.get(rarity, UI.LOCKED)))
		row.visible = false
		box.add_child(row)
		rows.append(row)
	var bonus := Label.new()
	bonus.text = tr("Bonus: +%s Insight  ·  +%d Gems") % [
		(results.get("insight", BigNumber.zero()) as BigNumber).to_notation(),
		int(results.get("gems", 0))]
	bonus.add_theme_font_size_override("font_size", 20)
	bonus.add_theme_color_override("font_color", BRASS)
	bonus.visible = false
	box.add_child(bonus)
	var close := _case_button("...", BRASS)
	close.disabled = true
	close.pressed.connect(func() -> void: dlg.queue_free())
	box.add_child(close)
	_stage_reveal(rows, bonus, close)

func _stage_reveal(rows: Array[Control], bonus: Label, close: Button) -> void:
	for row in rows:
		if not is_instance_valid(row):
			return
		row.visible = true
		await get_tree().create_timer(0.22).timeout
	if not is_instance_valid(bonus):
		return
	bonus.visible = true
	close.text = "Collect"
	close.disabled = false
