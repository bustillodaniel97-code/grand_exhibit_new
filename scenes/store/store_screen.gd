extends Control
## store_screen.gd — Store screen (SPEC §11 registry path). Built entirely in code
## per SPEC §2 (StyleBoxFlat, no theme, palette hardcoded — do NOT import ui_kit).
## PopupManager calls setup(payload) after instantiation.
##
## Sections: Offers banner row / Daily Deals shelf / Gem Packs / Cash & Insight /
## RV corner. All purchases route through iap_catalog.purchase; all ads through
## rv_placements; offers/deals through offer_system / daily_deals.

const RV := preload("res://scripts/monetization/rv_placements.gd")
const IAPCat := preload("res://scripts/monetization/iap_catalog.gd")
const Deals := preload("res://scripts/monetization/daily_deals.gd")
const Offers := preload("res://scripts/monetization/offer_system.gd")

# Palette (SPEC §2 hex values, hardcoded on purpose)
const BG := Color("#F5EFE0")
const INK := Color("#33312E")
const PANEL := Color("#FFFDF6")
const ACCENT := Color("#C4703F")
const BRASS := Color("#B08D3E")
const SAGE := Color("#7A9B76")
const SLATE := Color("#5B7B8C")
const PLUM := Color("#8E6C8A")

var _sections: VBoxContainer
var _tick_labels: Array = []  # Array of {label:Label, kind:String, data:Variant}

func _ready() -> void:
	var bg := ColorRect.new()
	bg.color = BG
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var scroll := ScrollContainer.new()
	scroll.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(scroll)

	_sections = VBoxContainer.new()
	_sections.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_sections.add_theme_constant_override("separation", 14)
	scroll.add_child(_sections)

	EventBus.iap_completed.connect(_on_iap_completed)
	EventBus.daily_deals_refreshed.connect(_rebuild)
	EventBus.rv_reward_granted.connect(func(_p: String, _c: Dictionary) -> void: _rebuild())
	EventBus.boost_changed.connect(func(_m: float, _s: int) -> void: _rebuild())

	var timer := Timer.new()
	timer.wait_time = 1.0
	timer.autostart = true
	timer.timeout.connect(_tick)
	add_child(timer)

	_rebuild()

func setup(_payload: Dictionary) -> void:
	Offers.check_triggers()
	if is_node_ready():
		_rebuild()

# ------------------------------------------------------------------- rebuild

func _rebuild() -> void:
	if not is_node_ready():
		return
	_tick_labels.clear()
	for child in _sections.get_children():
		child.queue_free()
	_sections.add_child(_title("Grand Exhibit Store"))
	_build_offers()
	_build_daily_deals()
	_build_gem_packs()
	_build_cash_insight()
	_build_rv_corner()

func _tick() -> void:
	for entry in _tick_labels:
		var label: Label = entry["label"]
		if not is_instance_valid(label):
			continue
		match str(entry["kind"]):
			"offer_expiry":
				label.text = "Expires in " + _fmt_duration(Offers.seconds_left(str(entry["data"])))
			"deals_refresh":
				label.text = "New deals in " + _fmt_duration(Deals.seconds_until_refresh())
			"boost_timer":
				label.text = _boost_text()
			"cash_worth":
				var def: Dictionary = DataLoader.get_iap(str(entry["data"]))
				label.text = _cash_worth_text(def)
			"instant_cash":
				label.text = "+" + RV.instant_cash_value().to_notation() + " cash"

# ------------------------------------------------------------------- sections

func _build_offers() -> void:
	var offers: Array = Offers.active_offers()
	if offers.is_empty():
		return
	_sections.add_child(_section_header("Special Offers"))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	_sections.add_child(row)
	for offer in offers:
		row.add_child(_offer_card(offer))

func _offer_card(offer: Dictionary) -> Control:
	var offer_id: String = str(offer["id"])
	var def: Dictionary = DataLoader.get_iap(str(offer.get("iap_id", "")))
	var card := _panel(BRASS)
	card.custom_minimum_size = Vector2(300, 0)
	var vbox := VBoxContainer.new()
	card.add_child(vbox)
	var name_label := _label(str(def.get("title", offer_id)), 20, INK)
	vbox.add_child(name_label)
	# discount_pct is display-only: debug IAP price is the unchanged catalog price.
	var badge := _label("SAVE %d%%" % int(offer.get("discount_pct", 0)), 18, ACCENT)
	vbox.add_child(badge)
	vbox.add_child(_label(_grants_text(def), 14, SLATE))
	var expiry := _label("", 14, PLUM)
	vbox.add_child(expiry)
	_tick_labels.append({"label": expiry, "kind": "offer_expiry", "data": offer_id})
	var buy := _button("Buy  " + IAPService.localized_price(str(offer.get("iap_id", ""))), ACCENT)
	buy.pressed.connect(func() -> void: Offers.buy(offer_id))
	vbox.add_child(buy)
	return card

