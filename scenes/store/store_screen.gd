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
## The shape now, top to bottom, is the order a shopper actually reads:
##   HERO      one offer, full width, with a real countdown and a computed saving
##   FREE      the three rewarded placements, above the fold, never below it
##   STARTER   shown only to a player who has never bought anything
##   DAILY     the rotating shelf, with its refresh countdown
##   GEMS      a ladder whose cards grow with the tier, badged with computed value
##   CASH/INSIGHT, AD-FREE, then the legal footer
##
## House rules honoured here:
##  · No button is ever disabled for affordability, ownership or a daily limit. It
##    stays tappable and explains by toast — a disabled button swallows the tap and
##    reads as a broken game.
##  · Every value claim is computed from the catalog (store_pricing.gd) and states
##    its basis on screen. No invented "most popular", no strikethrough without a
##    printed anchor, no countdown on something that does not actually expire.
##  · This screen is popup CONTENT, so its page is the light SURFACE and its body
##    text is INK — never the deep indigo app shell.

const RV := preload("res://scripts/monetization/rv_placements.gd")
const IAPCat := preload("res://scripts/monetization/iap_catalog.gd")
const Deals := preload("res://scripts/monetization/daily_deals.gd")
const Offers := preload("res://scripts/monetization/offer_system.gd")
const Entitlements := preload("res://scripts/monetization/entitlements.gd")
const Pricing := preload("res://scripts/monetization/store_pricing.gd")
const Consent := preload("res://scripts/monetization/consent.gd")
const Art := preload("res://scripts/monetization/store_art.gd")
const UI := preload("res://scripts/ui/ui_kit.gd")

# Palette aliases (ui_kit is the single source — SPEC §2).
const BG := UI.SURFACE
const INK := UI.INK
const PANEL := UI.PANEL
const ACCENT := UI.ACCENT
const BRASS := UI.BRASS
const SAGE := UI.SAGE
const SLATE := UI.SLATE
const PLUM := UI.PLUM

## Touch floor for anything in this screen. ui_kit documents 48dp as the Android
## minimum; a buy button is the last place to sit on the floor, so it sits above it.
const BUY_H := 56
const HERO_BUY_H := 64

var _scroll: ScrollContainer
var _sections: VBoxContainer
var _tick_labels: Array = []  # Array of {label:Label, kind:String, data:Variant}
var _pending_buttons: Dictionary = {}  # product_id -> Button (restored on failure)
var _impressions: Dictionary = {}      # product_id -> true, one log per screen open
var _burst: Control

func _ready() -> void:
	var bg := ColorRect.new()
	bg.color = BG
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	_scroll = ScrollContainer.new()
	_scroll.set_anchors_preset(Control.PRESET_FULL_RECT)
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(_scroll)

	_sections = VBoxContainer.new()
	_sections.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_sections.add_theme_constant_override("separation", 12)
	_scroll.add_child(_sections)

	EventBus.iap_completed.connect(_on_iap_completed)
	EventBus.daily_deals_refreshed.connect(_rebuild)
	EventBus.rv_reward_granted.connect(func(_p: String, _c: Dictionary) -> void: _rebuild())
	EventBus.boost_changed.connect(func(_m: float, _s: int) -> void: _rebuild())
	EventBus.toast_requested.connect(_on_toast)

	var timer := Timer.new()
	timer.wait_time = 1.0
	timer.autostart = true
	timer.timeout.connect(_tick)
	add_child(timer)

	_rebuild()

func setup(payload: Dictionary) -> void:
	Offers.check_triggers()
	Analytics.store_open(str(payload.get("source", "nav")))
	_impressions.clear()
	if is_node_ready():
		_rebuild()

# ------------------------------------------------------------------- rebuild

func _rebuild() -> void:
	if not is_node_ready():
		return
	# A rebuild used to throw the player back to the top of the store on every
	# purchase, which is the worst possible moment to lose their place.
	var scroll_y: int = _scroll.scroll_vertical if _scroll else 0
	_tick_labels.clear()
	_pending_buttons.clear()
	for child in _sections.get_children():
		child.queue_free()
	_build_hero()
	_build_free_rewards()
	_build_starter()
	_build_daily_deals()
	_build_gem_ladder()
	_build_cash_insight()
	_build_ad_free()
	_build_footer()
	if _scroll:
		_scroll.set_deferred("scroll_vertical", scroll_y)

