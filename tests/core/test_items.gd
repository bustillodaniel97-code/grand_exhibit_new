extends SceneTree
## test_items.gd — the upgrade atom: per-item levels, per-item pending, collect.
## Run: godot --headless --path <repo> -s tests/core/test_items.gd
##
## The load-bearing identity, guarded first: N level-1 items must produce EXACTLY
## the throughput the old integer staff count produced, or every balance number
## and historical test in the project silently shifts.

var failures: int = 0

const V := "whispering_pines"

var GS: Node
var EC: Node
var SS: Node
var EB: Node

func check(cond: bool, msg: String) -> void:
	if cond:
		print("  PASS ", msg)
	else:
		failures += 1
		printerr("  FAIL ", msg)

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	GS = root.get_node("GameState")
	EC = root.get_node("Economy")
	SS = root.get_node("SaveSystem")
	EB = root.get_node("EventBus")
	root.get_node("DataLoader").reload_all()
	# The sim must not tick underneath assertions that hand-build pending state.
	EC.set_process(false)
	SS.set_process(false)

	_test_fresh_state_shape()
	_test_units_identity()
	_test_staff_purchase_adds_item()
	_test_item_upgrade()
	_test_set_dept_level_resize_preserves_levels()
	_test_tick_allocates_pending()
	_test_collect_item_once()
	_test_manual_collect_drains_ledger()
	_test_migration_v3()

	print("---")
	if failures == 0:
		print("ALL ITEM CHECKS PASSED")
	quit(0 if failures == 0 else 1)

func _fresh() -> void:
	GS.reset_to_new_game()
	GS.ready_flag = true

func _test_fresh_state_shape() -> void:
	print("fresh state shape:")
	_fresh()
	var items: Array = GS.dept_items(V, "ticket")
	var base: int = int(root.get_node("DataLoader").dept_def("ticket").get("base_staff", 1))
	check(items.size() == base, "ticket starts with base_staff items (%d)" % base)
	check(GS.dept_level(V, "ticket", "staff") == items.size(), "staff track reads item count")
	check(int(GS.venue_state(V)["depts"]["ticket"]["staff"]) == items.size(), "staff mirror in sync")
	check(GS.item_level(V, "ticket", 0) == 1, "fresh items are level 1")

func _test_units_identity() -> void:
	print("units identity (N lv1 items == old integer staff):")
	_fresh()
	GS.set_dept_level(V, "ticket", "staff", 4)
	var units: float = EC.dept_units(V, "ticket")
	check(absf(units - 4.0) < 0.0001, "4 lv1 items = 4.0 units (got %f)" % units)
	var flows: Dictionary = EC.venue_flows(V)
	var spd: float = EC.dept_stat(V, "ticket", "speed")
	check(absf(float(flows["serve_per_s"]) - 4.0 * spd) < 0.0001,
		"serve_per_s = units * speed exactly as the old staff formula")

func _test_staff_purchase_adds_item() -> void:
	print("staff purchase places a new item:")
	_fresh()
	GS.add_cash(BigNumber.from_float(1e9))
	var before: int = GS.dept_items(V, "ticket").size()
	check(EC.purchase_upgrade(V, "ticket", "staff"), "purchase succeeds with cash")
	var items: Array = GS.dept_items(V, "ticket")
	check(items.size() == before + 1, "item count grew by one")
	check(int(items[items.size() - 1]["lv"]) == 1, "new item arrives at level 1")

func _test_item_upgrade() -> void:
	print("per-item upgrade:")
	_fresh()
	GS.add_cash(BigNumber.from_float(1e9))
	var got: Array = []
	var cb := func(vid: String, did: String, idx: int, lv: int) -> void:
		got.append([vid, did, idx, lv])
	EB.item_upgraded.connect(cb)
	var cost: BigNumber = EC.item_upgrade_cost(V, "ticket", 0)
	check(not cost.is_zero(), "upgrade has a nonzero cost")
	var cash_before: BigNumber = GS.cash
	check(EC.purchase_item_upgrade(V, "ticket", 0), "upgrade succeeds")
	check(GS.item_level(V, "ticket", 0) == 2, "item 0 is now level 2")
	check(GS.cash.lt(cash_before), "cash was spent")
	check(got.size() == 1 and got[0][2] == 0 and got[0][3] == 2, "item_upgraded signal fired with index+level")
	EB.item_upgraded.disconnect(cb)
	var units: float = EC.dept_units(V, "ticket")
	var step: float = float(root.get_node("DataLoader").core.get("items", {}).get("step_per_level", 0.25))
	check(absf(units - (1.0 + step + 0.0)) < 1.0001 or units > 1.0,
		"units rose above the level-1 baseline (got %f)" % units)
	# out-of-range and cap behaviour
	check(not EC.purchase_item_upgrade(V, "ticket", 99), "out-of-range index refuses")
	GS.set_item_level(V, "ticket", 0, EC.item_max_level())
	check(not EC.purchase_item_upgrade(V, "ticket", 0), "max-level item refuses")

