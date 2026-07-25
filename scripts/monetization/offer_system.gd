extends RefCounted
## offer_system.gd — triggered special offers (SPEC §8, data/offers.json).
##
## Triggers (offers.json "trigger" field):
##   "venue_N_start"    -> fires when GameState.venues_unlocked reaches its Nth venue
##   "rep_N"            -> fires when GameState.rep_level() >= N
##   "event_day"        -> fires when the Inspection event unlocks (feature_unlocked("inspection"))
##   "never_purchased"  -> fires for a player who has never bought anything, and is
##                         retired the moment they do
## check_triggers() is idempotent and re-evaluates everything against current state.
## It is wired to EventBus.prestige_performed + EventBus.reputation_level_up, and the
## world-view offer chip (scenes/ui/boost_dock.gd) polls it on a slow timer — offers
## used to be evaluated only when the store was opened, so a 24h countdown either had
## not started or was burning down where nobody could see it.
##
## State: GameState.offer_state[offer_id] = {"status":"shown|bought|dismissed", "shown_at":int}
## (legacy plain-string values from SPEC §3 saves are tolerated on read).
## expires_hours == 0 means the offer does not expire.
##
## Pricing note: an offer's saving is COMPUTED from the catalog by store_pricing.gd
## (what the same contents cost bought separately at entry-tier prices) rather than
## read from a hand-written discount field. v1 printed a decorative "SAVE 45%" beside
## a price that was never actually discounted, which is both a weak sales cue and,
## once real billing is attached, a misleading-pricing exposure.

const IapCatalog := preload("res://scripts/monetization/iap_catalog.gd")
const Entitlements := preload("res://scripts/monetization/entitlements.gd")
const StorePricing := preload("res://scripts/monetization/store_pricing.gd")
const MonoClock := preload("res://scripts/monetization/mono_clock.gd")

static var _connected: bool = false

static func connect_signals() -> void:
	if _connected:
		return
	_connected = true
	EventBus.prestige_performed.connect(func(_f: String, _t: String) -> void: check_triggers())
	EventBus.reputation_level_up.connect(func(_l: int, _r: Dictionary) -> void: check_triggers())
	EventBus.iap_completed.connect(_on_iap_completed)

# -------------------------------------------------------------------- triggers

static func check_triggers() -> void:
	connect_signals()
	for offer_id in DataLoader.offers.keys():
		if _status(offer_id) != "":
			continue  # already shown/bought/dismissed — never re-trigger
		var offer: Dictionary = DataLoader.offers[offer_id]
		if _trigger_met(str(offer.get("trigger", ""))):
			GameState.offer_state[offer_id] = {"status": "shown", "shown_at": MonoClock.now()}
			Analytics.log_event("offer_shown", {"offer": offer_id, "trigger": str(offer.get("trigger", ""))})

static func _trigger_met(trigger: String) -> bool:
	if trigger.begins_with("venue_") and trigger.ends_with("_start"):
		var n: int = int(trigger.trim_prefix("venue_").trim_suffix("_start"))
		return GameState.venues_unlocked.size() >= n
	if trigger.begins_with("rep_"):
		var n: int = int(trigger.trim_prefix("rep_"))
		return GameState.rep_level() >= n
	if trigger == "event_day":
		return GameState.feature_unlocked("inspection")
	if trigger == "never_purchased":
		return not Entitlements.has_ever_purchased()
	return false

# ---------------------------------------------------------------------- state

static func _entry(offer_id: String) -> Dictionary:
	var v: Variant = GameState.offer_state.get(offer_id, null)
	if typeof(v) == TYPE_DICTIONARY:
		return v
	if typeof(v) == TYPE_STRING and v != "":
		return {"status": v, "shown_at": 0}  # legacy SPEC §3 string form
	return {}

static func _status(offer_id: String) -> String:
	return str(_entry(offer_id).get("status", ""))

static func _set_status(offer_id: String, status: String) -> void:
	var e: Dictionary = _entry(offer_id)
	e["status"] = status
	if not e.has("shown_at"):
		e["shown_at"] = MonoClock.now()
	GameState.offer_state[offer_id] = e

