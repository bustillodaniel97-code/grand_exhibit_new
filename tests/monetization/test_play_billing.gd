extends SceneTree
## test_play_billing.gd — the Play Billing state machine, against a fake plugin.
##
## The real SDK cannot run here, and that is fine, because the SDK is not where
## the money is lost. Play Billing is a reconciliation API: it re-delivers,
## it settles late, it auto-refunds anything left unacknowledged for three days,
## and it silently takes entitlements back on a chargeback. Every one of those is
## OUR logic to get right, and every one is exercised below.
##
## What this does NOT prove is that the plugin's method and signal names match
## the candidates PlayBillingBackend probes for. That needs a device, and it is
## recorded as such in docs/ANDROID_RELEASE.md.
##
## Run: godot --headless --path <repo> -s tests/monetization/test_play_billing.gd


## load() at runtime, NOT preload(). Under -s the main script compiles before
## autoload names are reliably bound, and these helpers name
## GameState/DataLoader/Analytics at class scope. Preloading them compiles
## them too early: the calls then no-op against a dead GDScript, no check()
## ever runs, and the suite reports a FALSE GREEN.
var PlayBilling: GDScript
var Entitlements: GDScript

var failures := 0
var DL: Node
var GS: Node

func check(cond: bool, msg: String) -> void:
	if cond:
		print("  PASS ", msg)
	else:
		failures += 1
		printerr("  FAIL ", msg)

func _init() -> void:
	call_deferred("run")

# --------------------------------------------------------------- fake plugin
## Stands in for the Godot Play Billing singleton. Records what the adapter asked
## Play to do, and lets a test push Play's answers back in whatever order a real
## device would — including the awkward orders.
class FakePlugin:
	extends Object

	signal connected()
	signal disconnected()
	signal connect_error(code: int, msg: String)
	signal purchases_updated(purchases: Array)
	signal purchase_error(code: int, msg: String)
	signal query_purchases_response(response: Variant)
	signal purchase_acknowledged(token: String)
	signal purchase_consumed(token: String)

	var started: bool = false
	var purchase_calls: Array = []
	var acknowledged: Array = []
	var consumed: Array = []
	var queries: int = 0

	func startConnection() -> void:
		started = true

	func purchase(product_id: String) -> void:
		purchase_calls.append(product_id)

	func queryPurchases(_type: String) -> void:
		queries += 1

	func acknowledgePurchase(token: String) -> void:
		acknowledged.append(token)
		purchase_acknowledged.emit(token)

	func consumePurchase(token: String) -> void:
		consumed.append(token)
		purchase_consumed.emit(token)

func _purchase(pid: String, token: String, state: int = 1, ack: bool = false) -> Dictionary:
	return {
		"product_id": pid, "purchase_token": token, "order_id": "GPA." + token,
		"purchase_state": state, "is_acknowledged": ack,
		"purchase_time": 1785380000,
	}

# ---------------------------------------------------------------------- setup

func run() -> void:
	for pair in [["event_bus", "EventBus"], ["data_loader", "DataLoader"],
			["clock_guard", "ClockGuard"], ["analytics", "Analytics"],
			["ad_service", "AdService"], ["iap_service", "IAPService"],
			["game_state", "GameState"], ["save_system", "SaveSystem"],
			["economy", "Economy"]]:
		if root.has_node(pair[1]):
			continue
		var n: Node = (load("res://autoload/%s.gd" % pair[0]) as GDScript).new()
		n.name = pair[1]
		root.add_child(n)
	PlayBilling = load("res://scripts/monetization/play_billing.gd") as GDScript
	Entitlements = load("res://scripts/monetization/entitlements.gd") as GDScript
	var SS: Node = root.get_node("SaveSystem")
	SS.set_process(false)
	SS.autosave_interval_sec = 1 << 30
	GS = root.get_node("GameState")
	DL = root.get_node("DataLoader")
	GS.reset_to_new_game()
	GS.ready_flag = true

	_test_consumable_is_consumed()
	_test_non_consumable_is_acknowledged()
	_test_pending_grants_nothing()
	_test_redelivery_is_idempotent()
	_test_cancel_is_not_an_error_state()
	_test_refund_withdraws_entitlement()
	_test_restore_reports_ownership()
	_test_no_plugin_means_no_real_billing()

	print("---")
	print("play billing: %d failure(s)" % failures)
	quit(0 if failures == 0 else 1)

## A backend wired to a fresh fake, already "connected".
func _connected_backend() -> Array:
	var fake := FakePlugin.new()
	var backend: RefCounted = PlayBilling.new()
	backend._set_plugin_for_test(fake)
	backend.start()
	fake.connected.emit()
	return [backend, fake]

