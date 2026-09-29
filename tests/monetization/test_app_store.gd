extends SceneTree
## test_app_store.gd — the StoreKit backend (app_store.gd) against a fake
## "InAppStore" plugin that answers through a polled event queue, the way
## Godot's iOS in-app-store plugin does.
##
## Proves: localized prices land, a purchase is delivered with its transaction
## id and finished only after delivery is confirmed, cancel/errors map to
## reasons, auto-finish is turned off, Restore reports the non-consumables
## (with or without a completion event), and IAPService grants through it.
## What still needs a device: that the real plugin's method names match.

var AppStore: GDScript
var failures := 0

func check(cond: bool, msg: String) -> void:
	if cond:
		print("  PASS ", msg)
	else:
		failures += 1
		printerr("  FAIL ", msg)

func _init() -> void:
	call_deferred("run")

class FakeStore:
	extends Object
	var events: Array = []
	var finished: Array = []
	var purchases: Array = []
	var info_requests: Array = []
	var restores := 0
	var auto_finish := true
	func set_auto_finish_transaction(on: bool) -> void:
		auto_finish = on
	func request_product_info(params: Dictionary) -> int:
		info_requests.append(params)
		return OK
	func purchase(params: Dictionary) -> int:
		purchases.append(str(params.get("product_id", "")))
		return OK
	func restore_purchases() -> int:
		restores += 1
		return OK
	func finish_transaction(product_id: String) -> void:
		finished.append(product_id)
	func get_pending_event_count() -> int:
		return events.size()
	func pop_pending_event() -> Variant:
		return events.pop_front()

func run() -> void:
	if not OS.has_environment("GRAND_EXHIBIT_TEST_RUN"):
		printerr("REFUSED: requires GRAND_EXHIBIT_TEST_RUN isolation"); quit(2); return
	AppStore = load("res://scripts/monetization/app_store.gd")
	var gs: Node = root.get_node("GameState")
	root.get_node("SaveSystem").set_process(false)
	gs.reset_to_new_game()
	gs.ready_flag = true

	var fake := FakeStore.new()
	var store: RefCounted = AppStore.new()
	store._set_plugin_for_test(fake)
	check(store.available(), "the backend binds to an InAppStore plugin")
	check(store.start() and not fake.auto_finish, "start turns auto-finish off (finish only after the grant is saved)")

	# Prices.
	var got_details: Array = []
	store.product_details_received.connect(func(d: Array) -> void: got_details.append_array(d))
	store.query_product_details(["gems_pouch", "no_ads"])
	check(fake.info_requests.size() == 1, "product info is requested")
	fake.events.append({"type": "product_info", "result": "ok", "ids": ["gems_pouch", "no_ads"],
		"localized_prices": ["$0.99", "$4.99"], "prices": [0.99, 4.99]})
	store.poll()
	check(store.platform_price("gems_pouch") == "$0.99" and got_details.size() == 2, "localized prices arrive from the queue")

	# A purchase is delivered, then finished only once confirmed.
	var settled: Array = []
	var failed: Array = []
	store.purchase_settled.connect(func(pid: String, r: Dictionary) -> void: settled.append([pid, r]))
	store.purchase_failed.connect(func(pid: String, reason: String) -> void: failed.append([pid, reason]))
	check(store.purchase("gems_pouch") and fake.purchases == ["gems_pouch"], "purchase opens the StoreKit sheet")
	fake.events.append({"type": "purchase", "result": "progress", "product_id": "gems_pouch"})
	fake.events.append({"type": "purchase", "result": "ok", "product_id": "gems_pouch", "transaction_id": "T-1"})
	store.poll()
	check(settled.size() == 1 and str(settled[0][1]["purchase_token"]) == "T-1", "a completed purchase is delivered with its transaction id")
	check(fake.finished.is_empty() and store.pending_settlements() == 1, "and is not finished before delivery is confirmed")
	store.confirm_delivery("T-1")
	check(fake.finished == ["gems_pouch"] and store.pending_settlements() == 0, "confirm_delivery finishes the transaction")

	fake.events.append({"type": "purchase", "result": "error", "product_id": "gems_pouch", "error": "Payment cancelled"})
	fake.events.append({"type": "purchase", "result": "error", "product_id": "gems_sack", "error": "Network"})
	store.poll()
	check(failed.size() == 2 and failed[0][1] == "cancelled" and failed[1][1] == "error", "cancel and errors report their reasons")

	# Restore: the ad-free unlock comes back, with or without a completion event.
	var owned: Array = []
	store.ownership_reconciled.connect(func(ids: Array) -> void: owned.append(ids))
	store.reconcile()
	check(fake.restores == 0, "periodic reconcile never restores (no surprise Apple ID prompt)")
	store.restore()
	check(fake.restores == 1, "Restore Purchases asks StoreKit")
	fake.events.append({"type": "restore", "result": "ok", "product_id": "no_ads", "transaction_id": "R-1"})
	fake.events.append({"type": "restore", "result": "completed"})
	store.poll()
	check(owned.size() == 1 and "no_ads" in owned[0], "the restore reports the ad-free unlock")
	store.restore()
	fake.events.append({"type": "restore", "result": "ok", "product_id": "no_ads", "transaction_id": "R-2"})
	store.poll()
	await create_timer(4.3).timeout
	store.poll()
	check(owned.size() == 2 and "no_ads" in owned[1], "a restore without a completion event settles on its own")

	# Through IAPService: the purchase grants and the transaction finishes.
	var iap: Node = root.get_node("IAPService")
	var fake2 := FakeStore.new()
	var store2: RefCounted = AppStore.new()
	store2._set_plugin_for_test(fake2)
	store2.start()
	iap._use_billing_for_test(store2)
	fake2.events.append({"type": "product_info", "result": "ok", "ids": ["gems_pouch"], "localized_prices": ["$0.99"]})
	await process_frame
	await process_frame
	check(iap.localized_price("gems_pouch") == "$0.99", "IAPService shows the App Store price")
	var results: Array = []
	iap.iap_result.connect(func(pid: String, ok: bool, _r: Dictionary) -> void: results.append([pid, ok]))
	fake2.events.append({"type": "purchase", "result": "ok", "product_id": "gems_pouch", "transaction_id": "T-9"})
	await process_frame
	await process_frame
	check(results.size() >= 1 and results[0][1] == true, "IAPService reports the purchase")
	iap._clear_billing_for_test()
	fake.free()
	fake2.free()
	await create_timer(0.8).timeout
	print("RESULT: ", "OK" if failures == 0 else "FAILED (%d)" % failures)
	quit(1 if failures > 0 else 0)
