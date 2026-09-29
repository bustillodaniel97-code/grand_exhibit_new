extends SceneTree
## End-to-end catalog -> save -> fake store, with real filesystem failures.
var failures := 0
var gs: Node
var ss: Node
var svc: Node
var catalog: GDScript

class Store:
	extends RefCounted
	signal purchases_updated(purchases: Array)
	signal purchase_consumed(token: String)
	var consumed: Array = []
	var disk_at_consume: Dictionary = {}
	var save_path: String
	func consumePurchase(token: String) -> void:
		disk_at_consume = JSON.parse_string(FileAccess.get_file_as_string(save_path))
		consumed.append(token)
		purchase_consumed.emit(token)
	func startConnection() -> void:
		pass
	func queryPurchases(_type: String) -> void:
		pass

func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
	print("PASS " if ok else "FAIL ", message)

func _init() -> void:
	call_deferred("run")

func receipt(token: String, product: String = "gems_pouch") -> Dictionary:
	return {"product_id": product, "purchase_token": token, "purchase_state": 1}

func run() -> void:
	gs = root.get_node("GameState")
	ss = root.get_node("SaveSystem")
	svc = root.get_node("IAPService")
	ss.set_process(false)
	svc.set_process(false)
	root.get_node("Economy").set_process(false)
	gs.reset_to_new_game()
	gs.ready_flag = true
	var path: String = ss.save_path()
	for suffix in ["", ".bak", ".tmp", ".bak.tmp", ".corrupt"]:
		DirAccess.remove_absolute(path + suffix)
	catalog = load("res://scripts/monetization/iap_catalog.gd")
	var backend: RefCounted = load("res://scripts/monetization/play_billing.gd").new()
	var store := Store.new()
	store.save_path = path
	backend._set_plugin_for_test(store)
	backend.start()
	svc._use_billing_for_test(backend)
	var completed: Array = []
	root.get_node("EventBus").iap_completed.connect(func(pid: String) -> void: completed.append(pid))

	gs.gems = 41
	check(ss.save_now(), "initial save commits")
	gs.gems = 42
	check(ss.save_now(), "second generation commits")
	check(int(ss._read_envelope(path + ".bak")["state"]["gems"]) == 41, "previous valid generation retained")
	# Interrupted temp never replaces or outranks the primary.
	var f := FileAccess.open(path + ".tmp", FileAccess.WRITE)
	f.store_string("{interrupted")
	f.close()
	gs.gems = 0
	check(ss.load_game() and gs.gems == 42, "restart ignores incomplete temporary save")
	# A corrupt primary falls back to the known-good generation.
	f = FileAccess.open(path, FileAccess.WRITE)
	f.store_string("{damaged")
	f.close()
	check(ss.load_game() and gs.gems == 41, "corrupt primary recovers previous valid progress")
	check(FileAccess.file_exists(path + ".corrupt"), "damaged evidence quarantined separately")
	gs.ready_flag = true
	check(ss.save_now(), "recovered profile can save again")
	# Fail backup replacement after writing/verifying the new temporary file.
	DirAccess.remove_absolute(path + ".bak")
	DirAccess.make_dir_absolute(path + ".bak")
	gs.gems = 999
	check(not ss.save_now() and ss.last_save_error == "replace_backup", "backup replacement failure is reported")
	check(int(ss._read_envelope(path)["state"]["gems"]) == 41, "late write failure preserves committed primary")
	DirAccess.remove_absolute(path + ".bak")
	DirAccess.remove_absolute(path + ".tmp")
	gs.gems = 41
	var before: int = gs.gems
	var grant: int = int(root.get_node("DataLoader").get_iap("gems_pouch")["grants"]["gems"])
	# Use a directory at the exact temp path to cause a real open failure.
	DirAccess.make_dir_absolute(path + ".tmp")
	store.purchases_updated.emit([receipt("durable-1")])
	check(store.consumed.is_empty(), "failed disk write cannot consume purchase")
	check(completed.is_empty(), "failed disk write cannot announce completion")
	check(ss.last_save_error == "open_temp", "write failure is surfaced")
	check(gs.gems == before + grant, "grant staged exactly once in memory")
	check(int(ss._read_envelope(path)["state"]["gems"]) == before, "failed commit preserves primary")
	DirAccess.remove_absolute(path + ".tmp")
	store.purchases_updated.emit([receipt("durable-1")])
	check(store.consumed == ["durable-1"], "retry settles only after successful commit")
	check(gs.gems == before + grant, "retry does not double grant")
	check(completed.size() == 1, "completion announced once after persistence")
	check(int(store.disk_at_consume["state"]["gems"]) == before + grant, "reward exists on disk when store consumes")
	check("durable-1" in store.disk_at_consume["state"]["rv_state"]["_iap_receipts"], "receipt and reward share committed envelope")
	# Discard all player state and reload disk before store redelivery.
	gs.reset_to_new_game()
	check(ss.load_game(), "profile reload succeeds after settlement")
	gs.ready_flag = true
	store.purchases_updated.emit([receipt("durable-1")])
	check(gs.gems == before + grant, "post-restart redelivery does not double grant")
	check(completed.size() == 1, "post-restart duplicate is not a new completion")
	# Older unsettled tokens must survive more than the former 64-token cap.
	for i in range(70):
		catalog._redeem_receipt("other-%d" % i)
	store.purchases_updated.emit([receipt("durable-1")])
	check(gs.gems == before + grant, "older receipt survives many newer purchases")
	var consumed_before: int = store.consumed.size()
	store.purchases_updated.emit([receipt("unknown-1", "nonexistent_product")])
	check(store.consumed.size() == consumed_before, "unknown product never consumed")
	gs.ready_flag = false
	store.purchases_updated.emit([receipt("startup-1")])
	check(store.consumed.size() == consumed_before, "startup receipt waits for profile readiness")
	gs.ready_flag = true
	store.purchases_updated.emit([receipt("startup-1")])
	check(gs.gems == before + 2 * grant, "startup receipt recovers when profile becomes ready")
	svc.billing = null
	for suffix in ["", ".bak", ".tmp", ".bak.tmp", ".corrupt"]:
		DirAccess.remove_absolute(path + suffix)
	print("purchase durability: %d failure(s)" % failures)
	quit(0 if failures == 0 else 1)