func _tick() -> void:
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

	var card := _card(PANEL, ACCENT)
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
	body.add_child(Art.make_product_art(def, 104, _tier_of(product_id)))

	var text := VBoxContainer.new()
	text.add_theme_constant_override("separation", 4)
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(text)
	text.add_child(_display(str(def.get("title", product_id)), UI.TYPE_TITLE, INK))
	var sub: String = str(def.get("subtitle", ""))
	if sub != "":
		text.add_child(_wrapped(sub, UI.TYPE_LABEL, SLATE))
	text.add_child(_wrapped(_grants_text(def), UI.TYPE_BODY, INK))
	var anchor_row := _value_row(def)
	if anchor_row != null:
		text.add_child(anchor_row)

	var buy := _buy_button(product_id, "Get it  " + IAPService.localized_price(product_id),
		ACCENT, HERO_BUY_H)
	if offer_id != "":
		buy.pressed.connect(func() -> void: _on_buy_pressed(product_id, Offers.buy.bind(offer_id)))
	else:
		buy.pressed.connect(func() -> void: _on_buy_pressed(product_id, IAPCat.purchase.bind(product_id)))
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
	row.add_child(_label("bought separately", UI.TYPE_CAPTION, SLATE))
	row.add_child(Art.make_ribbon("SAVE %d%%" % save, SAGE))
	return row

# --------------------------------------------------------------- free rewards

## Directly under the hero, deliberately. These cost the player nothing and were
## previously the last section built.
func _build_free_rewards() -> void:
	_sections.add_child(_section_header("Free — watch a short ad"))
	var row := HBoxContainer.new()
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
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 4)
	card.add_child(col)
	col.add_child(_display(title, UI.TYPE_LABEL, INK))
	col.add_child(value)
	var btn := UI.make_button("Watch", color)
	btn.custom_minimum_size = Vector2(0, BUY_H)
	btn.icon = UI.icon_texture("arrow_right", 18)
	btn.tooltip_text = RV.blocked_message(placement_id)
	btn.pressed.connect(on_press)
	col.add_child(btn)
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
		"Shown once. These disappear after your first purchase.", UI.TYPE_CAPTION, SLATE))
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
		UI.TYPE_LABEL, SLATE)
	countdown.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	header_row.add_child(countdown)
	_tick_labels.append({"label": countdown, "kind": "deals_refresh", "data": null})
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	header_row.add_child(spacer)
	var force := UI.make_button("Reroll  %d" % Deals.force_cost(), SLATE)
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
	_sections.add_child(_label("Value compared with the smallest pouch.", UI.TYPE_CAPTION, SLATE))
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
			row.add_child(UI.make_icon("check", 26, SAGE))
			row.add_child(_wrapped("Ad-Free Pass active — interstitials are off.",
				UI.TYPE_BODY, INK))
			_sections.add_child(owned)
		else:
			_sections.add_child(_product_card(str(pid), "ad_free", 1, true))

# -------------------------------------------------------------------- footer

