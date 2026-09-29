extends RefCounted
## app_store.gd — Apple StoreKit transport behind IAPService (iOS).
##
## The iOS twin of play_billing.gd: same signals and methods, so IAPService,
## iap_catalog and the store screen don't know which store they talk to. It
## drives Godot's official iOS in-app-store plugin (godot-ios-plugins,
## singleton "InAppStore"), which answers through a queue of events the game
## polls, not through signals — hence poll(), which IAPService calls every frame.
##
## What differs from Play, and where it's handled:
##
##  1. FINISH, DON'T ACKNOWLEDGE. A StoreKit transaction stays in the queue, and
##     is re-delivered on every launch, until it is finished. Auto-finish is
##     turned off so a transaction is finished only after iap_catalog has saved
##     the grant (confirm_delivery). A crash between payment and save therefore
##     re-delivers the purchase instead of losing it; iap_catalog's receipt
##     dedupe (the transaction id) keeps a re-delivery from granting twice.
##  2. NO SILENT RESTORE. restore_purchases can put up an Apple ID sign-in
##     sheet, so it only runs when the player taps Restore (restore()). Periodic
##     reconcile() just retries finishing delivered transactions.
##  3. RESTORE HAS NO RELIABLE "DONE". Plugin versions differ on whether they
##     post a completion event, so a restore sweep also closes itself a few
##     seconds after its last restored transaction.
##  4. REFUNDS aren't visible to the app without server receipt validation, so
##     ownership_revoked is never emitted here (App Store Server Notifications
##     are the place for that).
##
## PLUGIN BINDING is probed, not assumed, like the Play backend: a missing or
## differently named plugin degrades to "no billing". The event handling is
## covered by tests/monetization/test_app_store.gd against a fake plugin.

const _SINGLETON_NAMES: Array[String] = ["InAppStore", "IOSInAppStore", "StoreKit"]
const RESTORE_SETTLE_MS := 4000

signal connected()
signal connect_failed(reason: String)
signal purchase_settled(product_id: String, receipt: Dictionary)
signal purchase_failed(product_id: String, reason: String)
signal product_details_received(details: Array)
signal ownership_reconciled(product_ids: Array)
signal ownership_revoked(product_ids: Array)

var _plugin: Object = null
var _started := false
## product_id -> {price_string, raw}. Filled only from App Store answers.
var product_details: Dictionary = {}
## transaction_id -> product_id: delivered to the game, not yet finished.
var _in_flight: Dictionary = {}
## Non-consumables seen during the current restore sweep.
var _restored: Array = []
var _restoring := false
var _restore_last_ms := 0

func available() -> bool:
	return _plugin != null or _resolve_plugin() != null

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

func _call(method: String, args: Array = []) -> Variant:
	var p := _resolve_plugin()
	if p == null or not p.has_method(method):
		return null
	return p.callv(method, args)

# ----------------------------------------------------------------- connection

## StoreKit needs no connection handshake: the payment queue is always there.
func start() -> bool:
	if _resolve_plugin() == null:
		return false
	_call("set_auto_finish_transaction", [false])
	_started = true
	Analytics.log_event("billing_connected", {"store": "app_store"})
	connected.emit()
	return true

func is_connected_to_store() -> bool:
	return _started

## Drain the plugin's event queue. IAPService calls this every frame.
func poll() -> void:
	var p := _resolve_plugin()
	if p == null or not p.has_method("get_pending_event_count"):
		return
	var guard := 0
	while int(p.call("get_pending_event_count")) > 0 and guard < 64:
		guard += 1
		var ev: Variant = p.call("pop_pending_event")
		if ev is Dictionary:
			_handle_event(ev as Dictionary)
	if _restoring and Time.get_ticks_msec() - _restore_last_ms > RESTORE_SETTLE_MS:
		_finish_restore()

func _handle_event(ev: Dictionary) -> void:
	match str(ev.get("type", "")):
		"product_info":
			_on_product_info(ev)
		"purchase":
			_on_purchase(ev)
		"restore":
			_on_restore(ev)

# ------------------------------------------------------------ product details