## The catalogue's ids for each shape, read from data rather than hardcoded so
## this test follows a rename of the products.
func _consumable_id() -> String:
	for pid in DL.iap_products.keys():
		if str(DL.iap_products[pid].get("entitlement", "")) == "":
			return str(pid)
	return ""

func _non_consumable_id() -> String:
	for pid in DL.iap_products.keys():
		if str(DL.iap_products[pid].get("entitlement", "")) != "":
			return str(pid)
	return ""

# ---------------------------------------------------------------------- tests

func _test_consumable_is_consumed() -> void:
	print("-- a consumable is CONSUMED so it can be bought again --")
	var pair: Array = _connected_backend()
	var backend: RefCounted = pair[0]
	var fake: FakePlugin = pair[1]
	var pid: String = _consumable_id()
	check(pid != "", "the catalogue has a consumable (%s)" % pid)

	var settled: Array = []
	backend.purchase_settled.connect(func(p: String, r: Dictionary) -> void:
		settled.append([p, r]))

	check(backend.purchase(pid), "the purchase flow launches")
	check(fake.purchase_calls.has(pid), "the plugin was asked to purchase it")
	fake.purchases_updated.emit([_purchase(pid, "tok-consume-1")])

	check(settled.size() == 1, "exactly one settlement was reported (%d)" % settled.size())
	check(settled.size() == 1 and str(settled[0][0]) == pid, "for the right product")
	check(settled.size() == 1 and str((settled[0][1] as Dictionary)["purchase_token"]) == "tok-consume-1",
		"carrying Play's own purchase token, which is what dedup keys on")
	check(fake.consumed.is_empty(), "receipt delivery alone cannot consume")
	backend.confirm_delivery("tok-consume-1")
	check(fake.consumed.has("tok-consume-1"), "and it was CONSUMED")
	check(not fake.acknowledged.has("tok-consume-1"), "not acknowledged")
	check(backend.pending_settlements() == 0, "nothing left unsettled")

func _test_non_consumable_is_acknowledged() -> void:
	print("-- a non-consumable is ACKNOWLEDGED or Play refunds it in 3 days --")
	var pair: Array = _connected_backend()
	var backend: RefCounted = pair[0]
	var fake: FakePlugin = pair[1]
	var pid: String = _non_consumable_id()
	check(pid != "", "the catalogue has a non-consumable (%s)" % pid)

	fake.purchases_updated.emit([_purchase(pid, "tok-ack-1")])
	check(fake.acknowledged.is_empty(), "receipt delivery alone cannot acknowledge")
	backend.confirm_delivery("tok-ack-1")
	check(fake.acknowledged.has("tok-ack-1"), "it was acknowledged")
	check(not fake.consumed.has("tok-ack-1"), "and NOT consumed — consuming it would resell a permanent unlock")
	check(backend.pending_settlements() == 0, "the settlement completed")

	# Already-acknowledged re-delivery must not be acknowledged twice.
	fake.acknowledged.clear()
	fake.purchases_updated.emit([_purchase(pid, "tok-ack-1", 1, true)])
	backend.confirm_delivery("tok-ack-1")
	check(fake.acknowledged.is_empty(),
		"an already-acknowledged purchase is not acknowledged again")

func _test_pending_grants_nothing() -> void:
	print("-- a PENDING purchase is not a purchase --")
	var pair: Array = _connected_backend()
	var backend: RefCounted = pair[0]
	var fake: FakePlugin = pair[1]
	var pid: String = _consumable_id()

	var settled: Array = []
	var failed: Array = []
	backend.purchase_settled.connect(func(p: String, _r: Dictionary) -> void: settled.append(p))
	backend.purchase_failed.connect(func(p: String, why: String) -> void: failed.append([p, why]))

	fake.purchases_updated.emit([_purchase(pid, "tok-pending", 2)])
	check(settled.is_empty(), "nothing was granted for a pending purchase")
	check(failed.size() == 1 and str(failed[0][1]) == "pending",
		"and it was reported as explicitly pending, not as a generic failure")
	check(not fake.consumed.has("tok-pending"), "a pending purchase is not settled")

	# It later completes.
	fake.purchases_updated.emit([_purchase(pid, "tok-pending", 1)])
	check(settled.size() == 1, "when it finally clears, it grants exactly once")
	backend.confirm_delivery("tok-pending")
	check(fake.consumed.has("tok-pending"), "and is settled then")

