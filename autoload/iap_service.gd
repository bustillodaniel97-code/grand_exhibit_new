extends Node
## IAPService — store-kit agnostic purchase stub. Real implementation swaps in
## Google Play Billing / StoreKit behind the same three methods.
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

const _SIM_ROUNDTRIP_SECONDS := 0.3

var debug_iap: bool = _default_debug_iap()

var _order_counter: int = 0

static func _default_debug_iap() -> bool:
	return OS.is_debug_build() and not OS.has_feature("release")

func purchase(product_id: String) -> void:
	if not debug_iap:
		# No billing SDK wired: fail honestly. Nothing is granted and nothing is charged.
		await get_tree().create_timer(0.2).timeout
		iap_result.emit(product_id, false, {"reason": "no_billing_sdk"})
		return
	await get_tree().create_timer(_SIM_ROUNDTRIP_SECONDS).timeout
	iap_result.emit(product_id, true, _mint_receipt(product_id))

## Re-deliver entitlements the account already owns. The stub reports the
## non-consumables recorded locally; the real one queries the billing client.
func restore_purchases() -> void:
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
	var def: Dictionary = DataLoader.get_iap(product_id)
	return str(def.get("price_usd", "$0.99"))
