extends SceneTree
## The 3D toy-diorama floor stands in for the 2D VenueFloor inside VenueView:
## same node name and signals, station chips per owned counter, taps resolve
## to departments (merged rooms included), and venues without 3D art keep the
## 2D floor.

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
	var dl: Node = root.get_node("DataLoader")
	var gs: Node = root.get_node("GameState")
	var ec: Node = root.get_node("Economy")
	root.get_node("SaveSystem").set_process(false)
	ec.set_process(false)
	dl.reload_all()
	gs.reset_to_new_game()
	gs.ready_flag = true
	gs.set_dept_level(gs.current_venue, "ticket", "staff", 3)
	var Floor3D: GDScript = load("res://scenes/venue3d/venue_floor_3d.gd")
	var VenueView: GDScript = load("res://scenes/venue/venue_view.gd")

	check(Floor3D.supports("whispering_pines"), "museum 1 has generated 3D art")
	VenueView.use_3d = true
	check(VenueView.wants_3d(gs.current_venue), "the opening venue picks the 3D floor")

	var view: Control = (load("res://scenes/venue/venue_view.tscn") as PackedScene).instantiate()
	view.set_size(Vector2(720, 980))
	root.add_child(view)
	await process_frame
	await process_frame
	var floor: Node = view.find_child("VenueFloor", true, false)
	check(floor.get_script() == Floor3D, "VenueView mounts the 3D floor under the VenueFloor name")
	check(floor.has_signal("dept_selected") and floor.has_signal("item_selected"),
		"3D floor exposes the 2D floor's signals (quests bar routes through them)")

	floor.set_rates(ec.venue_rates(gs.current_venue))
	var owned: int = gs.dept_items(gs.current_venue, "ticket").size()
	check(floor._chips.size() == mini(owned, floor.world.window_count()),
		"one cash chip per owned ticket counter")
	check(floor.world.open_windows() == owned, "unowned counters stand closed")
	check((floor._chips[0] as Button).custom_minimum_size.y >= 42, "station chip is mobile-sized")

	# Department lookup by floor point, including a room merged into another.
	var w: Node3D = floor.world
	check(w.dept_at(w.dept_center("gallery")) == "gallery", "gallery room resolves to gallery")
	check(w.dept_at(Vector3(5.0, 0.0, 12.0)) == "ticket", "reception court counts as the ticket hall")
	check(w.dept_at(Vector3(4.0, 0.0, 16.5)) == "", "the lobby is not a department")

	# Real pending cash behind station zero collects through the chip handler.
	var items: Array = gs.dept_items(gs.current_venue, "ticket")
	items[0]["pending"] = BigNumber.from_float(25.0).to_save()
	gs.pending_cash[gs.current_venue] = BigNumber.from_float(25.0)
	floor._refresh_stations()
	check("$25" in (floor._chips[0] as Button).text, "chip shows station zero's pending cash")
	var cash_before: BigNumber = gs.cash
	floor._on_station_cash(0)
	check(gs.cash.gt(cash_before), "tapping the chip banks the station")

	# Upgrade arrow opens the ticket sheet on that station.
	(floor._ups[1] as Button).pressed.emit()
	await process_frame
	check(view._open_dept == "ticket", "station upgrade opens the ticket sheet")
	var panel: Node = view._panels.get("ticket")
	check(panel != null and panel.selected_item == 1, "sheet targets station 2")

	# A department signal from the floor opens that department's sheet.
	floor.dept_selected.emit("gallery")
	await process_frame
	check(view._open_dept == "gallery", "dept_selected opens the gallery sheet")

	# Venues without 3D art keep the 2D floor.
	var other := ""
	for vid in dl.venues.keys():
		if not Floor3D.supports(str(vid)):
			other = vid
			break
	check(other != "" and not VenueView.wants_3d(other), "venues without art fall back to 2D")
	VenueView.use_3d = false
	check(not VenueView.wants_3d(gs.current_venue), "use_3d off forces the 2D floor")
	VenueView.use_3d = true

	# Moving to a venue without art swaps the floor kind in place.
	var home: String = gs.current_venue
	gs.current_venue = other
	view._on_venue_changed(home, other)
	await process_frame
	await process_frame
	var swapped: Node = view.find_child("VenueFloor", true, false)
	check(swapped != null and swapped.get_script() != Floor3D and swapped.has_method("set_rates"),
		"graduating to a 2D-only venue mounts the 2D floor")
	gs.current_venue = home
	view._on_venue_changed(other, home)
	await process_frame
	check(view.find_child("VenueFloor", true, false).get_script() == Floor3D,
		"returning to a 3D venue mounts the 3D floor again")

	view.queue_free()
	await process_frame
	print("RESULT: ", "OK" if failures == 0 else "FAILED (%d)" % failures)
	quit(1 if failures > 0 else 0)
