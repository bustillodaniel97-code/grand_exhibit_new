extends Node
## IAPService — store-agnostic purchases. Google Play Billing (play_billing.gd)
## or StoreKit (app_store.gd) behind the same three methods, and a simulator in
## debug builds without either plugin.
##
## Changes from v1 that a real billing SDK forces anyway:
##  · `iap_result` carries a receipt. Play Billing hands back a purchase token and
##    an order id; grants must be idempotent on that token, because Billing
##    re-delivers unacknowledged purchases on the next query. Without it, one
##    purchase could be granted twice by the store's own retry.
##  · `restore_purchases()`. Any non-consumable (the ad-free upgrade) needs a
##    restore path or the store review fails and reinstalls lose what they bought.
##  · `debug_iap` is derived from the build. Hardcoded `true` meant a release APK
##    completed every purchase without charging.
##  · No funnel logging here. v1 logged "purchase_start" while iap_catalog logged
##    "initiate" for the same step, so the funnel showed a 50% drop that did not
##    exist. iap_catalog owns the funnel; this layer owns the transport.

signal iap_result(product_id: String, success: bool, receipt: Dictionary)
signal restore_completed(product_ids: Array)
## Emitted when platform product details land (prices/availability may have
## changed). The store listens and rebuilds price labels.
signal prices_updated()

const PlayBilling := preload("res://scripts/monetization/play_billing.gd")
const AppStore := preload("res://scripts/monetization/app_store.gd")
const Entitlements := preload("res://scripts/monetization/entitlements.gd")

const _SIM_ROUNDTRIP_SECONDS := 0.3

var debug_iap: bool = _default_debug_iap()

## Production transport. Non-null on a device with the Play Billing plugin
## installed; null in the editor, the test suite and any desktop build, which is
## what keeps those on the simulator path.
var billing: RefCounted = null

var _order_counter: int = 0
var _retry_elapsed: float = 0.0
## Platform price strings by product id, filled ONLY from Play answers.
## Empty/absent means Play did not report the product: unavailable, never a
## fabricated fallback. The simulator path (no billing) uses catalog prices.
var _platform_prices: Dictionary = {}
## True once the bound backend has answered at least one details query.
## Before that, real-billing availability is unknown (treated as unavailable).
var _details_ready: bool = false

static func _default_debug_iap() -> bool:
	return OS.is_debug_build() and not OS.has_feature("release")

func _ready() -> void:
	_init_billing()

## Bring up the real store if a plugin is present.
##
## Note what this deliberately does NOT do: fall back to the simulator when the
## store is unreachable. A release build that cannot talk to Play must sell
## nothing rather than hand out free purchases, and debug_iap is derived from the
## build type so the simulator is not reachable there at all.
func _init_billing() -> void:
	# Google Play on Android, StoreKit on iOS: whichever plugin the build carries.
	var backend: RefCounted = PlayBilling.new()
	if not backend.available():
		backend = AppStore.new()
		if not backend.available():
			return
	_bind_billing(backend)
	backend.start()

func _bind_billing(backend: RefCounted) -> void:
	backend.purchase_settled.connect(_on_backend_settled)
	backend.purchase_failed.connect(_on_backend_failed)
	backend.ownership_reconciled.connect(_on_backend_reconciled)
	backend.ownership_revoked.connect(_on_backend_revoked)
	if backend.has_signal("product_details_received"):
		backend.product_details_received.connect(_on_platform_details)
	billing = backend
	request_product_details()

## Test seam: install a backend directly. Nothing in the game calls this.
func _use_billing_for_test(backend: RefCounted) -> void:
	_bind_billing(backend)

## Test seam: inject platform details without a plugin. Nothing in the game
## calls this.
func set_product_details_for_test(details: Dictionary) -> void:
	_platform_prices = details.duplicate()
	_details_ready = true
	prices_updated.emit()

## Test seam: drop the bound backend and clear platform state.
func _clear_billing_for_test() -> void:
	billing = null
	_platform_prices.clear()
	_details_ready = false

func using_real_billing() -> bool:
	return billing != null

func _on_backend_settled(product_id: String, receipt: Dictionary) -> void:
	# Connect even when receipts arrive before the store screen has opened.
	load("res://scripts/monetization/iap_catalog.gd")._ensure_connected()
	iap_result.emit(product_id, true, receipt)

func confirm_delivery(token: String) -> void:
	if billing != null:
		billing.confirm_delivery(token)

