extends RefCounted
class_name PlayBillingBackend
## play_billing.gd — Google Play Billing transport behind IAPService.
##
## WHAT THIS IS. IAPService owns the interface the game calls; this owns the
## conversation with Play. The split matters because Play Billing is not a
## request/response API — it is a RECONCILIATION API. You do not "make a
## purchase"; you launch a flow, and then Play tells you, possibly minutes later,
## possibly on the next app launch, possibly more than once, what the account
## actually owns. Everything awkward below follows from that.
##
## THE FOUR THINGS THAT LOSE REAL MONEY, and where each is handled:
##
##  1. UNACKNOWLEDGED PURCHASES ARE AUTO-REFUNDED. Play reverses any purchase not
##     acknowledged within three days. Every terminal purchase therefore has to
##     be either consumed (consumables) or acknowledged (non-consumables) —
##     `_settle()`. Forgetting this does not fail loudly; it silently refunds
##     paying customers three days later.
##  2. RE-DELIVERY. Play re-sends unacknowledged purchases on every reconnect, so
##     the same purchase_token arrives repeatedly. Granting is idempotent because
##     iap_catalog redeems each token exactly once (`rv_state._iap_receipts`);
##     this layer must not "helpfully" mint a fresh token per delivery, or that
##     dedup is defeated.
##  3. PENDING. A pending purchase (cash/voucher payment) is NOT a purchase yet.
##     Granting on pending is free money for the player. It is reported as an
##     explicit non-success with reason "pending" and settled only when it later
##     arrives as PURCHASED.
##  4. REVOKED / REFUNDED. An entitlement that disappears from queryPurchases is
##     gone — refunded or charged back — and must be withdrawn, otherwise a
##     refund is a free permanent unlock.
##
## PLUGIN BINDING IS THE UNVERIFIED PART. The Godot Play Billing plugin has
## shipped under several names with drifting method signatures, so the singleton
## and its methods are probed rather than assumed, and a missing plugin degrades
## to "no billing" instead of crashing. The STATE MACHINE here is fully covered
## by tests/monetization/test_play_billing.gd against a fake plugin; what still
## needs a device is that the real plugin's method and signal names match the
## candidates listed in _SINGLETON_NAMES / _call_any.

## Play's own constants. Named rather than inlined because a bare `2` in a
## purchase-state comparison is exactly the sort of thing that reads as
## "purchased" to a reviewer and means "pending".
const PURCHASE_STATE_UNSPECIFIED := 0
const PURCHASE_STATE_PURCHASED := 1
const PURCHASE_STATE_PENDING := 2

const BILLING_OK := 0
const BILLING_USER_CANCELED := 1
const BILLING_ITEM_ALREADY_OWNED := 7

## Candidate names the plugin has shipped under.
const _SINGLETON_NAMES: Array[String] = [
	"GodotGooglePlayBilling", "GooglePlayBilling", "PlayBilling",
]

signal connected()
signal connect_failed(reason: String)
## One settled purchase. `receipt` carries purchase_token/order_id/product_id and
## is what iap_catalog dedupes on.
signal purchase_settled(product_id: String, receipt: Dictionary)
signal purchase_failed(product_id: String, reason: String)
## Localized catalog from Play: Array of per-product Dictionaries. Emitted when
## the plugin answers a details query; IAPService caches the price strings so
## the store never presents an authored fallback as a live offer.
signal product_details_received(details: Array)
## Non-consumables the account currently owns, after a reconciliation sweep.
signal ownership_reconciled(product_ids: Array)
## An entitlement Play no longer reports — refunded, charged back or revoked.
signal ownership_revoked(product_ids: Array)

var _plugin: Object = null
var _connected: bool = false
## product_id -> normalized details ({price_string, raw}). Filled only from
## Play answers; never from authored data, so a missing entry honestly means
## "Play did not report this product".
var product_details: Dictionary = {}
## purchase_token -> receipt metadata, awaiting durable delivery/settlement.
var _in_flight: Dictionary = {}
## Non-consumable product ids seen in the last reconciliation, so a later sweep
## can tell "still owned" from "refunded".
var _known_owned: Dictionary = {}

# ------------------------------------------------------------------ discovery

## True when a real billing plugin is present. Callers use this to decide between
## the production path and the stub; it is deliberately not cached across calls
## so a test can install a double after construction.
func available() -> bool:
	return _plugin != null or _resolve_plugin() != null

## Inject a fake plugin. Tests use this; nothing in the game does.
func _set_plugin_for_test(obj: Object) -> void:
	_plugin = obj

func _resolve_plugin() -> Object:
	if _plugin != null:
		return _plugin
	for name in _SINGLETON_NAMES:
		if Engine.has_singleton(name):
			_plugin = Engine.get_singleton(name)
			return _plugin
	return null

