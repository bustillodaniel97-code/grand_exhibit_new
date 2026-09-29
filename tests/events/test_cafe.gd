extends SceneTree
## Pop-Up Café (timed event area): unlock at reputation, cycle of live and
## closed windows, café coins earned online and (capped) offline, station
## levels and prices, stars and the reward track, reset between events, the
## café screen's buttons, and the stand on the museum plaza that opens it.

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

func run() -> void:
	if not OS.has_environment("GRAND_EXHIBIT_TEST_RUN"):
		printerr("REFUSED: requires GRAND_EXHIBIT_TEST_RUN isolation"); quit(2); return
	var gs: Node = root.get_node("GameState")
	var ss: Node = root.get_node("SaveSystem")
	ss.set_process(false)
	var path: String = ss.save_path()
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)
	gs.reset_to_new_game()
	gs.ready_flag = true
	var CS: GDScript = load("res://scripts/events/cafe_system.gd")

	# Data: every museum has a themed café.
	check(CS.stations().size() == 4 and CS.rewards().size() >= 8, "four stations and a reward track")
	var themes: Dictionary = CS.config().get("themes", {})
	var complete := true
	for vid in root.get_node("DataLoader").venue_order():
		var t: Dictionary = themes.get(vid, {})
		complete = complete and str(t.get("name", "")) != "" and (t.get("stations", {}) as Dictionary).size() == 4 \
			and (t.get("palette", {}) as Dictionary).size() == 8
	check(complete, "all twelve museums have a café name, station names and palette")

	# Locked until reputation 3.
	check(not CS.is_live() and not gs.event_state.get("pop_up_cafe", {}).has("anchor"), "a new player has no café yet")
	_set_rep(gs, 3)
	check(CS.is_live(), "reputation 3 opens the first Pop-Up Café")
	var st: Dictionary = gs.event_state["pop_up_cafe"]
	check(str(st["theme"]) == gs.current_venue and str(CS.theme()["name"]) == "Dino Diner", "the café is themed after the museum (Dino Diner)")
	check(CS.level("bar") == 1 and CS.level("case") == 0 and CS.stars() == 1, "the coffee bar starts open, the rest closed")

	# Earning: online and capped offline.
	st["t"] = int(st["t"]) - 100
	CS.tick()
	check(absf(CS.coins() - 100.0) < 2.0, "the bar earns 1 coin a second (%.1f)" % CS.coins())
	st["coins"] = 0.0
	st["t"] = int(st["t"]) - 20 * 3600
	CS.tick()
	check(absf(CS.coins() - 8.0 * 3600.0) < 5.0, "offline earnings stop at the 8 hour cap")

	# Buying.
	st["coins"] = 5.0
	check(not CS.buy("bar"), "can't buy a level without the coins")
	st["coins"] = 1000.0
	var c: float = CS.cost("bar")
	check(CS.buy("bar") and CS.level("bar") == 2 and absf(CS.coins() - (1000.0 - c)) < 0.01, "a level costs its price (%.1f)" % c)
	check(is_equal_approx(CS.cost("case"), 300.0) and CS.buy("case") and CS.level("case") == 1, "opening the pastry case costs 300")
	check(is_equal_approx(CS.income("bar", 25), 1.0 * 25.0 * 1.5), "every 25 levels multiplies income by 1.5")
	check(CS.stars() == 3, "stars count every level bought")

	# Rewards.
	check(not CS.claimable(0), "the first reward needs 10 stars")
	(st["levels"] as Dictionary)["bar"] = 9
	var gems_before: int = gs.gems
	check(CS.claimable(0), "10 stars unlock the first reward")
	var got: Dictionary = CS.claim(0)
	check(int(got.get("gems", 0)) == 5 and gs.gems == gems_before + 5, "the first reward pays 5 gems")
	check(CS.claim(0).is_empty() and CS.is_claimed(0), "a reward is claimed once")
	(st["levels"] as Dictionary)["bar"] = 30
	var cards: Dictionary = CS.claim(1)
	var n := 0
	for v in (cards.get("cards", {}) as Dictionary).values():
		n += int(v)
	check(n > 0, "the Field Case reward draws manager cards (%d)" % n)

	# The cycle: closed after 72 h, a fresh café after the cooldown.
	var anchor := int(st["anchor"])
	st["anchor"] = anchor - 73 * 3600
	var w: Dictionary = CS.tick()
	check(not bool(w["live"]) and not CS.is_live(), "the café closes after 72 hours")
	check(not CS.buy("bar"), "nothing can be bought while it is closed")
	st["anchor"] = anchor - 121 * 3600
	gs.current_venue = "copper_kettle"
	CS.tick()
	check(CS.is_live() and CS.level("bar") == 1 and CS.level("case") == 0 and CS.coins() == 0.0, "the next event opens a fresh café")
	check(not CS.is_claimed(0) and str(CS.theme()["name"]) == "Harbour Chowder Hut", "with a new track and the current museum's theme")
	gs.current_venue = "whispering_pines"

	# Save and load.
	st = gs.event_state["pop_up_cafe"]
	st["coins"] = 1234.0
	var saved: Dictionary = gs.to_save_dict()
	gs.reset_to_new_game()
	gs.from_save_dict(JSON.parse_string(JSON.stringify(saved)))
	check(absf(CS.coins() - 1234.0) < 50.0 and CS.level("bar") == 1, "the café survives save and load")

	# The café screen.
	gs.reset_to_new_game()
	var vp := SubViewport.new()
	vp.size = Vector2i(720, 1280)
	root.add_child(vp)
	vp.add_child((load("res://scenes/main.tscn") as PackedScene).instantiate())
	await create_timer(2.5).timeout
	# Booting starts a new game; reach reputation 4 in it.
	_set_rep(gs, 4)
	check(CS.is_live(), "the café is live at reputation 4")
	var rail: Node = root.find_child("SideRail", true, false)
	rail.call("refresh")
	var tile: Control = rail.find_child("ItemCafé", true, false)
	check(tile != null and tile.visible, "a Café tile shows on the rail while it is live")
	var screen: Control = (load("res://scenes/events/cafe_screen.tscn") as PackedScene).instantiate()
	vp.add_child(screen)
	await process_frame
	gs.event_state["pop_up_cafe"]["coins"] = 50.0
	var buy: Button = screen.find_child("Buy_bar", true, false)
	buy.pressed.emit()
	await process_frame
	check(CS.level("bar") == 2, "the Upgrade button buys a coffee bar level")
	var world: Node = screen.get("world")
	check(world != null and world.find_child("*", false, false) != null, "the café diorama is built")
	await create_timer(3.0).timeout
	var npcs := 0
	for ch in world.get_children():
		if ch.get_script() == load("res://scenes/venue3d/toy_npc.gd"):
			npcs += 1
	check(npcs >= 1, "customers walk into the café (%d)" % npcs)
	screen.queue_free()
	await process_frame

	# The stand on the plaza opens the café.
	var floor: Node = root.find_child("VenueFloor", true, false)
	var w3: Node = floor.get("world")
	check(w3.get("cafe_spot") != Vector3.INF and w3.find_child("CafeStand", true, false) != null, "the museum has a café stand on its plaza")
	var cam: Camera3D = w3.get("camera")
	var at: Vector3 = w3.get("cafe_spot") + Vector3(0.0, 0.8, 0.0)
	var hit: Dictionary = w3.call("pick", cam.unproject_position(at))
	check(bool(hit.get("cafe", false)), "a tap on the stand hits the café")

	vp.queue_free()
	await create_timer(0.5).timeout
	gs.reset_to_new_game()
	print("RESULT: ", "OK" if failures == 0 else "FAILED (%d)" % failures)
	quit(1 if failures > 0 else 0)
