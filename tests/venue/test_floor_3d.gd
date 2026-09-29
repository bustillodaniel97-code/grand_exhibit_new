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

	# Upper floors: derelict until renovated, tappable, then revealed and reachable.
	check(w.floors.size() == 2, "museum 1 shows two upper floors")
	var f2: Dictionary = w.floors[0]
	check(not bool(f2["open"]) and not (f2["tints"] as Array).is_empty(), "the 2F starts derelict (greyed)")
	check((f2["derelict"] as Array).size() >= 4, "derelict dressing stands on the 2F")
	check(not (f2["pieces"][0] as Node3D).visible, "2F exhibits wait under dust sheets")
	var cam: Camera3D = w.camera
	var r2: Rect2 = f2["rect"]
	var mid := Vector3(r2.get_center().x, float(f2["y"]), r2.get_center().y)
	var hit: Dictionary = w.pick(cam.unproject_position(mid))
	check(str(hit.get("wing", "")) == "hall_of_giants" and not bool(hit.get("open", true)), "a tap on the 2F finds the derelict wing")
	check(w.pick(cam.unproject_position(w.dept_center("gallery"))).get("dept", "") == "gallery", "ground taps still find departments")
	var WS: GDScript = load("res://scripts/meta/wing_system.gd")
	var ms_ids: Array = []
	for m in dl.milestones.get(gs.current_venue, []):
		ms_ids.append(str(m["id"]))
	gs.venue_state(gs.current_venue)["milestones"] = ms_ids
	gs.cash = BigNumber.from_parts(1.0, 40)
	check(WS.renovate(gs.current_venue, "hall_of_giants"), "2F renovates")
	var t2 := Time.get_ticks_msec()
	while not (f2["tints"] as Array).is_empty() and Time.get_ticks_msec() - t2 < 15000:
		await process_frame
	await create_timer(0.5).timeout
	check(bool(f2["open"]) and (f2["derelict"] as Array).is_empty(), "renovation clears the derelict dressing")
	check((f2["pieces"][0] as Node3D).visible, "2F exhibits are revealed")
	check((f2["tints"] as Array).is_empty(), "colour floods back (grey overrides removed)")
	hit = w.pick(cam.unproject_position(mid))
	check(str(hit.get("dept", "")) == "gallery" and bool(hit.get("open", false)), "an open 2F taps through to its department")
	var shell: Node = w.get("_shell")
	check((shell.find_child("grand_2", true, false) as Node3D).visible, "grandeur II dressing appears outside")
	check(not (shell.find_child("grand_3", true, false) as Node3D).visible, "grandeur III waits for the next wing")
	# A visitor rides the glass lift to the 2F.
	var Npc: GDScript = load("res://scenes/venue3d/toy_npc.gd")
	var rider: Node3D = w._spawn(w._look(), f2["enter"])
	w._travel(rider, 0, 1)
	var t0 := Time.get_ticks_msec()
	while int(rider.get_meta("floor", 0)) != 1 and Time.get_ticks_msec() - t0 < 90000:
		await process_frame
	check(int(rider.get_meta("floor", 0)) == 1 and absf(rider.global_position.y - float(f2["y"])) < 0.2,
		"a visitor rides the lift up to the 2F (y=%.2f)" % rider.global_position.y)
	floor.go_to_floor(1)
	var t1 := Time.get_ticks_msec()
	while absf(cam.focus.y - float(f2["y"])) >= 0.3 and Time.get_ticks_msec() - t1 < 15000:
		await process_frame
	check(absf(cam.focus.y - float(f2["y"])) < 0.3, "the floor selector lifts the camera to the 2F")

	# Venues without 3D art keep the 2D floor. Once every museum has art, the
	# kill switch stands in for a 2D-only museum.
	var other := ""
	for vid in dl.venues.keys():
		if not Floor3D.supports(str(vid)):
			other = vid
			break
	var forced := other == ""
	if forced:
		other = "copper_kettle"
		VenueView.use_3d = false
	check(not VenueView.wants_3d(other), "a venue without art (or with 3D switched off) falls back to 2D")
	VenueView.use_3d = false
	check(not VenueView.wants_3d(gs.current_venue), "use_3d off forces the 2D floor")
	VenueView.use_3d = not forced

	# Moving to a venue without art swaps the floor kind in place.
	var home: String = gs.current_venue
	gs.current_venue = other
	view._on_venue_changed(home, other)
	await process_frame
	await process_frame
	var swapped: Node = view.find_child("VenueFloor", true, false)
	check(swapped != null and swapped.get_script() != Floor3D and swapped.has_method("set_rates"),
		"graduating to a 2D-only venue mounts the 2D floor")
	VenueView.use_3d = true
	gs.current_venue = home
	view._on_venue_changed(other, home)
	await process_frame
	check(view.find_child("VenueFloor", true, false).get_script() == Floor3D,
		"returning to a 3D venue mounts the 3D floor again")

	view.queue_free()
	# Let teardown finish (killed tweens and freed timers are released on the
	# following frames) so nothing is reported leaked at exit.
	for _i in 10:
		await process_frame
	print("RESULT: ", "OK" if failures == 0 else "FAILED (%d)" % failures)
	quit(1 if failures > 0 else 0)
