extends Control
## store_screen.gd — the shopfront (SPEC §11 registry path). Built entirely in code.
## PopupManager calls setup(payload) after instantiation.
##
## v1 was an inventory list: eleven near-identical cards, every buy button the same
## orange pill at the same size, so $0.99 and $19.99 carried equal visual weight; a
## single offer marooned in a two-column grid left the entire right half of the most
## valuable screen region empty; and the three free-reward cards — the only things in
## here that cost the player nothing — were built last, a full screen below the fold.
##
## A persistent wallet and five category tabs keep navigation above the shelf.
## Each category remembers its scroll position; a rebuild preserves the active
## category and recovers product controls from the authoritative purchase state.
## Offers holds the hero, starter and daily shelf; Rewards, Gems, Resources and
## Passes each expose their own complete section. Product-view events are emitted
## once when their category is first shown, not while hidden panels are built.
##
## House rules honoured here:
##  · No button is disabled for affordability, ownership or a daily limit. It stays
##    tappable and explains by toast. An accepted purchase temporarily disables all
##    visible copies of that product so two cards cannot launch the same purchase.
##  · Every value claim is computed from the catalog (store_pricing.gd) and states
##    its basis on screen. No invented "most popular", no strikethrough without a
##    printed anchor, no countdown on something that does not actually expire.
##  · The page is the shared cream chrome with dark ink. The shop is the ground
##    the products stand on, so it stays out of the way and the gold, green and
##    violet on the cards do the selling.

const RV := preload("res://scripts/monetization/rv_placements.gd")
const IAPCat := preload("res://scripts/monetization/iap_catalog.gd")
const Deals := preload("res://scripts/monetization/daily_deals.gd")
const Offers := preload("res://scripts/monetization/offer_system.gd")
const Entitlements := preload("res://scripts/monetization/entitlements.gd")
const Pricing := preload("res://scripts/monetization/store_pricing.gd")
const Consent := preload("res://scripts/monetization/consent.gd")
const Art := preload("res://scripts/monetization/store_art.gd")
const UI := preload("res://scripts/ui/ui_kit.gd")
const Chrome := preload("res://scripts/ui/museum_chrome.gd")

# Toy-shop palette: the same warm cream chrome as every other screen, with
# saturated candy accents on the products so the cards do the selling.
const BG := Chrome.BG
const INK := Chrome.INK
const DIM := Chrome.DIM
const PANEL := Chrome.PANEL
const ACCENT := Color("f0772e")
const BRASS := Color("e3a21a")
const SAGE := Chrome.ACTION
const SLATE := Color("2f8fd8")
const PLUM := Color("9a5ad6")
const CATEGORIES := {"offers":"Offers", "rewards":"Rewards", "gems":"Gems", "resources":"Resources", "passes":"Passes"}

## Design-pixel targets. Physical phone sizing still requires device validation.
const BUY_H := 56
const HERO_BUY_H := 64

var _category := "offers"
var _category_buttons: Dictionary = {}
var _category_panels: Dictionary = {}
var _category_products: Dictionary = {}
var _building_category := ""
var _category_scroll: Dictionary = {}
var _scroll_revision := 0
var _restoring_scroll := false
var _shelf_root: VBoxContainer
var _wallet_chips: Dictionary = {}
var _scroll: ScrollContainer
var _sections: VBoxContainer
var _tick_labels: Array = []  # Array of {label:Label, kind:String, data:Variant}
var _product_buttons: Dictionary = {}  # product_id -> Array[Button], including hero duplicates
var _pending_products: Dictionary = {} # product_id -> true while this screen awaits settlement
var _tracking_ready := false
var _impressions: Dictionary = {}      # product_id -> true, one log per screen open
var _burst: Control

