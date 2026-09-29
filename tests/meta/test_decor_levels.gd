extends SceneTree
## Decor is priced in each museum's economy and levels up like a station:
## every level raises its income bonus and decor points and pays reputation.
## The 3D floor stands placed pieces at their decor anchors.

var failures := 0

func check(ok: bool, message: String) -> void:
	if ok:
		print("PASS: ", message)
	else:
		failures += 1
		printerr("FAIL: ", message)

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var gs: Node = root.get_node("GameState")
	var ec: Node = root.get_node("Economy")
	root.get_node("SaveSystem").set_process(false)
	ec.set_process(false)
	root.get_node("DataLoader").reload_all()
	gs.reset_to_new_game()
	gs.ready_flag = true
	var DS: GDScript = load("res://scripts/meta/decor_system.gd")
	var BN: GDScript = load("res://scripts/core/big_number.gd")
	var m1: BigNumber = DS.cash_cost("oak_bench", "whispering_pines")
	var m3: BigNumber = DS.cash_cost("oak_bench", "grand_river")
	check(m1.eq(BN.from_parts(5.0, 2)), "museum one pays the authored price (500)")
	check(m3.gt(m1.scale(1e6)), "museum three prices it in its own economy (%s)" % m3.to_notation())
	var vid: String = gs.current_venue
	gs.cash = BN.from_parts(1.0, 30)
	check(DS.buy_decor(vid, "oak_bench"), "buy an oak bench")
	check(DS.level(vid, "oak_bench") == 1, "new decor starts at level 1")
	var mult1: float = ec.income_multiplier(vid)
	var pts1: float = DS.venue_decor_points(vid)
	var cost: BigNumber = DS.upgrade_cost(vid, "oak_bench")
	check(cost.gt(DS.cash_cost("oak_bench", vid)), "upgrading costs more than buying")
	var rep_before: BigNumber = gs.reputation_xp.copy()
	check(DS.upgrade(vid, "oak_bench"), "upgrade the bench")
	check(DS.level(vid, "oak_bench") == 2, "it is level 2")
	check(ec.income_multiplier(vid) > mult1, "a level raises museum income")
	check(DS.venue_decor_points(vid) > pts1, "a level raises decor points")
	check(gs.reputation_xp.gt(rep_before), "a level pays reputation")
	for _i in 20:
		DS.upgrade(vid, "oak_bench")
	check(DS.level(vid, "oak_bench") == DS.MAX_LEVEL, "levels cap at %d" % DS.MAX_LEVEL)
	check(not DS.upgrade(vid, "oak_bench"), "no upgrade past the cap")
	check(absf(DS.piece_mult(vid, "oak_bench") - (1.0 + 0.03 * (1.0 + 0.6 * 9.0))) < 0.0001, "level 10 bench: +19% income")
	DS.remove_decor(vid, "oak_bench")
	check(not DS.can_upgrade(vid, "oak_bench"), "stored decor cannot be upgraded")
	check(DS.place_decor(vid, "oak_bench") and DS.level(vid, "oak_bench") == DS.MAX_LEVEL, "levels survive storage")

	# The 3D floor shows it.
	var Venue3D: GDScript = load("res://scenes/venue3d/venue_3d.gd")
	var w: Node3D = Venue3D.new()
	w.venue_id = vid
	var vp := SubViewport.new()
	vp.own_world_3d = true
	root.add_child(vp)
	vp.add_child(w)
	await process_frame
	check(w._decor_nodes.size() == 1, "placed decor stands in the 3D museum")
	gs.gems = 1000
	check(DS.buy_decor(vid, "brass_fountain"), "buy a fountain")
	await process_frame
	check(w._decor_nodes.size() == 2, "a new purchase appears immediately")
	DS.remove_decor(vid, "brass_fountain")
	w.refresh_decor()
	check(w._decor_nodes.size() == 1, "storing a piece removes it from the floor")
	vp.queue_free()
	await process_frame
	print("RESULT: ", "OK" if failures == 0 else "FAILED (%d)" % failures)
	quit(1 if failures > 0 else 0)