## Call the first method the plugin actually implements. The plugin's API has
## drifted across versions (purchase/purchaseProduct, querySkuDetails/
## queryProductDetails), and guessing wrong should degrade, not crash.
func _call_any(names: Array, args: Array = []) -> Variant:
	var p: Object = _resolve_plugin()
	if p == null:
		return null
	for n in names:
		if p.has_method(str(n)):
			return p.callv(str(n), args)
	push_warning("PlayBilling: plugin implements none of %s" % str(names))
	return null

func _connect_signal(sig: String, target: Callable) -> void:
	var p: Object = _resolve_plugin()
	if p == null or not p.has_signal(sig):
		return
	if not p.is_connected(sig, target):
		p.connect(sig, target)

# ----------------------------------------------------------------- connection

func start() -> bool:
	var p: Object = _resolve_plugin()
	if p == null:
		return false
	_connect_signal("connected", _on_connected)
	_connect_signal("disconnected", _on_disconnected)
	_connect_signal("connect_error", _on_connect_error)
	_connect_signal("purchases_updated", _on_purchases_updated)
	_connect_signal("purchase_error", _on_purchase_error)
	_connect_signal("query_purchases_response", _on_query_purchases_response)
	_connect_signal("sku_details_response", _on_product_details_response)
	_connect_signal("query_product_details_response", _on_product_details_response)
	_connect_signal("product_details_response", _on_product_details_response)
	_connect_signal("purchase_acknowledged", _on_acknowledged)
	_connect_signal("purchase_consumed", _on_consumed)
	_connect_signal("purchase_acknowledgement_error", _on_settle_error)
	_connect_signal("purchase_consumption_error", _on_settle_error)
	_call_any(["startConnection", "start_connection"])
	return true

func is_connected_to_store() -> bool:
	return _connected

func _on_connected() -> void:
	_connected = true
	Analytics.log_event("billing_connected", {})
	connected.emit()
	# Reconcile immediately. This is the path that recovers a purchase the player
	# made while the app was closed, and the one that finally acknowledges a
	# purchase whose grant crashed mid-flight last session.
	reconcile()

func _on_disconnected() -> void:
	_connected = false
	Analytics.log_event("billing_disconnected", {})

func _on_connect_error(code: int, msg: String = "") -> void:
	_connected = false
	Analytics.log_event("billing_connect_error", {"code": code, "msg": msg})
	connect_failed.emit("code_%d" % code)

# ------------------------------------------------------------------- purchase

func purchase(product_id: String) -> bool:
	if not _connected:
		purchase_failed.emit(product_id, "not_connected")
		return false
	Analytics.iap_funnel("store_flow", product_id, {})
	_call_any(["purchase", "purchaseProduct", "purchase_product"], [product_id])
	return true

func _on_purchase_error(code: int, msg: String = "") -> void:
	# A cancel is not an error worth alarming the player about; it is the single
	# most common outcome of opening a store sheet.
	var reason: String = "cancelled" if code == BILLING_USER_CANCELED else "code_%d" % code
	if code == BILLING_ITEM_ALREADY_OWNED:
		# The account owns it but our local record does not. Reconciling is the
		# fix, not an error message — this is the reinstall case.
		reason = "already_owned"
		reconcile()
	Analytics.iap_funnel("failed", "", {"reason": reason, "msg": msg})
	purchase_failed.emit("", reason)

func _on_purchases_updated(purchases: Array) -> void:
	for entry in purchases:
		if entry is Dictionary:
			_handle_purchase(entry as Dictionary, false)

# ------------------------------------------------------------- reconciliation

## Ask Play what the account actually owns and settle anything outstanding.
## Called on connect and on resume; safe to call repeatedly.
func reconcile() -> void:
	_call_any(["queryPurchases", "query_purchases"], ["inapp"])

# ------------------------------------------------------------ product details

## Ask Play for localized prices/availability. Safe to call repeatedly; answers
## arrive on product_details_received. A missing plugin degrades to no answer
## (callers treat that as unavailable) instead of crashing.
func query_product_details(product_ids: Array) -> void:
	if product_ids.is_empty():
		return
	_call_any(["querySkuDetails", "queryProductDetails", "query_product_details"],
		[{"product_ids": product_ids, "type": "inapp"}])

func _on_product_details_response(response: Variant) -> void:
	var items: Array = []
	if response is Array:
		items = response
	elif response is Dictionary:
		var d: Dictionary = response
		for key in ["products", "sku_details", "skuDetails", "product_details"]:
			if d.get(key) is Array:
				items = d.get(key)
				break
	for entry in items:
		if not (entry is Dictionary):
			continue
		var e: Dictionary = entry
		var pid := ""
		for key in ["product_id", "productId", "sku", "id"]:
			if str(e.get(key, "")) != "":
				pid = str(e.get(key))
				break
		if pid == "":
			continue
		var price := ""
		for key in ["price_string", "price", "localized_price", "formatted_price",
				"priceString", "localizedPrice", "formattedPrice"]:
			if str(e.get(key, "")) != "":
				price = str(e.get(key))
				break
		product_details[pid] = {"price_string": price, "raw": e}
	if not items.is_empty():
		product_details_received.emit(items)