func _ready() -> void:
	var bg := ColorRect.new()
	bg.color = BG
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 14)
	add_child(margin)
	var page := VBoxContainer.new()
	page.add_theme_constant_override("separation", 12)
	margin.add_child(page)
	page.add_child(_build_shop_header())
	page.add_child(_build_category_bar())
	_scroll = ScrollContainer.new()
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	page.add_child(_scroll)
	_shelf_root = VBoxContainer.new()
	_shelf_root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.add_child(_shelf_root)

	EventBus.iap_completed.connect(_on_iap_completed)
	EventBus.daily_deals_refreshed.connect(_rebuild)
	EventBus.rv_reward_granted.connect(func(_p: String, _c: Dictionary) -> void: _rebuild())
	EventBus.boost_changed.connect(func(_m: float, _s: int) -> void: _rebuild())
	EventBus.toast_requested.connect(_on_toast)
	# Platform prices arrive asynchronously (and on resume/reconnect): rebuild
	# labels rather than holding a fabricated fallback as a live offer.
	if not IAPService.prices_updated.is_connected(_rebuild):
		IAPService.prices_updated.connect(_rebuild)

	var timer := Timer.new()
	timer.wait_time = 1.0
	timer.autostart = true
	timer.timeout.connect(_tick)
	add_child(timer)

	_rebuild()

func setup(payload: Dictionary) -> void:
	_tracking_ready = true
	Offers.check_triggers()
	Analytics.store_open(str(payload.get("source", "nav")))
	_impressions.clear()
	if is_node_ready():
		# Select the requested shelf before rebuilding/tracking visible products.
		# Wallet deep links must not report an unseen Offers shelf impression.
		var requested:=str(payload.get("category",""))
		if CATEGORIES.has(requested):_category=requested
		_rebuild()

# ------------------------------------------------------------------- rebuild

func _rebuild() -> void:
	if not is_node_ready():
		return
	# A rebuild used to throw the player back to the top of the store on every
	# purchase, which is the worst possible moment to lose their place.
	if not _restoring_scroll: _category_scroll[_category] = _scroll.scroll_vertical
	_tick_labels.clear()
	_product_buttons.clear()
	_pending_products.clear()
	_category_panels.clear()
	_category_products.clear()
	for child in _shelf_root.get_children():
		_shelf_root.remove_child(child)
		child.queue_free()
	for key in CATEGORIES:
		_building_category = key
		_category_products[key] = []
		_sections = VBoxContainer.new()
		_sections.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_sections.add_theme_constant_override("separation", 14)
		_shelf_root.add_child(_sections)
		_category_panels[key] = _sections
		match key:
			"offers":
				_build_hero()
				_build_starter()
				_build_daily_deals()
			"rewards": _build_free_rewards()
			"gems": _build_gem_ladder()
			"resources": _build_cash_insight()
			"passes":
				_build_ad_free()
				_build_footer()
	_building_category = ""
	_show_category()
	_refresh_wallet()

func _build_shop_header() -> Control:
	var header := VBoxContainer.new()
	header.add_theme_constant_override("separation", 10)
	var title := _display("Museum Store", 32, INK)
	header.add_child(title)
	if IAPService.debug_iap or AdService.debug_ads:
		var simulated := "Purchases and ads are simulated" if IAPService.debug_iap and AdService.debug_ads else ("Purchases are simulated" if IAPService.debug_iap else "Ads are simulated")
		var simulation := _label("PLAYTEST · " + simulated, 14, BRASS.darkened(0.25))
		simulation.name = "SimulationNotice"
		header.add_child(simulation)
	var wallet := HBoxContainer.new()
	wallet.add_theme_constant_override("separation", 8)
	header.add_child(wallet)
	for currency in ["cash", "gems", "insight"]:
		var chip := UI.make_dark_currency_chip(currency, "0", INK, 20)
		chip.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		chip.add_theme_stylebox_override("panel", _surface(Chrome.RAISED, Chrome.BORDER, 10))
		wallet.add_child(chip)
		_wallet_chips[currency] = chip
	return header

func _refresh_wallet() -> void:
	for key in _wallet_chips:
		var value: String = str(GameState.gems) if key == "gems" else (
			GameState.cash.to_notation() if key == "cash" else GameState.insight.to_notation())
		UI.set_chip_value(_wallet_chips[key], value)

func _build_category_bar() -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	for key in CATEGORIES:
		var button := _button(CATEGORIES[key], PANEL)
		button.name = "Category_" + key
		button.toggle_mode = true
		button.custom_minimum_size.y = UI.TOUCH_MIN
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.add_theme_font_size_override("font_size", 17)
		button.pressed.connect(func() -> void: set_category(key))
		row.add_child(button)
		_category_buttons[key] = button
	return row

func set_category(key: String) -> void:
	if not CATEGORIES.has(key): return
	if not _restoring_scroll: _category_scroll[_category] = _scroll.scroll_vertical
	_category = key
	_show_category()

