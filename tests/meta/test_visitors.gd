extends SceneTree
## Visitor types: reputation unlocks new visitors (weighted, dressed per type),
## VIPs pay a tip on a cooldown, tips unlock achievements and are saved, and in
## the 3D museum a VIP carries a tappable Tip! bubble that pays out.

var failures := 0

func check(ok: bool, message: String) -> void:
	if ok:
		print("PASS: ", message)
	else:
		failures += 1
		printerr("FAIL: ", message)

func _initialize() -> void:
	call_deferred("run")

func _set_rep(gs: Node, level: int) -> void:
	var th: Array = root.get_node("DataLoader").core["reputation"]["thresholds_mantissa"]
	gs.reputation_xp = BigNumber.from_float(float(th[level - 1]))

func _reachable(VS: GDScript) -> Dictionary:
	var seen := {}
	for i in 1000:
		seen[str(VS.pick(float(i) / 1000.0).get("id", ""))] = true
	return seen

func run() -> void:
	if not OS.has_environment("GRAND_EXHIBIT_TEST_RUN"):
		printerr("REFUSED: requires GRAND_EXHIBIT_TEST_RUN isolation"); quit(2); return
	var gs: Node = root.get_node("GameState")
	var ps: Node = root.get_node("PlatformServices")
	var ss: Node = root.get_node("SaveSystem")
	ss.set_process(false)
	var path: String = ss.save_path()
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)
	gs.reset_to_new_game()
	gs.ready_flag = true
	var VS: GDScript = load("res://scripts/meta/visitor_system.gd")

	check(VS.types().size() >= 8, "eight visitor types are defined")
	var early := _reachable(VS)
	check(early.keys().size() == 2 and early.has("local") and early.has("kids"), "a new museum sees only locals and little explorers")
	check(not VS.is_unlocked("collector"), "VIPs are locked at reputation 1")
	var at4: Array = VS.unlocked_at(4).map(func(t: Dictionary) -> String: return str(t["id"]))
	check("collector" in at4, "reputation 4 brings the first VIP (collectors)")
	_set_rep(gs, 12)
	var late := _reachable(VS)
	check(late.keys().size() == VS.types().size(), "at reputation 12 every type walks in (%d)" % late.keys().size())

	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var tourist: Dictionary = VS.dress({"hair": "#2B2320", "acc": ["acc_bow"]}, VS.type_def("tourist"), rng)
	check("acc_hat" in tourist["acc"] and "acc_camera" in tourist["acc"] and not ("acc_bow" in tourist["acc"]), "tourists wear the straw hat and camera")
	var kid: Dictionary = VS.dress({"hair": "#E8E4DC", "acc": []}, VS.type_def("kids"), rng)
	check(is_equal_approx(float(kid.get("scale", 1.0)), 0.78) and str(kid["hair"]) != "#E8E4DC", "little explorers are small and never grey")
	var royal: Dictionary = VS.dress({"acc": []}, VS.type_def("royal"), rng)
	check("acc_crown" in royal["acc"] and str(royal["type"]) == "royal", "royal patrons wear the crown")

	# Tips: seconds of income, one at a time.
	gs.add_cash(BigNumber.from_parts(1.0, 9))
	root.get_node("Economy").purchase_item_upgrade(gs.current_venue, "ticket", 0)
	var cps: BigNumber = root.get_node("Economy").current_cash_per_second()
	check(not cps.is_zero(), "the museum has income to tip from")
	check(VS.collect_tip("student").is_zero(), "a non-VIP never tips")
	check(VS.tip_ready(), "a tip starts ready")
	var before: BigNumber = gs.cash
	var tip: BigNumber = VS.collect_tip("collector")
	var want: BigNumber = cps.scale(30.0)
	check(absf(tip.to_float_approx() - want.to_float_approx()) <= want.to_float_approx() * 0.01, "a collector tips 30s of income")
	check(gs.cash.gt(before), "the tip is banked")
	check(not VS.tip_ready() and VS.seconds_to_tip() > 60, "then the tip cools down")
	check(VS.collect_tip("royal").is_zero(), "no second tip during the cooldown")
	check(ps.is_unlocked("FIRST_VIP"), "a VIP tip unlocks 'Very Important Visitor'")
	gs.visitors_state["tip_ready"] = 0
	VS.collect_tip("royal")
	check(ps.is_unlocked("ROYAL_VISIT"), "a royal tip unlocks 'By Royal Appointment'")
	check(VS.tips_collected() == 2, "tips are counted")
	VS.note_arrival("tourist")
	var saved: Dictionary = gs.to_save_dict()
	gs.reset_to_new_game()
	check(VS.tips_collected() == 0, "a new game forgets the guide")
	gs.from_save_dict(saved)
	check(VS.tips_collected() == 2 and VS.met_count("tourist") == 1, "the guide survives save and load")

	# In the museum: a VIP carries a Tip! bubble; tapping it pays.
	gs.reset_to_new_game()
	_set_rep(gs, 12)
	gs.settings["tutorial_step"] = 99
	var vp := SubViewport.new()
	vp.size = Vector2i(720, 1280)
	root.add_child(vp)
	vp.add_child((load("res://scenes/main.tscn") as PackedScene).instantiate())
	await create_timer(2.5).timeout
	var floor: Node = root.find_child("VenueFloor", true, false)
	var world: Node = floor.get("world")
	check(world != null, "the 3D museum is mounted")
	var ok := false
	for i in 40:
		if bool(world.get("_nav_ready")):
			ok = true
			break
		await create_timer(0.25).timeout
	check(ok, "the museum's navigation is ready")
	var views: Array = world.get("_views")
	var spot: Vector3 = (views[0] as Dictionary)["spot"]
	var vip: Node3D = world.call("_spawn", VS.dress({"acc": []}, VS.type_def("royal"), rng), spot)
	world.call("_visit", vip, true)
	check(vip.find_child("VipRing", true, false) != null, "a VIP walks on a gold ring")
	var carried := false
	for i in 20:
		await create_timer(0.2).timeout
		if world.get("tip_carrier") == vip:
			carried = true
			break
	check(carried, "the ready tip goes to the VIP in the museum")
	var btn: Button = floor.find_child("VipTip", true, false)
	check(btn != null, "the floor has a Tip! bubble")
	var cash_before: BigNumber = gs.cash
	vip.set_meta("vrequest", false)  # a plain tip; wishes are tests/meta/test_vip_requests.gd
	floor.call("_on_vip_tip")
	await process_frame
	check(gs.cash.gt(cash_before), "tapping the bubble banks the royal tip")
	check(world.get("tip_carrier") == null and not btn.visible, "the bubble is spent")

	vp.queue_free()
	await create_timer(0.5).timeout
	gs.reset_to_new_game()
	print("RESULT: ", "OK" if failures == 0 else "FAILED (%d)" % failures)
	quit(1 if failures > 0 else 0)