func _build_daily_deals() -> void:
	_sections.add_child(_section_header("Daily Deals"))
	var header_row := HBoxContainer.new()
	_sections.add_child(header_row)
	var countdown := _label("", 14, SLATE)
	header_row.add_child(countdown)
	_tick_labels.append({"label": countdown, "kind": "deals_refresh", "data": null})
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header_row.add_child(spacer)
	var force := _button("Refresh (%d gems, %d left)" % [Deals.force_cost(), Deals.force_refreshes_left()], SLATE)
	force.pressed.connect(func() -> void: Deals.force_refresh())
	header_row.add_child(force)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	_sections.add_child(row)
	for pid in Deals.shelf():
		row.add_child(_product_card(str(pid)))

func _build_gem_packs() -> void:
	_sections.add_child(_section_header("Gem Packs"))
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 10)
	_sections.add_child(grid)
	for pid in _products_where(func(def: Dictionary) -> bool:
		return str(def.get("kind", "")) == "gems" and str(def.get("tag", "")) == "regular"):
		grid.add_child(_product_card(pid))

func _build_cash_insight() -> void:
	_sections.add_child(_section_header("Cash & Insight"))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	_sections.add_child(row)
	for pid in _products_where(func(def: Dictionary) -> bool:
		return str(def.get("kind", "")) in ["cash_pack", "insight_pack"] and str(def.get("tag", "")) == "regular"):
		row.add_child(_product_card(pid))

func _build_rv_corner() -> void:
	_sections.add_child(_section_header("Free Rewards (Watch an Ad)"))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	_sections.add_child(row)

	var cash_card := _panel(SAGE)
	var cv := VBoxContainer.new()
	cash_card.add_child(cv)
	cv.add_child(_label("Instant Cash", 18, INK))
	var cash_val := _label("", 14, SLATE)
	cv.add_child(cash_val)
	_tick_labels.append({"label": cash_val, "kind": "instant_cash", "data": null})
	var cash_btn := _button("Watch Ad", SAGE)
	cash_btn.pressed.connect(func() -> void: RV.instant_cash())
	cv.add_child(cash_btn)
	row.add_child(cash_card)

	var gems_card := _panel(SAGE)
	var gv := VBoxContainer.new()
	gems_card.add_child(gv)
	gv.add_child(_label("Free Gems", 18, INK))
	gv.add_child(_label("%d left today" % RV.remaining_free_gems(), 14, SLATE))
	var gems_btn := _button("Watch Ad", SAGE)
	gems_btn.disabled = RV.remaining_free_gems() <= 0
	gems_btn.pressed.connect(func() -> void: RV.free_gems())
	gv.add_child(gems_btn)
	row.add_child(gems_card)

	var boost_card := _panel(SAGE)
	var bv := VBoxContainer.new()
	boost_card.add_child(bv)
	bv.add_child(_label("x2 Income", 18, INK))
	var boost_lbl := _label(_boost_text(), 14, SLATE)
	bv.add_child(boost_lbl)
	_tick_labels.append({"label": boost_lbl, "kind": "boost_timer", "data": null})
	var boost_btn := _button("Watch Ad", SAGE)
	boost_btn.pressed.connect(func() -> void: RV.income_x2())
	bv.add_child(boost_btn)
	row.add_child(boost_card)

# ------------------------------------------------------------------ widgets