func _show_category() -> void:
	for entry in _category_products.get(_category, []):
		_emit_impression(entry.id, entry.section)
	for key in _category_panels:
		_category_panels[key].visible = key == _category
	for key in _category_buttons:
		_category_buttons[key].set_pressed_no_signal(key == _category)
		_skin_button(_category_buttons[key], SAGE if key == _category else PANEL)
	_scroll_revision += 1
	_restoring_scroll = true
	_restore_category_scroll(_category, _scroll_revision)

func _restore_category_scroll(key: String, revision: int) -> void:
	# Visibility changes first resize the shelf, then the ScrollContainer updates
	# its range. Restoring before those layout passes clamps a saved offset to 0.
	await get_tree().process_frame
	await get_tree().process_frame
	if revision != _scroll_revision or key != _category: return
	_scroll.scroll_vertical = int(_category_scroll.get(key, 0))
	_restoring_scroll = false

func _tick() -> void:
	_refresh_wallet()
	for entry in _tick_labels:
		var label: Label = entry["label"]
		if not is_instance_valid(label):
			continue
		match str(entry["kind"]):
			"offer_expiry":
				label.text = "Ends in " + _fmt_duration(Offers.seconds_left(str(entry["data"])))
			"deals_refresh":
				label.text = "New deals in " + _fmt_duration(Deals.seconds_until_refresh())
			"boost_timer":
				label.text = _boost_text()
			"cash_worth":
				label.text = _cash_worth_text(DataLoader.get_iap(str(entry["data"])))
			"instant_cash":
				label.text = "+" + RV.instant_cash_value().to_notation()
			"free_gems_left":
				label.text = _placement_status("free_gems", "%d left today" % RV.remaining_free_gems())

# ---------------------------------------------------------------------- hero

## The single most valuable strip of pixels in the store. It always holds
## something: the best live offer, else the starter bundle for a player who has
## never bought, else the best-value gem tier.
func _build_hero() -> void:
	var offer: Dictionary = Offers.best_offer()
	var product_id: String = ""
	var offer_id: String = ""
	if not offer.is_empty():
		offer_id = str(offer["id"])
		product_id = str(offer.get("iap_id", ""))
	elif not Entitlements.has_ever_purchased():
		product_id = "starter_bundle"
	else:
		product_id = Pricing.best_value_id()
	var def: Dictionary = DataLoader.get_iap(product_id)
	if def.is_empty():
		return
	_log_impression(product_id, "hero")

	# The hero rides the ELEVATED card tone. On a dark shelf every card is the same
	# value, so "this one is the offer" has to be carried by the surface as well as
	# by the ribbon and the rim.
	var card := _card(Chrome.RAISED, Chrome.BRASS)
	_sections.add_child(card)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
	card.add_child(col)

	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 8)
	col.add_child(top)
	var badge_text: String = "LIMITED OFFER" if offer_id != "" else (
		"START HERE" if product_id == "starter_bundle" else "BEST VALUE")
	top.add_child(Art.make_ribbon(badge_text, PLUM if offer_id != "" else ACCENT))
	var gap := Control.new()
	gap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.add_child(gap)
	# A countdown is only drawn when something genuinely runs out.
	if offer_id != "" and Offers.expires(offer_id):
		var pill := Art.make_pill("", PLUM, "exclamation")
		top.add_child(pill)
		var pill_label: Label = pill.get_meta("pill_label", null) as Label
		if pill_label != null:
			pill_label.text = "Ends in " + _fmt_duration(Offers.seconds_left(offer_id))
			_tick_labels.append({"label": pill_label, "kind": "offer_expiry", "data": offer_id})

	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", 14)
	col.add_child(body)
	body.add_child(Art.make_product_art(def, 204, _tier_of(product_id)))

	var text := VBoxContainer.new()
	text.add_theme_constant_override("separation", 4)
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(text)
	text.add_child(_display(str(def.get("title", product_id)), UI.TYPE_TITLE, INK))
	var sub: String = str(def.get("subtitle", ""))
	if sub != "":
		text.add_child(_wrapped(sub, UI.TYPE_LABEL, DIM))
	text.add_child(_wrapped(_grants_text(def), UI.TYPE_BODY, INK))
	var anchor_row := _value_row(def)
	if anchor_row != null:
		text.add_child(anchor_row)

	var buy := _buy_button(product_id, "Get it  " + IAPService.localized_price(product_id),
		ACCENT, HERO_BUY_H)
	if offer_id != "":
		buy.pressed.connect(func() -> void: _on_buy_pressed(
			product_id, Offers.buy.bind(offer_id), buy))
	else:
		buy.pressed.connect(func() -> void: _on_buy_pressed(
			product_id, IAPCat.purchase.bind(product_id), buy))
	col.add_child(buy)

