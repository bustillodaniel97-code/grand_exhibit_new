extends RefCounted
## store_pricing.gd — value framing for the shopfront, computed from the catalog.
##
## The store needs to answer "is this a good deal?" without lying. v1 printed
## "SAVE 45%" from a hand-written `discount_pct` next to an unmodified price, with
## nothing to compare against: the number was decorative, and once a real billing
## SDK charges the same price either way it is also a misleading-pricing exposure.
##
## Everything here is derived from data/store_iap.json, so it cannot drift from what
## is actually charged:
##
##  · alacarte_usd(product) — what the same contents cost bought separately at the
##    ENTRY tier of each kind (the smallest gem pouch, the one-hour cash pack, the
##    small insight pack). Entry tier, not best tier, because that is the purchase a
##    player actually makes instead: nobody buys the $99 pack to get 300 gems. The
##    basis is always printed next to the number ("bought separately"), so the claim
##    is checkable rather than implied.
##  · savings_pct(product) — from that anchor, and 0 when the anchor does not exceed
##    the price. A bundle that is not cheaper simply shows no badge.
##  · bonus_pct(gem product) — gems-per-dollar against the entry pouch. This is the
##    honest way to rank a ladder: "+73% more gems per dollar", not "MOST POPULAR",
##    which we have no data to support and will not invent.
##  · best_value_id() — the single highest gems-per-dollar tier. Exactly one card
##    can carry the badge, and it is the one that is actually true.

## Cheapest product of a kind, by price — the tier a player buys by default.
static func _entry_product(kind: String) -> Dictionary:
	var best: Dictionary = {}
	var best_price: float = 0.0
	for pid in DataLoader.iap_products.keys():
		var def: Dictionary = DataLoader.iap_products[pid]
		if str(def.get("kind", "")) != kind or str(def.get("tag", "")) != "regular":
			continue
		var price: float = price_usd(def)
		if price <= 0.0:
			continue
		if best.is_empty() or price < best_price:
			best = def
			best_price = price
	return best

static func price_usd(def: Dictionary) -> float:
	return str(def.get("price_usd", "$0")).trim_prefix("$").to_float()

static func _grant_value(def: Dictionary, key: String) -> float:
	return float(def.get("grants", {}).get(key, 0.0))

static func _insight_units(def: Dictionary) -> float:
	var g: Dictionary = def.get("grants", {})
	return float(g.get("insight_m", 0.0)) * pow(10.0, float(g.get("insight_e", 0)))

## Dollars per gem / per second of income / per insight unit at the entry tier.
static func _entry_rate(kind: String, unit_getter: Callable) -> float:
	var def: Dictionary = _entry_product(kind)
	if def.is_empty():
		return 0.0
	var units: float = float(unit_getter.call(def))
	if units <= 0.0:
		return 0.0
	return price_usd(def) / units

static func gem_rate_usd() -> float:
	return _entry_rate("gems", func(d: Dictionary) -> float: return _grant_value(d, "gems"))

static func cash_second_rate_usd() -> float:
	return _entry_rate("cash_pack", func(d: Dictionary) -> float: return _grant_value(d, "cash_seconds"))

static func insight_rate_usd() -> float:
	return _entry_rate("insight_pack", func(d: Dictionary) -> float: return _insight_units(d))

## What this product's contents cost bought separately at entry-tier rates.
static func alacarte_usd(def: Dictionary) -> float:
	var g: Dictionary = def.get("grants", {})
	var total: float = 0.0
	total += float(g.get("gems", 0)) * gem_rate_usd()
	total += float(g.get("cash_seconds", 0)) * cash_second_rate_usd()
	total += _insight_units(def) * insight_rate_usd()
	var box_id: String = str(g.get("box", ""))
	if box_id != "":
		# A case has no dollar price of its own; it is sold for gems, so value it at
		# the same entry-tier gem rate rather than inventing a number.
		total += float(DataLoader.get_lootbox(box_id).get("price_gems", 0)) * gem_rate_usd()
	return total

static func savings_pct(def: Dictionary) -> int:
	var anchor: float = alacarte_usd(def)
	var price: float = price_usd(def)
	if anchor <= price or price <= 0.0:
		return 0
	return int(round((anchor - price) / anchor * 100.0))

static func format_usd(amount: float) -> String:
	return "$%.2f" % amount

## Gems per dollar relative to the entry pouch, as a percentage bonus.
static func bonus_pct(def: Dictionary) -> int:
	if str(def.get("kind", "")) != "gems":
		return 0
	var rate: float = gem_rate_usd()
	if rate <= 0.0:
		return 0
	var price: float = price_usd(def)
	var gems: float = float(def.get("grants", {}).get("gems", 0))
	if price <= 0.0 or gems <= 0.0:
		return 0
	var own_rate: float = price / gems
	return maxi(0, int(round((rate / own_rate - 1.0) * 100.0)))

## The one gem tier with the most gems per dollar. "" when the catalog has none.
static func best_value_id() -> String:
	var best_id: String = ""
	var best_per_dollar: float = 0.0
	for pid in DataLoader.iap_products.keys():
		var def: Dictionary = DataLoader.iap_products[pid]
		if str(def.get("kind", "")) != "gems" or str(def.get("tag", "")) != "regular":
			continue
		var price: float = price_usd(def)
		var gems: float = float(def.get("grants", {}).get("gems", 0))
		if price <= 0.0 or gems <= 0.0:
			continue
		var per_dollar: float = gems / price
		if per_dollar > best_per_dollar:
			best_per_dollar = per_dollar
			best_id = str(pid)
	return best_id

## Short, checkable badge line for a card, or "" when there is nothing true to say.
static func value_badge(def: Dictionary) -> String:
	if str(def.get("id", "")) != "" and str(def.get("id", "")) == best_value_id():
		return "BEST VALUE"
	var bonus: int = bonus_pct(def)
	if bonus >= 10:
		return "+%d%% MORE PER $" % bonus
	var save: int = savings_pct(def)
	if save >= 10:
		return "SAVE %d%%" % save
	return ""