func _product_card(pid: String) -> Control:
	var def: Dictionary = DataLoader.get_iap(pid)
	var card := _panel(PANEL, ACCENT)
	card.custom_minimum_size = Vector2(300, 0)
	var vbox := VBoxContainer.new()
	card.add_child(vbox)
	vbox.add_child(_label(str(def.get("title", pid)), 18, INK))
	if str(def.get("kind", "")) == "cash_pack":
		var worth := _label(_cash_worth_text(def), 14, SLATE)
		vbox.add_child(worth)
		_tick_labels.append({"label": worth, "kind": "cash_worth", "data": pid})
	else:
		vbox.add_child(_label(_grants_text(def), 14, SLATE))
	var left: int = IAPCat.purchases_left_today(pid)
	var buy := _button(IAPService.localized_price(pid), ACCENT)
	if left == 0:
		buy.disabled = true
		buy.text = "Bought today"
	buy.pressed.connect(func() -> void: IAPCat.purchase(pid))
	vbox.add_child(buy)
	return card

func _on_iap_completed(product_id: String) -> void:
	var def: Dictionary = DataLoader.get_iap(product_id)
	EventBus.toast_requested.emit("Purchased: " + str(def.get("title", product_id)))
	_rebuild()

# ------------------------------------------------------------------- helpers

func _products_where(pred: Callable) -> Array:
	var out: Array = []
	for pid in DataLoader.iap_products.keys():
		if pred.call(DataLoader.iap_products[pid]):
			out.append(pid)
	out.sort_custom(func(a: String, b: String) -> bool:
		return _price_num(DataLoader.get_iap(a)) < _price_num(DataLoader.get_iap(b)))
	return out

func _price_num(def: Dictionary) -> float:
	return str(def.get("price_usd", "$0")).trim_prefix("$").to_float()

func _grants_text(def: Dictionary) -> String:
	var g: Dictionary = def.get("grants", {})
	var parts: Array = []
	if int(g.get("gems", 0)) > 0:
		parts.append("%d gems" % int(g["gems"]))
	if float(g.get("cash_seconds", 0)) > 0.0:
		parts.append("%s of income" % _fmt_duration(int(g["cash_seconds"])))
	if float(g.get("insight_m", 0.0)) > 0.0:
		parts.append(BigNumber.from_parts(float(g["insight_m"]), int(g.get("insight_e", 0))).to_notation() + " insight")
	if str(g.get("box", "")) != "":
		parts.append(str(DataLoader.get_lootbox(str(g["box"])).get("name", str(g["box"]))))
	return " + ".join(parts)

func _cash_worth_text(def: Dictionary) -> String:
	var secs: float = float(def.get("grants", {}).get("cash_seconds", 0))
	var worth: BigNumber = Economy.current_cash_per_second().scale(secs)
	return "Worth " + worth.to_notation() + " cash now"

func _boost_text() -> String:
	var rem: int = RV.income_x2_remaining_seconds()
	if rem <= 0:
		return "No active boost"
	return "Active: " + _fmt_duration(rem) + " left"

func _fmt_duration(seconds: int) -> String:
	seconds = maxi(seconds, 0)
	var h: int = seconds / 3600
	var m: int = (seconds % 3600) / 60
	var s: int = seconds % 60
	if h > 0:
		return "%dh %02dm" % [h, m]
	if m > 0:
		return "%dm %02ds" % [m, s]
	return "%ds" % s

func _title(text: String) -> Label:
	return _label(text, 28, INK)

func _section_header(text: String) -> Label:
	return _label(text, 22, ACCENT)

func _label(text: String, size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l

func _panel(fill: Color, border: Color = Color(0, 0, 0, 0)) -> PanelContainer:
	var p := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = fill
	sb.set_corner_radius_all(12)
	sb.content_margin_left = 12
	sb.content_margin_right = 12
	sb.content_margin_top = 10
	sb.content_margin_bottom = 10
	if border.a > 0.0:
		sb.border_color = border
		sb.set_border_width_all(3)
	p.add_theme_stylebox_override("panel", sb)
	return p

func _button(text: String, color: Color) -> Button:
	var b := Button.new()
	b.text = text
	var sb := StyleBoxFlat.new()
	sb.bg_color = color
	sb.set_corner_radius_all(12)
	sb.content_margin_left = 14
	sb.content_margin_right = 14
	sb.content_margin_top = 8
	sb.content_margin_bottom = 8
	b.add_theme_stylebox_override("normal", sb)
	var hover := sb.duplicate() as StyleBoxFlat
	hover.bg_color = color.lightened(0.12)
	b.add_theme_stylebox_override("hover", hover)
	var disabled := sb.duplicate() as StyleBoxFlat
	disabled.bg_color = color.darkened(0.3)
	b.add_theme_stylebox_override("disabled", disabled)
	b.add_theme_color_override("font_color", PANEL)
	return b