## Struck-through à-la-carte anchor plus the basis for it, or null when the bundle
## is not actually cheaper than buying the pieces.
func _value_row(def: Dictionary) -> Control:
	var save: int = Pricing.savings_pct(def)
	if save < 10:
		return null
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	row.add_child(Art.make_strikethrough(Pricing.format_usd(Pricing.alacarte_usd(def))))
	row.add_child(_label("bought separately", UI.TYPE_CAPTION, DIM))
	row.add_child(Art.make_ribbon("SAVE %d%%" % save, SAGE))
	return row

# --------------------------------------------------------------- free rewards

## Directly under the hero, deliberately. These cost the player nothing and were
## previously the last section built.
func _build_free_rewards() -> void:
	_sections.add_child(_section_header("Daily rewards"))
	_sections.add_child(_wrapped("Choose a reward. Watch an ad to collect it.", 17, DIM))
	var row := VBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	_sections.add_child(row)

	var boost_val := _label(_boost_text(), UI.TYPE_CAPTION, SLATE)
	_tick_labels.append({"label": boost_val, "kind": "boost_timer", "data": null})
	row.add_child(_free_card("x2 Income", boost_val, "income_x2", SAGE,
		func() -> void: RV.income_x2()))

	var cash_val := _label("+" + RV.instant_cash_value().to_notation(), UI.TYPE_CAPTION, SLATE)
	_tick_labels.append({"label": cash_val, "kind": "instant_cash", "data": null})
	row.add_child(_free_card("Instant Cash", cash_val, "instant_cash", ACCENT,
		func() -> void: RV.instant_cash()))

	var gems_val := _label(_placement_status("free_gems", "%d left today" % RV.remaining_free_gems()),
		UI.TYPE_CAPTION, SLATE)
	_tick_labels.append({"label": gems_val, "kind": "free_gems_left", "data": null})
	row.add_child(_free_card("%d Free Gems" % RV.free_gems_amount(), gems_val, "free_gems", BRASS,
		func() -> void: RV.free_gems()))

## Never disabled, even at the daily cap: rv_placements explains by toast, which is
## the house rule and also the only way the player learns when it comes back.
func _free_card(title: String, value: Label, placement_id: String, color: Color,
		on_press: Callable) -> Control:
	var card := _card(PANEL, color)
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	card.add_child(row)
	row.add_child(Art.make_product_art({"id":"reward_"+placement_id},96))
	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", 6)
	row.add_child(col)
	col.add_child(_display(title, 24, INK))
	value.add_theme_color_override("font_color", DIM)
	value.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(value)
	var btn := _button("Watch", color)
	btn.custom_minimum_size = Vector2(120, BUY_H)
	btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	btn.icon = UI.icon_texture("arrow_right", 18)
	btn.tooltip_text = RV.blocked_message(placement_id)
	btn.pressed.connect(on_press)
	row.add_child(btn)
	return card

func _placement_status(placement_id: String, when_free: String) -> String:
	var reason: String = RV.blocked_reason(placement_id)
	if reason == "":
		return when_free
	return RV.blocked_message(placement_id)

# -------------------------------------------------------------------- starter

## The $4.99 starter bundle used to be gated behind `venue_2_start`, which fires
## after the first prestige — so the one product designed for a new player could
## never be shown to one. It is now a section of its own, visible until the player
## buys anything at all, and it disappears the moment they do.
func _build_starter() -> void:
	if Entitlements.has_ever_purchased():
		return
	var ids: Array = []
	for pid in ["first_buy_bonus", "starter_bundle"]:
		if not DataLoader.get_iap(pid).is_empty():
			ids.append(pid)
	if ids.is_empty():
		return
	_sections.add_child(_section_header("Get started"))
	_sections.add_child(_label(
		"Shown once. These disappear after your first purchase.", UI.TYPE_CAPTION, DIM))
	var grid := _grid(2)
	_sections.add_child(grid)
	for pid in ids:
		grid.add_child(_product_card(str(pid), "starter", 1))

