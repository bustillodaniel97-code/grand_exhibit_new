extends Node
## IAPService — store-kit agnostic purchase stub. Debug: all purchases succeed.
## Real implementation swaps in Google Play Billing / App Store StoreKit plugin.

signal iap_result(product_id: String, success: bool)

var debug_iap: bool = true

func purchase(product_id: String) -> void:
	Analytics.iap_funnel("purchase_start", product_id)
	if not debug_iap:
		await get_tree().create_timer(0.2).timeout
		iap_result.emit(product_id, false)
		return
	await get_tree().create_timer(0.4).timeout
	iap_result.emit(product_id, true)

func localized_price(product_id: String) -> String:
	var def: Dictionary = DataLoader.get_iap(product_id)
	return str(def.get("price_usd", "$0.99"))