func query_product_details(product_ids: Array) -> void:
	if product_ids.is_empty():
		return
	_call("request_product_info", [{"product_ids": PackedStringArray(product_ids)}])

func _on_product_info(ev: Dictionary) -> void:
	if str(ev.get("result", "ok")) != "ok":
		Analytics.log_event("billing_details_failed", {"store": "app_store", "error": str(ev.get("error", ""))})
		return
	var ids: Array = Array(ev.get("ids", []))
	var localized: Array = Array(ev.get("localized_prices", []))
	var prices: Array = Array(ev.get("prices", []))
	var items: Array = []
	for i in ids.size():
		var pid := str(ids[i])
		var price := str(localized[i]) if i < localized.size() else ""
		if price == "" and i < prices.size():
			price = str(prices[i])
		product_details[pid] = {"price_string": price, "raw": {"index": i}}
		items.append({"product_id": pid, "price_string": price})
	if not items.is_empty():
		product_details_received.emit(items)

func platform_price(product_id: String) -> String:
	return str((product_details.get(product_id, {}) as Dictionary).get("price_string", ""))

# ------------------------------------------------------------------- purchase

func purchase(product_id: String) -> bool:
	if not _started:
		purchase_failed.emit(product_id, "not_connected")
		return false
	Analytics.iap_funnel("store_flow", product_id, {})
	var err: Variant = _call("purchase", [{"product_id": product_id}])
	if err != null and int(err) != OK:
		purchase_failed.emit(product_id, "code_%d" % int(err))
		return false
	return true

func _on_purchase(ev: Dictionary) -> void:
	var pid := str(ev.get("product_id", ""))
	var result := str(ev.get("result", ""))
	if result == "progress":
		return
	if result != "ok":
		var msg := str(ev.get("error", result))
		var reason := "cancelled" if (result == "cancelled" or msg.to_lower().contains("cancel")) else "error"
		Analytics.iap_funnel("failed", pid, {"reason": reason, "msg": msg})
		purchase_failed.emit(pid, reason)
		return
	var tid := str(ev.get("transaction_id", ""))
	if pid == "" or tid == "":
		return
	_in_flight[tid] = pid
	# A receipt, not confirmation that the grant is saved: only confirm_delivery
	# (after iap_catalog's save) finishes the transaction.
	purchase_settled.emit(pid, {"product_id": pid, "purchase_token": tid, "order_id": tid,
		"purchase_time": int(Time.get_unix_time_from_system()), "from_query": false})

## Finish the transaction once the grant is durably saved.
func confirm_delivery(token: String) -> void:
	if not _in_flight.has(token):
		return
	_call("finish_transaction", [str(_in_flight[token])])
	_in_flight.erase(token)

func pending_settlements() -> int:
	return _in_flight.size()

## Periodic retry hook (IAPService calls it while settlements are pending and on
## resume). StoreKit re-delivers unfinished transactions by itself, so there is
## nothing to query; never restore here (it can prompt for an Apple ID).
func reconcile() -> void:
	pass

# -------------------------------------------------------------------- restore

## Player-initiated Restore Purchases.
func restore() -> void:
	_restored.clear()
	_restoring = true
	_restore_last_ms = Time.get_ticks_msec()
	_call("restore_purchases")

func _on_restore(ev: Dictionary) -> void:
	var result := str(ev.get("result", "ok"))
	if result == "completed" or result == "finished":
		_finish_restore()
		return
	if result != "ok":
		Analytics.log_event("billing_restore_failed", {"store": "app_store", "error": str(ev.get("error", ""))})
		_finish_restore()
		return
	var pid := str(ev.get("product_id", ""))
	if pid != "" and _is_non_consumable(pid) and pid not in _restored:
		_restored.append(pid)
	_restore_last_ms = Time.get_ticks_msec()
	# A restored transaction also has to be finished, or it is re-delivered.
	if pid != "":
		_call("finish_transaction", [pid])

func _finish_restore() -> void:
	if not _restoring:
		return
	_restoring = false
	ownership_reconciled.emit(_restored.duplicate())

func _is_non_consumable(product_id: String) -> bool:
	return str(DataLoader.get_iap(product_id).get("entitlement", "")) != ""