# ---------------------------------------------------------------- daily deals

func _build_daily_deals() -> void:
	_sections.add_child(_section_header("Daily deals"))
	var header_row := HBoxContainer.new()
	header_row.add_theme_constant_override("separation", 8)
	_sections.add_child(header_row)
	var countdown := _label("New deals in " + _fmt_duration(Deals.seconds_until_refresh()),
		UI.TYPE_LABEL, SLATE.darkened(0.2))
	countdown.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	header_row.add_child(countdown)
	_tick_labels.append({"label": countdown, "kind": "deals_refresh", "data": null})
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	header_row.add_child(spacer)
	var force := _button("Reroll  %d" % Deals.force_cost(), SLATE)
	force.icon = UI.icon_texture("gems", 18)
	force.custom_minimum_size = Vector2(0, UI.TOUCH_MIN)
	force.tooltip_text = "%d rerolls left today" % Deals.force_refreshes_left()
	force.pressed.connect(func() -> void: Deals.force_refresh())
	header_row.add_child(force)
	var shelf: Array = Deals.shelf()
	var grid := _grid(2)
	_sections.add_child(grid)
	for i in range(shelf.size()):
		# An odd shelf in a two-column grid leaves a hole exactly where the eye
		# lands; the odd card takes the full width instead.
		if i == shelf.size() - 1 and shelf.size() % 2 == 1:
			_sections.add_child(_product_card(str(shelf[i]), "daily", 1, true))
		else:
			grid.add_child(_product_card(str(shelf[i]), "daily", 1))

# ----------------------------------------------------------------- gem ladder

## A ladder, not a list: the two top tiers get the full sheet width and taller art,
## the four below share two columns. Card weight now tracks price, so $19.99 stops
## reading like $0.99.
func _build_gem_ladder() -> void:
	var ids: Array = _products_where(func(def: Dictionary) -> bool:
		return str(def.get("kind", "")) == "gems" and str(def.get("tag", "")) == "regular")
	if ids.is_empty():
		return
	_sections.add_child(_section_header("Gems"))
	_sections.add_child(_label("Value compared with the smallest pouch.", UI.TYPE_CAPTION, DIM))
	var grid := _grid(2)
	_sections.add_child(grid)
	var top_count: int = mini(2, ids.size())
	for i in range(ids.size() - top_count):
		grid.add_child(_product_card(str(ids[i]), "gems", i))
	for i in range(ids.size() - top_count, ids.size()):
		_sections.add_child(_product_card(str(ids[i]), "gems", i, true))

func _build_cash_insight() -> void:
	var ids: Array = _products_where(func(def: Dictionary) -> bool:
		return str(def.get("kind", "")) in ["cash_pack", "insight_pack"] \
			and str(def.get("tag", "")) == "regular")
	if ids.is_empty():
		return
	_sections.add_child(_section_header("Cash & insight"))
	var grid := _grid(2)
	_sections.add_child(grid)
	for i in range(ids.size()):
		if i == ids.size() - 1 and ids.size() % 2 == 1:
			_sections.add_child(_product_card(str(ids[i]), "cash_insight", i % 3, true))
		else:
			grid.add_child(_product_card(str(ids[i]), "cash_insight", i % 3))

## Ad-free is a non-consumable: once owned the card is replaced by its receipt
## rather than left on screen as a thing to buy twice.
func _build_ad_free() -> void:
	var ids: Array = _products_where(func(def: Dictionary) -> bool:
		return str(def.get("entitlement", "")) == "no_ads")
	if ids.is_empty():
		return
	_sections.add_child(_section_header("Ad-free"))
	for pid in ids:
		if Entitlements.owns(str(pid)):
			var owned := _card(PANEL, SAGE)
			var row := HBoxContainer.new()
			row.add_theme_constant_override("separation", 10)
			owned.add_child(row)
			row.add_child(Art.make_product_art({"id":"no_ads"},128))
			row.add_child(_wrapped("Ad-Free Pass active — interstitials are off.",
				UI.TYPE_BODY, INK))
			_sections.add_child(owned)
		else:
			_sections.add_child(_product_card(str(pid), "ad_free", 1, true))

# -------------------------------------------------------------------- footer

