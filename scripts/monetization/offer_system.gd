extends RefCounted
## offer_system.gd — triggered special offers (SPEC §8, data/offers.json).
##
## Triggers (offers.json "trigger" field):
##   "venue_N_start" -> fires when GameState.venues_unlocked reaches its Nth venue
##   "rep_10"        -> fires when GameState.rep_level() >= 10
##   "event_day"     -> fires when the Inspection event unlocks (feature_unlocked("inspection"))
## check_triggers() is idempotent and re-evaluates everything against current state;
## it is wired to EventBus.prestige_performed + EventBus.reputation_level_up and is
## also safe to call any time (e.g. when the store screen opens).
##
## State: GameState.offer_state[offer_id] = {"status":"shown|bought|dismissed", "shown_at":int}
## (legacy plain-string values from SPEC §3 saves are tolerated on read).
##
## NOTE: discount_pct is DISPLAY-ONLY. The debug IAPService charges the catalog
## price_usd unchanged; real store-side promo pricing is wired when a real billing
## SDK replaces IAPService.

const IapCatalog := preload("res://scripts/monetization/iap_catalog.gd")

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
			GameState.offer_state[offer_id] = {"status": "shown", "shown_at": ClockGuard.now()}
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
		e["shown_at"] = ClockGuard.now()
	GameState.offer_state[offer_id] = e

static func shown_at(offer_id: String) -> int:
	return int(_entry(offer_id).get("shown_at", 0))

static func expires_at(offer_id: String) -> int:
	var offer: Dictionary = DataLoader.offers.get(offer_id, {})
	return shown_at(offer_id) + int(offer.get("expires_hours", 24)) * 3600

static func seconds_left(offer_id: String) -> int:
	return maxi(0, expires_at(offer_id) - ClockGuard.now())

## Offers currently visible in the store banner row: shown, not bought/dismissed,
## not expired. Sorted by expiry (soonest first).
static func active_offers() -> Array:
	check_triggers()
	var out: Array = []
	var now: int = ClockGuard.now()
	for offer_id in DataLoader.offers.keys():
		if _status(offer_id) != "shown":
			continue
		if expires_at(offer_id) <= now:
			continue
		var offer: Dictionary = DataLoader.offers[offer_id].duplicate()
		offer["id"] = offer_id
		out.append(offer)
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return expires_at(str(a["id"])) < expires_at(str(b["id"])))
	return out

# ---------------------------------------------------------------------- buy

static func buy(offer_id: String) -> bool:
	connect_signals()
	if _status(offer_id) != "shown" or seconds_left(offer_id) <= 0:
		EventBus.toast_requested.emit("Offer expired")
		return false
	var offer: Dictionary = DataLoader.offers.get(offer_id, {})
	var iap_id: String = str(offer.get("iap_id", ""))
	if iap_id == "":
		return false
	Analytics.log_event("offer_buy_initiate", {"offer": offer_id, "iap": iap_id})
	return IapCatalog.purchase(iap_id)

static func dismiss(offer_id: String) -> void:
	if _status(offer_id) == "shown":
		_set_status(offer_id, "dismissed")
		Analytics.log_event("offer_dismissed", {"offer": offer_id})

## When a purchase completes, every shown offer pointing at that product is bought.
static func _on_iap_completed(product_id: String) -> void:
	for offer_id in DataLoader.offers.keys():
		if _status(offer_id) == "shown" and str(DataLoader.offers[offer_id].get("iap_id", "")) == product_id:
			_set_status(offer_id, "bought")
			Analytics.log_event("offer_bought", {"offer": offer_id, "iap": product_id})