## Platform price string for one product, or "" when Play did not report it.
## Empty is an honest answer (unavailable/unknown), never a fallback.
func platform_price(product_id: String) -> String:
	return str((product_details.get(product_id, {}) as Dictionary).get("price_string", ""))

func _on_query_purchases_response(response: Variant) -> void:
	var purchases: Array = []
	if response is Dictionary:
		var d: Dictionary = response
		if int(d.get("status", BILLING_OK)) != BILLING_OK:
			Analytics.log_event("billing_query_failed", {"status": d.get("status")})
			return
		purchases = d.get("purchases", [])
	elif response is Array:
		purchases = response

	var seen_non_consumable: Array = []
	for entry in purchases:
		if not (entry is Dictionary):
			continue
		var pur: Dictionary = entry
		var pid: String = _product_of(pur)
		if _is_non_consumable(pid) \
				and int(pur.get("purchase_state", PURCHASE_STATE_PURCHASED)) == PURCHASE_STATE_PURCHASED:
			seen_non_consumable.append(pid)
		_handle_purchase(pur, true)

	# Anything previously owned and now absent has been refunded or revoked.
	# Withdrawing it is not optional: without this, a refund buys a permanent
	# ad-free upgrade for free.
	var revoked: Array = []
	for pid in _known_owned.keys():
		if str(pid) not in seen_non_consumable:
			revoked.append(str(pid))
	_known_owned.clear()
	for pid in seen_non_consumable:
		_known_owned[pid] = true

	if not revoked.is_empty():
		Analytics.log_event("billing_ownership_revoked", {"products": revoked})
		ownership_revoked.emit(revoked)
	ownership_reconciled.emit(seen_non_consumable)

# --------------------------------------------------------------- purchase flow

func _handle_purchase(pur: Dictionary, from_query: bool) -> void:
	var pid: String = _product_of(pur)
	var token: String = str(pur.get("purchase_token", pur.get("purchaseToken", "")))
	if token == "":
		return
	var state: int = int(pur.get("purchase_state", PURCHASE_STATE_PURCHASED))

	if state == PURCHASE_STATE_PENDING:
		# Deliberately NOT a grant. The player has committed to pay but has not
		# paid; it will arrive as PURCHASED later, or expire.
		Analytics.iap_funnel("pending", pid, {})
		purchase_failed.emit(pid, "pending")
		return

	if state != PURCHASE_STATE_PURCHASED:
		return

	_in_flight[token] = {"product_id": pid,
		"acknowledged": bool(pur.get("is_acknowledged", pur.get("isAcknowledged", false)))}
	# This signal delivers a receipt; it is NOT confirmation of disk persistence.
	# Only the catalog's successful save can authorize confirm_delivery().
	purchase_settled.emit(pid, {
		"product_id": pid, "purchase_token": token,
		"order_id": str(pur.get("order_id", pur.get("orderId", ""))),
		"purchase_time": int(pur.get("purchase_time", pur.get("purchaseTime", 0))),
		"from_query": from_query,
	})

func confirm_delivery(token: String) -> void:
	if not _in_flight.has(token):
		return
	var delivery: Dictionary = _in_flight[token]
	_settle(str(delivery["product_id"]), token, bool(delivery["acknowledged"]))

## Consumables are consumed so they can be bought again; non-consumables are
## acknowledged so Play stops re-delivering and does not auto-refund them.
func _settle(product_id: String, token: String, already_acknowledged: bool) -> void:
	if _is_non_consumable(product_id):
		if already_acknowledged:
			_in_flight.erase(token)
			return
		_call_any(["acknowledgePurchase", "acknowledge_purchase"], [token])
	else:
		_call_any(["consumePurchase", "consume_purchase"], [token])

func _on_acknowledged(token: String) -> void:
	Analytics.log_event("billing_acknowledged", {})
	_in_flight.erase(token)

func _on_consumed(token: String) -> void:
	Analytics.log_event("billing_consumed", {})
	_in_flight.erase(token)

## An unsettled purchase is a three-day fuse: Play refunds it if it is never
## acknowledged. Leaving the token in flight means the next reconcile() retries.
func _on_settle_error(token: String, code: int = -1, msg: String = "") -> void:
	Analytics.log_event("billing_settle_error",
		{"code": code, "msg": msg})

func pending_settlements() -> int:
	return _in_flight.size()

# ---------------------------------------------------------------------- helpers

func _product_of(pur: Dictionary) -> String:
	if pur.has("product_id"):
		return str(pur["product_id"])
	if pur.has("sku"):
		return str(pur["sku"])
	var products: Variant = pur.get("products", pur.get("skus", null))
	if products is Array and not (products as Array).is_empty():
		return str((products as Array)[0])
	return ""

## Non-consumable = the catalogue says it confers a permanent entitlement.
## Driven by data, not a hardcoded id list, so adding a second permanent unlock
## needs no code change here.
func _is_non_consumable(product_id: String) -> bool:
	return str(DataLoader.get_iap(product_id).get("entitlement", "")) != ""