func _build_footer() -> void:
	_sections.add_child(UI.make_divider(Chrome.BORDER))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	_sections.add_child(row)
	var restore := _button("Restore purchases", SLATE)
	restore.custom_minimum_size = Vector2(0, UI.TOUCH_MIN)
	restore.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	restore.pressed.connect(func() -> void: IAPCat.restore_purchases())
	row.add_child(restore)
	var privacy := _button("Privacy choices", PLUM)
	privacy.custom_minimum_size = Vector2(0, UI.TOUCH_MIN)
	privacy.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	privacy.pressed.connect(_on_privacy_pressed)
	row.add_child(privacy)
	_sections.add_child(_wrapped(_footer_text(), UI.TYPE_CAPTION, DIM))

func _footer_text() -> String:
	var lines: Array = [
		"Prices shown are the store price; the amount charged is the amount displayed.",
		"\"Bought separately\" compares the same contents at our smallest pack prices.",
	]
	if Consent.child_directed():
		lines.append("This build serves non-personalized ads only.")
	return "\n".join(lines)

func _on_privacy_pressed() -> void:
	# The real EEA form comes from the UMP SDK; until it is wired, the revocation
	# path is what matters — a recorded choice the player cannot change is worse
	# than no choice at all.
	Consent.reset_choice()
	EventBus.toast_requested.emit("Privacy choices reset — you'll be asked again")

# ------------------------------------------------------------------ widgets

func _product_card(pid: String, section: String, tier: int, wide: bool = false) -> Control:
	var def: Dictionary = DataLoader.get_iap(pid)
	_log_impression(pid, section)
	var accent: Color = _kind_color(def)
	var card := _card(PANEL, accent)
	if not wide:
		card.custom_minimum_size = Vector2(300, 0)
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 6)
	card.add_child(col)

	var badge: String = Pricing.value_badge(def)
	if badge != "":
		col.add_child(Art.make_ribbon(badge, BRASS if badge == "BEST VALUE" else SAGE))
	elif not wide:
		# Reserve the ribbon line so neighboring product art and titles align.
		var badge_space := Control.new()
		badge_space.custom_minimum_size.y = 26
		badge_space.mouse_filter = Control.MOUSE_FILTER_IGNORE
		col.add_child(badge_space)

	var body: BoxContainer = HBoxContainer.new() if wide else VBoxContainer.new()
	body.add_theme_constant_override("separation", 10)
	col.add_child(body)
	var product_art := Art.make_product_art(def,180,tier)
	if not wide:product_art.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(product_art)
	var text := VBoxContainer.new()
	text.add_theme_constant_override("separation", 2)
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(text)
	text.add_child(_display(str(def.get("title", pid)), 22 if wide else 20, INK))
	if str(def.get("kind", "")) == "cash_pack":
		var worth := _wrapped(_cash_worth_text(def), UI.TYPE_LABEL, DIM)
		text.add_child(worth)
		_tick_labels.append({"label": worth, "kind": "cash_worth", "data": pid})
	else:
		text.add_child(_wrapped(_grants_text(def), UI.TYPE_LABEL, DIM))
	var sub: String = str(def.get("subtitle", ""))
	if sub != "" and wide:
		text.add_child(_wrapped(sub, UI.TYPE_CAPTION, DIM))
	if wide:
		var value_row := _value_row(def)
		if value_row != null:
			text.add_child(value_row)

	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(spacer)
	var buy := _buy_button(pid, IAPService.localized_price(pid), accent, BUY_H)
	buy.pressed.connect(func() -> void: _on_buy_pressed(pid, IAPCat.purchase.bind(pid), buy))
	col.add_child(buy)
	return card

## Buy buttons stay enabled in every state. When a product is sold out for the day,
## already owned, or not reported by the platform store, the label says so and
## the tap explains why — the codebase has already paid once for disabling these.
## An empty price_text (Play did not report the product) never falls back to a
## fabricated catalog price as a live offer: it reads Unavailable and stays blocked.
func _buy_button(pid: String, price_text: String, color: Color, height: int) -> Button:
	var reason: String = IAPCat.blocked_reason(pid)
	var label: String = price_text if price_text != "" else "Unavailable"
	var tint: Color = color
	match reason:
		"daily_limit":
			label = "Bought today"
			tint = SLATE
		"owned":
			label = "Owned"
			tint = SAGE
		"in_flight":
			label = "Purchasing…"
			tint = SLATE
		"unavailable":
			label = "Unavailable"
			tint = SLATE
	var b := _button(label, tint)
	b.custom_minimum_size = Vector2(0, height)
	b.set_meta("product_id", pid)
	b.set_meta("price_text", price_text)
	b.set_meta("base_color", color)
	if not _product_buttons.has(pid):
		_product_buttons[pid] = []
	(_product_buttons[pid] as Array).append(b)
	if reason == "in_flight":
		_pending_products[pid] = true
	if reason == "in_flight" or _pending_products.has(pid):
		_set_purchase_pending(b, true)
	return b