func _test_redelivery_is_idempotent() -> void:
	print("-- Play re-delivers; the grant layer must not double-pay --")
	var pair: Array = _connected_backend()
	var backend: RefCounted = pair[0]
	var fake: FakePlugin = pair[1]
	var pid: String = _consumable_id()

	var tokens: Array = []
	backend.purchase_settled.connect(func(_p: String, r: Dictionary) -> void:
		tokens.append(str(r["purchase_token"])))

	for _i in 3:
		fake.purchases_updated.emit([_purchase(pid, "tok-same")])
	check(tokens.size() == 3, "the transport reports every delivery (%d)" % tokens.size())
	var unique: Dictionary = {}
	for t in tokens:
		unique[t] = true
	check(unique.size() == 1,
		"but they all carry the SAME token, so iap_catalog can dedupe them")
	check(str(tokens[0]) == "tok-same", "the token is Play's, not a freshly minted one")

func _test_cancel_is_not_an_error_state() -> void:
	print("-- a user cancel is the commonest outcome, not a fault --")
	var pair: Array = _connected_backend()
	var backend: RefCounted = pair[0]
	var fake: FakePlugin = pair[1]

	var failed: Array = []
	backend.purchase_failed.connect(func(_p: String, why: String) -> void: failed.append(why))
	fake.purchase_error.emit(1, "user canceled")
	check(failed.size() == 1 and str(failed[0]) == "cancelled",
		"cancel is reported as 'cancelled' (got '%s')" % (str(failed[0]) if failed.size() > 0 else "none"))

	# ITEM_ALREADY_OWNED is the reinstall case: reconcile rather than complain.
	var q_before: int = fake.queries
	fake.purchase_error.emit(7, "already owned")
	check(fake.queries > q_before,
		"an already-owned error triggers reconciliation instead of a dead end")

func _test_refund_withdraws_entitlement() -> void:
	print("-- a refund takes the entitlement back --")
	var pair: Array = _connected_backend()
	var backend: RefCounted = pair[0]
	var fake: FakePlugin = pair[1]
	var pid: String = _non_consumable_id()

	var revoked: Array = []
	backend.ownership_revoked.connect(func(ids: Array) -> void: revoked.append_array(ids))

	# Own it.
	fake.query_purchases_response.emit({"status": 0, "purchases": [_purchase(pid, "tok-own", 1, true)]})
	# record_purchase is what the real grant path calls; restore() alone only
	# re-applies ownership and deliberately does not touch the purchase count.
	Entitlements.record_purchase(pid)
	Entitlements.restore([pid])
	check(Entitlements.owns(pid), "the entitlement is recorded")
	check(revoked.is_empty(), "nothing revoked while it is still owned")

	# Next sweep: Play no longer reports it.
	fake.query_purchases_response.emit({"status": 0, "purchases": []})
	check(revoked.has(pid), "the disappearance was detected as a revocation")
	var removed: int = Entitlements.withdraw(revoked)
	check(removed == 1, "withdraw removed it (%d)" % removed)
	check(not Entitlements.owns(pid),
		"and the ad-free upgrade is gone — a refund must not be a free permanent unlock")
	check(Entitlements.has_ever_purchased(),
		"but the purchase COUNT stands: they did once pay, so no first-purchase offer returns")

func _test_restore_reports_ownership() -> void:
	print("-- restore reports what the account actually owns --")
	var pair: Array = _connected_backend()
	var backend: RefCounted = pair[0]
	var fake: FakePlugin = pair[1]
	var pid: String = _non_consumable_id()

	# append_array, NOT assignment: a GDScript lambda captures locals by VALUE, so
	# `reconciled = ids` inside the closure rebinds only the closure's own copy.
	# Mutating the captured Array works because both names point at one object.
	var reconciled: Array = []
	backend.ownership_reconciled.connect(func(ids: Array) -> void:
		reconciled.append_array(ids))

	backend.reconcile()
	check(fake.queries > 0, "reconcile queried the store")
	fake.query_purchases_response.emit({"status": 0,
		"purchases": [_purchase(pid, "tok-restore", 1, true)]})
	check(reconciled.has(pid), "the owned non-consumable came back (%s)" % str(reconciled))

	# A failed query must report nothing rather than an empty-and-therefore-
	# "you own nothing" answer, which would revoke on a network blip.
	reconciled.clear()
	var revoked: Array = []
	backend.ownership_revoked.connect(func(ids: Array) -> void: revoked.append_array(ids))
	fake.query_purchases_response.emit({"status": 3, "purchases": []})
	check(reconciled.is_empty() and revoked.is_empty(),
		"a FAILED query neither reconciles nor revokes")

func _test_no_plugin_means_no_real_billing() -> void:
	print("-- no plugin: sell nothing, never simulate --")
	var backend: RefCounted = PlayBilling.new()
	check(not backend.available(),
		"with no Android plugin present the backend reports unavailable")
	var svc: Node = root.get_node("IAPService")
	check(not svc.using_real_billing(),
		"so IAPService stays off the production path in this environment")
	check(not backend.purchase("anything"),
		"and a purchase attempt through a disconnected backend refuses")