static func shown_at(offer_id: String) -> int:
	return int(_entry(offer_id).get("shown_at", 0))

## 0 when the offer never expires.
static func expires_at(offer_id: String) -> int:
	var offer: Dictionary = DataLoader.offers.get(offer_id, {})
	var hours: int = int(offer.get("expires_hours", 24))
	if hours <= 0:
		return 0
	return shown_at(offer_id) + hours * 3600

static func expires(offer_id: String) -> bool:
	return expires_at(offer_id) > 0

static func seconds_left(offer_id: String) -> int:
	if not expires(offer_id):
		return 0
	return maxi(0, expires_at(offer_id) - MonoClock.now())

## Record that the player actually laid eyes on the card. Separate from the trigger
## so impressions can be counted against conversions.
static func mark_seen(offer_id: String) -> void:
	var e: Dictionary = _entry(offer_id)
	if e.is_empty() or bool(e.get("seen", false)):
		return
	e["seen"] = true
	GameState.offer_state[offer_id] = e
	Analytics.log_event("offer_impression", {"offer": offer_id})

## Computed saving against buying the same contents separately. 0 when there is
## none, in which case the card shows no discount badge at all.
static func savings_pct(offer_id: String) -> int:
	return StorePricing.savings_pct(DataLoader.get_iap(_iap_id(offer_id)))

static func anchor_usd(offer_id: String) -> float:
	return StorePricing.alacarte_usd(DataLoader.get_iap(_iap_id(offer_id)))

static func _iap_id(offer_id: String) -> String:
	return str(DataLoader.offers.get(offer_id, {}).get("iap_id", ""))

## Offers currently visible in the store banner row: shown, not bought/dismissed,
## not expired. Sorted by expiry (soonest first; non-expiring last).
static func active_offers() -> Array:
	check_triggers()
	var out: Array = []
	var now: int = MonoClock.now()
	for offer_id in DataLoader.offers.keys():
		if _status(offer_id) != "shown":
			continue
		if expires(offer_id) and expires_at(offer_id) <= now:
			continue
		var offer: Dictionary = DataLoader.offers[offer_id].duplicate()
		offer["id"] = offer_id
		out.append(offer)
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var ea: int = expires_at(str(a["id"]))
		var eb: int = expires_at(str(b["id"]))
		if ea == 0:
			return false
		if eb == 0:
			return true
		return ea < eb)
	return out

## The offer that earns the hero slot: biggest computed saving, expiry as tiebreak.
static func best_offer() -> Dictionary:
	var best: Dictionary = {}
	var best_save: int = -1
	for offer in active_offers():
		var save: int = savings_pct(str(offer["id"]))
		if save > best_save:
			best_save = save
			best = offer
	return best

static func active_count() -> int:
	return active_offers().size()

# ---------------------------------------------------------------------- buy

static func buy(offer_id: String) -> bool:
	connect_signals()
	if _status(offer_id) != "shown" or (expires(offer_id) and seconds_left(offer_id) <= 0):
		EventBus.toast_requested.emit("Offer expired")
		return false
	var iap_id: String = _iap_id(offer_id)
	if iap_id == "":
		return false
	Analytics.log_event("offer_buy_initiate", {"offer": offer_id, "iap": iap_id})
	return IapCatalog.purchase(iap_id)

static func dismiss(offer_id: String) -> void:
	if _status(offer_id) == "shown":
		_set_status(offer_id, "dismissed")
		Analytics.log_event("offer_dismissed", {"offer": offer_id})

## When a purchase completes, every shown offer pointing at that product is bought,
## and any "never purchased" offer stops being true and retires.
static func _on_iap_completed(product_id: String) -> void:
	for offer_id in DataLoader.offers.keys():
		if _status(offer_id) != "shown":
			continue
		var offer: Dictionary = DataLoader.offers[offer_id]
		if str(offer.get("iap_id", "")) == product_id:
			_set_status(offer_id, "bought")
			Analytics.log_event("offer_bought", {"offer": offer_id, "iap": product_id})
		elif str(offer.get("trigger", "")) == "never_purchased":
			_set_status(offer_id, "dismissed")
