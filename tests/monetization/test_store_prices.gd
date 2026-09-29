extends SceneTree
## test_store_prices.gd — STORE-01 regression: displayed prices must come from
## platform product details when real billing is bound, never from an authored
## fallback presented as a live offer.
##
## Covers: simulator shows catalog; real billing before details is unavailable;
## details answer supplies regional prices verbatim; missing products stay
## unavailable and blocked; reconnect (late details) flips to available; the
## store card reads Unavailable instead of a fabricated price. Fake backend
## only — real SDK binding still needs device verification.

var failures := 0
var IAP: Node
var DL: Node
var GS: Node
var EventBus: Node

class FakeBilling:
	extends RefCounted
	signal purchase_settled(product_id: String, receipt: Dictionary)
	signal purchase_failed(product_id: String, reason: String)
	signal ownership_reconciled(product_ids: Array)
	signal ownership_revoked(product_ids: Array)
	signal product_details_received(details: Array)
	var purchase_calls: Array = []
	var detail_queries: Array = []
	var product_details: Dictionary = {}
	func available() -> bool:
		return true
	func start() -> bool:
		return true
	func purchase(product_id: String) -> bool:
		purchase_calls.append(product_id)
		return true
	func query_product_details(ids: Array) -> void:
		detail_queries.append(ids.duplicate())
	func pending_settlements() -> int:
		return 0
	func reconcile() -> void:
		pass
	func confirm_delivery(_token: String) -> void:
		pass

func check(ok: bool, message: String) -> void:
	if ok:
		print("  PASS ", message)
	else:
		failures += 1
		printerr("  FAIL ", message)

func _init() -> void:
	call_deferred("run")

func _first_product() -> String:
	var keys: Array = DL.iap_products.keys()
	keys.sort()
	return str(keys[0]) if not keys.is_empty() else ""

func _second_product(first: String) -> String:
	var keys: Array = DL.iap_products.keys()
	keys.sort()
	for k in keys:
		if str(k) != first:
			return str(k)
	return first

func run() -> void:
	for pair in [["event_bus", "EventBus"], ["data_loader", "DataLoader"],
			["clock_guard", "ClockGuard"], ["analytics", "Analytics"],
			["ad_service", "AdService"], ["iap_service", "IAPService"],
			["game_state", "GameState"], ["save_system", "SaveSystem"],
			["economy", "Economy"]]:
		if not root.has_node(pair[1]):
			var node: Node = load("res://autoload/%s.gd" % pair[0]).new()
			node.name = pair[1]
			root.add_child(node)
	IAP = root.get_node("IAPService")
	DL = root.get_node("DataLoader")
	GS = root.get_node("GameState")
	EventBus = root.get_node("EventBus")
	root.get_node("SaveSystem").set_process(false)
	root.get_node("Economy").set_process(false)
	GS.reset_to_new_game()
	GS.ready_flag = true
	IAP._clear_billing_for_test()
	IAP.debug_iap = true
	var IAPCat = load("res://scripts/monetization/iap_catalog.gd")
	var pid: String = _first_product()
	check(pid != "", "catalogue has at least one product")
	if pid == "":
		quit(1)
		return
	var other: String = _second_product(pid)
	var catalog_price: String = str(DL.get_iap(pid).get("price_usd", ""))

	# 1. Simulator (no billing): catalog price, always available.
	check(not IAP.using_real_billing(), "simulator has no real billing bound")
	check(IAP.localized_price(pid) == catalog_price, "simulator shows catalog price (%s)" % catalog_price)
	check(IAP.is_available(pid), "simulator product is available")
	check(IAPCat.blocked_reason(pid) != "unavailable", "simulator is never blocked as unavailable")

	# 2. Real billing before any details answer: unknown means unavailable.
	var fake := FakeBilling.new()
	IAP._use_billing_for_test(fake)
	check(IAP.using_real_billing(), "fake backend counts as real billing")
	check(IAP.localized_price(pid) == "", "no fabricated price before Play answers")
	check(not IAP.is_available(pid), "product unavailable until Play reports it")
	check(IAPCat.blocked_reason(pid) == "unavailable", "catalog blocks the unreported product")
	check(IAPCat.blocked_message(pid) == "Not available in your store right now",
		"unavailable has explicit player-facing copy")

	# 3. Unavailable purchase fails honestly without touching the backend.
	var results: Array = []
	var on_result := func(p: String, ok: bool, r: Dictionary) -> void:
		results.append([p, ok, r])
	IAP.iap_result.connect(on_result)
	IAP.purchase(pid)
	await create_timer(0.5).timeout
	check(fake.purchase_calls.is_empty(), "unavailable purchase never reaches the backend (no charge)")
	check(results.size() == 1 and results[0][1] == false
		and str((results[0][2] as Dictionary).get("reason", "")) == "unavailable",
		"unavailable purchase reports reason=unavailable")
	IAP.iap_result.disconnect(on_result)

	# 4. Details answer: regional price verbatim; unreported stays unavailable.
	IAP.set_product_details_for_test({pid: "€0,99"})
	check(IAP.localized_price(pid) == "€0,99", "platform regional price used verbatim")
	check(IAP.store_price_text(pid) == "€0,99", "store text shows the platform price")
	check(IAP.is_available(pid), "reported product becomes available")
	check(IAPCat.blocked_reason(pid) != "unavailable", "reported product no longer blocked")
	check(IAP.localized_price(other) == "", "unreported product still has no price")
	if other != pid:
		check(not IAP.is_available(other), "unreported product stays unavailable")
		check(IAP.store_price_text(other) == "Unavailable", "store shows Unavailable, not a fallback")

	# 5. Backend signal path: details emitted by the backend update the cache
	# (offline startup -> reconnect flow) and notify the store.
	var notified := [false]
	var on_prices := func() -> void: notified[0] = true
	IAP.prices_updated.connect(on_prices)
	fake.product_details_received.emit([{"product_id": other, "price": "$4.99"}])
	IAP._on_platform_details([{"product_id": other, "price": "$4.99"}])
	await process_frame
	check(IAP.localized_price(other) == "$4.99", "backend details land in the price cache")
	check(notified[0], "store notified via prices_updated")
	IAP.prices_updated.disconnect(on_prices)

	# 6. Store card honors availability instead of a fabricated price.
	var screen: Control = load("res://scenes/store/store_screen.tscn").instantiate()
	root.add_child(screen)
	await process_frame
	IAP.set_product_details_for_test({pid: "€0,99"})
	var card_missing: Button = screen._buy_button(other if other != pid else "__missing__",
		IAP.localized_price(other if other != pid else "__missing__"), Color.WHITE, 56)
	check(card_missing.text == "Unavailable", "store card reads Unavailable for unreported product")
	var card_live: Button = screen._buy_button(pid, IAP.localized_price(pid), Color.WHITE, 56)
	check(card_live.text == "€0,99", "store card shows the live platform price")
	card_missing.free()
	card_live.free()
	screen.queue_free()
	await process_frame

	IAP._clear_billing_for_test()
	IAP.debug_iap = true
	print("---")
	print("store prices: %d failure(s)" % failures)
	quit(0 if failures == 0 else 1)
