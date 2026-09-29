extends SceneTree
## First-run tutorial: starts only for a new player, advances on the real game
## events (collect, upgrade, opening the Nature Hall, then timed tips), never
## takes input, and is remembered in the save.

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
	if not OS.has_environment("GRAND_EXHIBIT_TEST_RUN"):
		printerr("REFUSED: requires GRAND_EXHIBIT_TEST_RUN isolation"); quit(2); return
	var gs: Node = root.get_node("GameState")
	var ss: Node = root.get_node("SaveSystem")
	ss.set_process(false)
	var path: String = ss.save_path()
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)
	var vp := SubViewport.new()
	vp.size = Vector2i(720, 1280)
	root.add_child(vp)
	vp.add_child((load("res://scenes/main.tscn") as PackedScene).instantiate())
	await create_timer(2.5).timeout
	var tut: Control = root.find_child("Tutorial", true, false)
	check(tut != null and tut.active() and tut.current_id() == "collect", "a new player starts the walkthrough at 'collect'")
	check(tut.mouse_filter == Control.MOUSE_FILTER_IGNORE, "the overlay never takes a tap")
	var floor: Node = root.find_child("VenueFloor", true, false)
	var vid: String = gs.current_venue
	var items: Array = gs.dept_items(vid, "ticket")
	items[0]["pending"] = BigNumber.from_float(10.0).to_save()
	gs.pending_cash[vid] = BigNumber.from_float(10.0)
	floor._on_station_cash(0)
	await process_frame
	check(tut.current_id() == "upgrade", "collecting a desk's cash moves on to 'upgrade'")
	gs.add_cash(BigNumber.from_parts(1.0, 6))
	root.get_node("Economy").purchase_item_upgrade(vid, "ticket", 0)
	await process_frame
	check(tut.current_id() == "gallery", "upgrading a desk moves on to the Nature Hall")
	floor.dept_selected.emit("gallery")
	await create_timer(0.3).timeout
	check(tut.current_id() == "floors", "opening the Nature Hall moves on to the floors tip")
	await create_timer(15.0).timeout
	check(not tut.active() and not tut.visible, "the timed tips finish the walkthrough")
	check(int(gs.settings.get("tutorial_step", 0)) >= 5, "completion is saved in settings")
	vp.queue_free()
	await process_frame
	# A returning player with progress never sees it.
	gs.reset_to_new_game()
	gs.venues_unlocked.append("copper_kettle")
	var t2: Control = load("res://scenes/ui/tutorial.gd").new()
	root.add_child(t2)
	check(not t2.active(), "an existing player is not shown the walkthrough")
	t2.queue_free()
	for _i in 5:
		await process_frame
	print("RESULT: ", "OK" if failures == 0 else "FAILED (%d)" % failures)
	quit(1 if failures > 0 else 0)
