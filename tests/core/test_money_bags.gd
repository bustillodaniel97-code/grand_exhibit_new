extends SceneTree
## test_money_bags.gd — tip bags: satisfaction drives them, tapping banks once,
## and a bag tap must not fall through to the room underneath.
## Run: godot --headless --path <repo> -s tests/core/test_money_bags.gd

var failures: int = 0

const V := "whispering_pines"

var GS: Node
var EC: Node
var EB: Node
var DL: Node

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
	EB = root.get_node("EventBus")
	DL = root.get_node("DataLoader")
	DL.reload_all()
	EC.set_process(false)
	root.get_node("SaveSystem").set_process(false)

	_test_config_present()
	_test_scales_with_satisfaction()
	_test_value_tracks_progression()
	_test_collect_grants_once()
	_test_collect_does_not_touch_pending()
	_test_floor_tap_consumes()

	print("---")
	if failures == 0:
		print("ALL MONEY BAG CHECKS PASSED")
	quit(0 if failures == 0 else 1)

func _fresh() -> void:
	GS.reset_to_new_game()
	GS.ready_flag = true

func _test_config_present() -> void:
	print("config:")
	var c: Dictionary = DL.core.get("money_bags", {})
	check(not c.is_empty(), "money_bags block exists in balance_core")
	check(float(c.get("chance_min", -1.0)) > 0.0,
		"chance_min is above zero — a venue with a poor rating must still drop the "
		+ "occasional bag, or the feature reads as broken and cannot be learned")
	check(float(c.get("chance_max", 0.0)) > float(c.get("chance_min", 1.0)),
		"chance rises with satisfaction")
	check(int(c.get("max_alive", 0)) > 0, "a cap on live bags exists")

## The load-bearing claim: better service and decor mean more and bigger bags.
func _test_scales_with_satisfaction() -> void:
	print("satisfaction drives the drop:")
	_fresh()
	var low_chance: float = EC.bag_drop_chance(V)
	var low_value: float = (EC.bag_value(V) as BigNumber).to_float_approx()
	var low_stars: float = float(EC.venue_satisfaction(V).get("stars", 0.0))

	# Raise the venue: more service throughput and every decor piece placed.
	GS.set_dept_level(V, "ticket", "staff", 5)
	GS.set_dept_level(V, "ticket", "speed", 8)
	GS.set_dept_level(V, "archive", "staff", 5)
	GS.set_dept_level(V, "promotions", "staff", 2)
	var DS: GDScript = load("res://scripts/meta/decor_system.gd")
	GS.add_cash(BigNumber.from_float(1e14))
	GS.add_gems(100000)
	for did in DL.decor.keys():
		DS.buy_decor(V, str(did))

	var hi_stars: float = float(EC.venue_satisfaction(V).get("stars", 0.0))
	var hi_chance: float = EC.bag_drop_chance(V)
	var hi_value: float = (EC.bag_value(V) as BigNumber).to_float_approx()

	check(hi_stars > low_stars, "stars rose (%0.2f -> %0.2f)" % [low_stars, hi_stars])
	check(hi_chance > low_chance, "drop chance rose (%0.3f -> %0.3f)" % [low_chance, hi_chance])
	check(hi_value > low_value, "bag value rose with the rating")

func _test_value_tracks_progression() -> void:
	print("value is denominated in visitors, so it scales with the curve:")
	_fresh()
	var before: float = (EC.bag_value(V) as BigNumber).to_float_approx()
	GS.set_dept_level(V, "ticket", "value", 9)
	GS.set_dept_level(V, "promotions", "value", 9)
	var after: float = (EC.bag_value(V) as BigNumber).to_float_approx()
	check(after > before,
		"raising value-per-visitor raises the bag without a per-venue table (%f -> %f)"
			% [before, after])

func _test_collect_grants_once() -> void:
	print("collect banks exactly what was offered:")
	_fresh()
	var got: Array = []
	var cb := func(_v: String, amt: Variant) -> void: got.append(amt)
	EB.money_bag_collected.connect(cb)
	var amount: BigNumber = EC.bag_value(V)
	var cash_before: BigNumber = GS.cash
	var banked: BigNumber = EC.collect_bag(V, amount)
	EB.money_bag_collected.disconnect(cb)
	check(absf(banked.to_float_approx() - amount.to_float_approx()) < 0.001,
		"returned the full bag value")
	check(absf(GS.cash.to_float_approx() - cash_before.add(amount).to_float_approx()) < 0.001,
		"cash rose by exactly the bag")
	check(got.size() == 1, "money_bag_collected fired once")
	check(EC.collect_bag(V, BigNumber.zero()).is_zero(), "a zero bag banks nothing")

## A tip is fresh cash. Drawing it from pending would make tapping a bag steal
## from the porters instead of rewarding a well-run venue.
func _test_collect_does_not_touch_pending() -> void:
	print("a tip is fresh cash, not a draw against pending:")
	_fresh()
	GS.set_dept_level(V, "ticket", "staff", 3)
	GS.set_dept_level(V, "archive", "staff", 0)
	for _i in 10:
		EC._tick(0.5)
	var pending_before: BigNumber = GS.pending_cash.get(V, BigNumber.zero())
	check(not pending_before.is_zero(), "pending accrued")
	EC.collect_bag(V, EC.bag_value(V))
	var pending_after: BigNumber = GS.pending_cash.get(V, BigNumber.zero())
	check(absf(pending_before.to_float_approx() - pending_after.to_float_approx()) < 0.001,
		"venue pending is untouched by a bag collect")

## The regression that matters on a phone: a bag sitting inside a room must not
## fire the bag AND the room's upgrade sheet from one tap.
func _test_floor_tap_consumes() -> void:
	print("a bag tap does not fall through to the room:")
	_fresh()
	var VF: PackedScene = load("res://scenes/venue/floor/venue_floor.tscn")
	var floor_node: Control = VF.instantiate()
	root.add_child(floor_node)
	floor_node.set_size(Vector2(720, 760))

	var taps: Array = []
	floor_node.dept_selected.connect(func(d: String) -> void: taps.append(d))

	# Drop a bag in the middle of a real room, then tap exactly on it.
	var room_centre: Vector2 = floor_node.room_center("ticket")
	var g: Vector2 = floor_node.canvas_to_grid(room_centre)
	floor_node._drop_bag(g)
	check(floor_node.bag_count() == 1, "bag dropped")

	var consumed: bool = floor_node._try_tap_bag(room_centre)
	check(consumed, "the tap was consumed by the bag")
	check(floor_node.bag_count() == 0, "the bag was taken")
	check(taps.is_empty(), "no dept_selected was emitted — the room did not also open")

	# And a tap nowhere near a bag still reaches the room.
	floor_node.simulate_tap(room_centre)
	check(taps == ["ticket"], "a tap with no bag still opens the room (got %s)" % [taps])
	floor_node.queue_free()