func _build_footer() -> void:
	_sections.add_child(UI.make_divider())
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	_sections.add_child(row)
	var restore := UI.make_button("Restore purchases", SLATE)
	restore.custom_minimum_size = Vector2(0, UI.TOUCH_MIN)
	restore.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	restore.pressed.connect(func() -> void: IAPCat.restore_purchases())
	row.add_child(restore)
	var privacy := UI.make_button("Privacy choices", PLUM)
	privacy.custom_minimum_size = Vector2(0, UI.TOUCH_MIN)
	privacy.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	privacy.pressed.connect(_on_privacy_pressed)
	row.add_child(privacy)
	_sections.add_child(_wrapped(_footer_text(), UI.TYPE_CAPTION, SLATE))

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

	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", 10)
	col.add_child(body)
	body.add_child(Art.make_product_art(def, 84 if wide else 60, tier))
	var text := VBoxContainer.new()
	text.add_theme_constant_override("separation", 2)
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(text)
	text.add_child(_display(str(def.get("title", pid)), UI.TYPE_HEADING, INK))
	if str(def.get("kind", "")) == "cash_pack":
		var worth := _label(_cash_worth_text(def), UI.TYPE_LABEL, SLATE)
		text.add_child(worth)
		_tick_labels.append({"label": worth, "kind": "cash_worth", "data": pid})
	else:
		text.add_child(_wrapped(_grants_text(def), UI.TYPE_LABEL, SLATE))
	var sub: String = str(def.get("subtitle", ""))
	if sub != "" and wide:
		text.add_child(_wrapped(sub, UI.TYPE_CAPTION, SLATE))
	if wide:
		var value_row := _value_row(def)
		if value_row != null:
			text.add_child(value_row)

	var buy := _buy_button(pid, IAPService.localized_price(pid), accent, BUY_H)
	buy.pressed.connect(func() -> void: _on_buy_pressed(pid, IAPCat.purchase.bind(pid)))
	col.add_child(buy)
	return card

## Buy buttons stay enabled in every state. When a product is sold out for the day
## or already owned the label says so and the tap explains why — the codebase has
## already paid once for disabling these.
func _buy_button(pid: String, price_text: String, color: Color, height: int) -> Button:
	var reason: String = IAPCat.blocked_reason(pid)
	var label: String = price_text
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
	var b := UI.make_button(label, tint)
	b.custom_minimum_size = Vector2(0, height)
	b.set_meta("product_id", pid)
	b.set_meta("price_text", price_text)
	b.set_meta("base_color", color)
	return b

func _on_buy_pressed(product_id: String, action: Callable) -> void:
	if not bool(action.call()):
		return
	# Pending state, not a disabled button: iap_catalog rejects the repeat tap and
	# toasts, so the player always gets an answer.
	var btn: Button = _find_buy_button(product_id)
	if btn != null:
		btn.text = "Purchasing…"
		UI.retint_button(btn, SLATE)
		_pending_buttons[product_id] = btn

func _find_buy_button(product_id: String) -> Button:
	for node in _sections.get_children():
		var found: Button = _search_button(node, product_id)
		if found != null:
			return found
	return null

func _search_button(node: Node, product_id: String) -> Button:
	if node is Button and node.has_meta("price_text") \
			and str(node.get_meta("product_id", "")) == product_id:
		return node
	for child in node.get_children():
		var found: Button = _search_button(child, product_id)
		if found != null:
			return found
	return null

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
	card.add_theme_stylebox_override("panel", UI.make_frame(SAGE))
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(card)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 6)
	card.add_child(col)
	var head := _display("Thank you!", UI.TYPE_TITLE, SAGE)
	head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(head)
	var name_lbl := _display(title, UI.TYPE_HEADING, INK)
	name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(name_lbl)
	if contents != "":
		var got := _label(contents, UI.TYPE_LABEL, SLATE)
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
	if _pending_buttons.is_empty():
		return
	var settled: Array = []
	for pid in _pending_buttons.keys():
		if IAPCat.is_in_flight(str(pid)):
			continue  # still waiting on the store; leave the pending label alone
		var btn: Button = _pending_buttons[pid]
		if is_instance_valid(btn):
			btn.text = str(btn.get_meta("price_text", "Buy"))
			UI.retint_button(btn, btn.get_meta("base_color", ACCENT))
		settled.append(pid)
	for pid in settled:
		_pending_buttons.erase(pid)

# ------------------------------------------------------------------- helpers

func _log_impression(product_id: String, section: String) -> void:
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
	return UI.make_display_label(text, size, color)

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

## Card surface: light page with a saturated rim in the product's own colour, so a
## shelf of cards reads as a set of different things rather than one repeated thing.
func _card(fill: Color, border: Color = Color(0, 0, 0, 0)) -> PanelContainer:
	var p := PanelContainer.new()
	if border.a > 0.0:
		var sb := UI.make_card(fill)
		sb.set_border_width_all(3)
		sb.border_color = border
		p.add_theme_stylebox_override("panel", sb)
	else:
		p.add_theme_stylebox_override("panel", UI.make_card(fill))
	return p