func _on_buy_pressed(product_id: String, action: Callable, tapped: Button = null) -> void:
	# The catalogue remains the authority for repeat-tap rejection. This local guard
	# closes the smaller window before an async backend exposes its in-flight state.
	if _pending_products.has(product_id):
		EventBus.toast_requested.emit("Purchase already in progress")
		return
	if not bool(action.call()):
		return
	_pending_products[product_id] = true
	# Include the exact control that initiated the purchase even in focused tests or
	# transient layouts where it has not yet been registered in the rebuilt shelf.
	if is_instance_valid(tapped) and not tapped in _buttons_for(product_id):
		if not _product_buttons.has(product_id):
			_product_buttons[product_id] = []
		(_product_buttons[product_id] as Array).append(tapped)
	_set_product_pending(product_id, true)

func _buttons_for(product_id: String) -> Array:
	return _product_buttons.get(product_id, []) as Array

func _set_purchase_pending(button: Button, pending: bool) -> void:
	if not is_instance_valid(button):
		return
	button.disabled = pending
	button.text = "Purchasing…" if pending else str(button.get_meta("price_text", "Buy"))
	_skin_button(button, SLATE if pending else button.get_meta("base_color", ACCENT))

func _set_product_pending(product_id: String, pending: bool) -> void:
	for button: Button in _buttons_for(product_id):
		_set_purchase_pending(button, pending)

func _on_iap_completed(product_id: String) -> void:
	var def: Dictionary = DataLoader.get_iap(product_id)
	_show_reward_burst(str(def.get("title", product_id)), _grants_text(def))
	UI.play_sfx(self, "buy")
	_rebuild()

## The single most important moment for a paying player used to be a toast that had
## already faded by the time the screen finished rebuilding.
func _show_reward_burst(title: String, contents: String) -> void:
	if is_instance_valid(_burst):
		_burst.queue_free()
	var holder := Control.new()
	holder.set_anchors_preset(Control.PRESET_FULL_RECT)
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(holder)
	_burst = holder

	var card := PanelContainer.new()
	card.set_anchors_preset(Control.PRESET_CENTER)
	card.grow_horizontal = Control.GROW_DIRECTION_BOTH
	card.grow_vertical = Control.GROW_DIRECTION_BOTH
	card.add_theme_stylebox_override("panel", UI.make_dark_frame(SAGE))
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(card)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 6)
	card.add_child(col)
	var head := _display("Thank you!", UI.TYPE_TITLE, Chrome.TEAL)
	head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(head)
	var name_lbl := _display(title, UI.TYPE_HEADING, INK)
	name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(name_lbl)
	if contents != "":
		var got := _label(contents, UI.TYPE_LABEL, SLATE.darkened(0.2))
		got.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		col.add_child(got)

	card.pivot_offset = Vector2(160, 60)
	card.scale = Vector2(0.7, 0.7)
	card.modulate.a = 0.0
	var tw := holder.create_tween()
	tw.set_parallel(true)
	tw.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(card, "scale", Vector2.ONE, 0.22)
	tw.tween_property(card, "modulate:a", 1.0, 0.16)
	var out := holder.create_tween()
	out.tween_interval(1.5)
	out.tween_property(card, "modulate:a", 0.0, 0.4)
	out.tween_callback(holder.queue_free)

## A failed or blocked purchase must put the button back; the toast is the signal
## we already have for both.
func _on_toast(_text: String) -> void:
	if _pending_products.is_empty():
		return
	var settled: Array = []
	for pid in _pending_products.keys():
		if IAPCat.is_in_flight(str(pid)):
			continue  # still waiting on the store; leave the pending label alone
		_set_product_pending(str(pid), false)
		settled.append(pid)
	for pid in settled:
		_pending_products.erase(pid)

# ------------------------------------------------------------------- helpers