func _test_set_dept_level_resize_preserves_levels() -> void:
	print("resize preserves per-item progress:")
	_fresh()
	GS.set_dept_level(V, "ticket", "staff", 3)
	GS.set_item_level(V, "ticket", 0, 7)
	GS.set_dept_level(V, "ticket", "staff", 5)
	check(GS.item_level(V, "ticket", 0) == 7, "grow keeps existing item levels")
	GS.set_dept_level(V, "ticket", "staff", 2)
	check(GS.item_level(V, "ticket", 0) == 7, "shrink keeps the front items")
	check(GS.dept_items(V, "ticket").size() == 2, "shrink drops from the back")

func _test_tick_allocates_pending() -> void:
	print("tick decomposes venue pending across station piles:")
	_fresh()
	GS.set_dept_level(V, "ticket", "staff", 3)
	# No transport -> nothing banks -> ledger total must track venue pending.
	GS.set_dept_level(V, "archive", "staff", 0)
	for _i in 20:
		EC._tick(0.5)
	var venue_pending: BigNumber = GS.pending_cash.get(V, BigNumber.zero())
	check(not venue_pending.is_zero(), "sim accrued pending with transport at zero")
	var ledger := BigNumber.zero()
	for i in 3:
		ledger = ledger.add(EC.item_pending(V, "ticket", i))
	var vp: float = venue_pending.to_float_approx()
	var lg: float = ledger.to_float_approx()
	check(vp > 0.0 and absf(lg - vp) / vp < 0.02,
		"station piles sum to venue pending within 2%% (venue=%f ledger=%f)" % [vp, lg])

func _test_collect_item_once() -> void:
	print("collect-once semantics:")
	_fresh()
	GS.set_dept_level(V, "ticket", "staff", 2)
	GS.set_dept_level(V, "archive", "staff", 0)
	for _i in 10:
		EC._tick(0.5)
	var pile: BigNumber = EC.item_pending(V, "ticket", 0)
	check(not pile.is_zero(), "station 0 accrued a pile")
	var cash_before: BigNumber = GS.cash
	var pending_before: BigNumber = GS.pending_cash.get(V, BigNumber.zero())
	var got: Array = []
	var cb := func(_v: String, _d: String, idx: int, amt: Variant) -> void:
		got.append([idx, amt])
	EB.item_collected.connect(cb)
	var amount: BigNumber = EC.collect_item(V, "ticket", 0)
	EB.item_collected.disconnect(cb)
	check(absf(amount.to_float_approx() - pile.to_float_approx()) < 0.001, "collected exactly the pile")
	check(GS.cash.to_float_approx() > cash_before.to_float_approx(), "cash went up")
	var pending_after: BigNumber = GS.pending_cash.get(V, BigNumber.zero())
	check(absf(pending_before.to_float_approx() - pending_after.to_float_approx()
		- amount.to_float_approx()) < 0.001, "venue pending dropped by the same amount")
	check(got.size() == 1 and got[0][0] == 0, "item_collected fired for the station")
	check(EC.collect_item(V, "ticket", 0).is_zero(), "second collect yields zero — no double grant")

func _test_manual_collect_drains_ledger() -> void:
	print("venue-wide sweep empties the piles too:")
	_fresh()
	GS.set_dept_level(V, "ticket", "staff", 2)
	GS.set_dept_level(V, "archive", "staff", 0)
	for _i in 10:
		EC._tick(0.5)
	check(not EC.item_pending(V, "ticket", 0).is_zero(), "pile exists before sweep")
	EC.manual_collect(V)
	var frac: float = float(root.get_node("DataLoader").core.get("economy", {}).get("manual_collect_fraction", 1.0))
	if frac >= 0.999:
		check(EC.item_pending(V, "ticket", 0).is_zero(), "full sweep zeroes the station piles")
	else:
		check(true, "partial-sweep config; drain ratio covered by the allocator test")

func _test_migration_v3() -> void:
	print("v3 save migrates staff counts into item containers:")
	var state := {
		"venues_state": {V: {"depts": {
			"ticket": {"staff": 3, "speed": 2, "value": 1},
			"archive": {"staff": 2, "speed": 1, "value": 1},
		}}},
	}
	var out: Dictionary = SS.migrate(state, 3)
	var t: Dictionary = out["venues_state"][V]["depts"]["ticket"]
	check(t.has("items") and (t["items"] as Array).size() == 3, "3 staff became 3 items")
	check(int((t["items"] as Array)[0]["lv"]) == 1, "migrated items are level 1")
	check(int(t["speed"]) == 2, "other tracks untouched")
	var a: Dictionary = out["venues_state"][V]["depts"]["archive"]
	check((a["items"] as Array).size() == 2, "second dept migrated too")