func _process(delta: float) -> void:
	# Event-queue stores (StoreKit) answer only when polled.
	if billing != null and billing.has_method("poll"):
		billing.poll()
	if billing == null or not GameState.ready_flag:
		return
	_retry_elapsed += delta
	if _retry_elapsed >= 15.0:
		_retry_elapsed = 0.0
		if billing.pending_settlements() > 0:
			billing.reconcile()

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_RESUMED and billing != null:
		billing.reconcile()
		request_product_details()

func _on_backend_failed(product_id: String, reason: String) -> void:
	iap_result.emit(product_id, false, {"reason": reason})

func _on_backend_reconciled(product_ids: Array) -> void:
	Entitlements.restore(product_ids)
	restore_completed.emit(product_ids)

## A refund or chargeback removes the entitlement. Without this, refunding the
## ad-free upgrade keeps it forever.
func _on_backend_revoked(product_ids: Array) -> void:
	var removed: int = Entitlements.withdraw(product_ids)
	if removed > 0:
		Analytics.log_event("entitlement_revoked",
			{"products": product_ids, "removed": removed})

func purchase(product_id: String) -> void:
	if billing != null:
		# No platform details for this product: fail honestly rather than
		# charging through an unverified price. Nothing is granted.
		if not is_available(product_id):
			await get_tree().create_timer(0.2).timeout
			iap_result.emit(product_id, false, {"reason": "unavailable"})
			return
		# Terminates via purchases_updated / purchase_error on the backend, which
		# is what emits iap_result. Play may answer in seconds, or in days.
		billing.purchase(product_id)
		return
	if not debug_iap:
		# No billing SDK wired: fail honestly. Nothing is granted and nothing is charged.
		await get_tree().create_timer(0.2).timeout
		iap_result.emit(product_id, false, {"reason": "no_billing_sdk"})
		return
	await get_tree().create_timer(_SIM_ROUNDTRIP_SECONDS).timeout
	iap_result.emit(product_id, true, _mint_receipt(product_id))

## Re-deliver entitlements the account already owns. The real path asks Play what
## the account owns; the stub reports the non-consumables recorded locally.
func restore_purchases() -> void:
	if billing != null:
		# Answers on ownership_reconciled -> restore_completed. StoreKit's restore
		# may ask for an Apple ID, so it has its own player-initiated entry point.
		if billing.has_method("restore"):
			billing.restore()
		else:
			billing.reconcile()
		return
	var owned: Array = []
	var ents: Dictionary = GameState.rv_state.get("entitlements", {}) if GameState else {}
	for pid in ents.get("owned", []):
		owned.append(str(pid))
	restore_completed.emit(owned)

func _mint_receipt(product_id: String) -> Dictionary:
	_order_counter += 1
	return {
		"product_id": product_id,
		"purchase_token": "sim-%s-%d-%d" % [product_id, Time.get_ticks_usec(), _order_counter],
		"order_id": "SIM.%d.%d" % [Time.get_unix_time_from_system(), _order_counter],
		"purchase_time": int(Time.get_unix_time_from_system()),
	}

func localized_price(product_id: String) -> String:
	# Real billing: the platform catalog is the only honest price. Empty means
	# Play did not report this product (unavailable/unknown/offline) — never
	# present the authored fallback as a live offer.
	if billing != null:
		return str(_platform_prices.get(product_id, ""))
	var def: Dictionary = DataLoader.get_iap(product_id)
	return str(def.get("price_usd", "$0.99"))

## True when this product may be offered right now. Simulator builds (no
## billing) always may; real-billing builds may only offer products Play
## actually reported, after at least one details answer.
func is_available(product_id: String) -> bool:
	if billing == null:
		return true
	if not _details_ready:
		return false
	return _platform_prices.has(product_id)

## Display text for store cards: platform price when real, catalog price on the
## simulator, and an honest Unavailable label when Play did not report it.
func store_price_text(product_id: String) -> String:
	var price := localized_price(product_id)
	if price != "":
		return price
	return "Unavailable"

## Ask the bound backend for localized details over every catalog product.
## Safe before connect (the answer arrives on product_details_received) and
## safe to repeat on resume/reconnect.
func request_product_details() -> void:
	if billing == null:
		return
	var ids: Array = DataLoader.iap_products.keys()
	if ids.is_empty():
		return
	if billing.has_method("query_product_details"):
		billing.query_product_details(ids)

func _on_platform_details(details: Array) -> void:
	_platform_prices.clear()
	for entry in details:
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
		# The backend already normalized most shapes; accept its cache too.
		if price == "" and billing != null and billing.get("product_details") is Dictionary:
			price = str((billing.get("product_details") as Dictionary).get(pid, {}).get("price_string", ""))
		if price != "":
			_platform_prices[pid] = price
	_details_ready = true
	prices_updated.emit()