func _log_impression(product_id: String, section: String) -> void:
	if not _building_category.is_empty():
		_category_products[_building_category].append({"id":product_id,"section":section})
		if _building_category != _category: return
	_emit_impression(product_id, section)

func _emit_impression(product_id: String, section: String) -> void:
	if not _tracking_ready: return
	if _impressions.has(product_id):
		return
	_impressions[product_id] = true
	Analytics.product_view(product_id, section)

func _tier_of(product_id: String) -> int:
	var ids: Array = _products_where(func(def: Dictionary) -> bool:
		return str(def.get("kind", "")) == str(DataLoader.get_iap(product_id).get("kind", "")) \
			and str(def.get("tag", "")) == "regular")
	var idx: int = ids.find(product_id)
	return maxi(idx, 0)

func _kind_color(def: Dictionary) -> Color:
	match str(def.get("kind", "")):
		"gems":
			return SLATE
		"cash_pack":
			return SAGE
		"insight_pack":
			return PLUM
		"utility":
			return SAGE
		_:
			return ACCENT

func _products_where(pred: Callable) -> Array:
	var out: Array = []
	for pid in DataLoader.iap_products.keys():
		if pred.call(DataLoader.iap_products[pid]):
			out.append(pid)
	out.sort_custom(func(a: String, b: String) -> bool:
		return Pricing.price_usd(DataLoader.get_iap(a)) < Pricing.price_usd(DataLoader.get_iap(b)))
	return out

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
	return "  +  ".join(parts)

func _cash_worth_text(def: Dictionary) -> String:
	var secs: float = float(def.get("grants", {}).get("cash_seconds", 0))
	var worth: BigNumber = Economy.current_cash_per_second().scale(secs)
	return "Worth " + worth.to_notation() + " now"

func _boost_text() -> String:
	var rem: int = RV.income_x2_remaining_seconds()
	if rem <= 0:
		return "+%dh, stacks" % RV.boost_hours_per_view()
	return _fmt_duration(rem) + " left"

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

func _section_header(text: String) -> Label:
	return UI.make_display_label(text, UI.TYPE_TITLE, INK)

func _display(text: String, size: int, color: Color) -> Label:
	var label := UI.make_display_label(text, size, color)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size.x = 100
	return label

func _label(text: String, size: int, color: Color) -> Label:
	var l := UI.make_label(text, size)
	l.add_theme_color_override("font_color", color)
	return l

func _wrapped(text: String, size: int, color: Color) -> Label:
	var l := _label(text, size, color)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(120, 0)
	return l

func _grid(columns: int) -> GridContainer:
	var grid := GridContainer.new()
	grid.columns = columns
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 10)
	return grid

## Card surface: a lifted cream tile with a saturated rim in the product's own
## colour, so a shelf reads as a set of different things rather than one repeated
## thing.
func _card(fill: Color, border: Color = Color(0, 0, 0, 0)) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _surface(fill, border.lerp(fill, .35), 16))
	return panel

func _surface(fill: Color, border: Color, radius: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = border
	style.set_border_width_all(2)
	style.set_corner_radius_all(radius)
	style.set_content_margin_all(14)
	style.shadow_color = Color(0,0,0,.17)
	style.shadow_size = 4
	style.shadow_offset = Vector2(0,3)
	return style

func _button(text: String, color: Color) -> Button:
	var button := UI.make_button(text, color)
	_skin_button(button, color)
	return button

func _skin_button(button: Button, color: Color) -> void:
	for state in ["normal", "hover", "pressed", "disabled"]:
		var fill := color.darkened(.04) if state == "hover" else (color.darkened(.13) if state == "pressed" else color)
		if state == "disabled": fill = PANEL
		var style := _surface(fill, fill.lightened(.14), 10)
		style.content_margin_top = 8
		style.content_margin_bottom = 8
		button.add_theme_stylebox_override(state, style)
	button.add_theme_constant_override("outline_size", 0)
	var foreground := Art.foreground_for(color)
	button.add_theme_color_override("font_color", foreground)
	button.add_theme_color_override("font_hover_color", foreground)
	button.add_theme_color_override("font_pressed_color", foreground)
	button.add_theme_color_override("font_disabled_color", DIM)
	var focus := StyleBoxFlat.new()
	focus.bg_color = Color.TRANSPARENT
	focus.border_color = INK
	focus.set_border_width_all(2)
	focus.set_corner_radius_all(10)
	button.add_theme_stylebox_override("focus", focus)
