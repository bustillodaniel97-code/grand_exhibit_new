extends SceneTree
## Object-level floor loop: visible station -> collect or selected upgrade sheet.

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

	var view: Control = (load("res://scenes/venue/venue_view.tscn") as PackedScene).instantiate()
	view.set_size(Vector2(720, 980))
	root.add_child(view)
	await process_frame
	await process_frame
	var floor: Control = view.find_child("VenueFloor", true, false)
	floor._refresh_station_ui()
	check(floor._station_chips.size() == 3, "three staffed counters expose three cash chips")
	check(floor._station_upgrade.size() == 3, "three staffed counters expose three upgrade targets")
	check((floor._station_chips[0] as Button).custom_minimum_size.y >= 42,
		"station chip is a mobile-sized Control")

	# Put real venue pending behind station zero, then collect through the same
	# handler the floor button calls.
	var items: Array = gs.dept_items(gs.current_venue, "ticket")
	items[0]["pending"] = BigNumber.from_float(25.0).to_save()
	gs.pending_cash[gs.current_venue] = BigNumber.from_float(25.0)
	var cash_before: BigNumber = gs.cash
	floor._refresh_station_ui()
	check("$25" in (floor._station_chips[0] as Button).text,
		"cash chip publishes station zero's real pending amount")
	floor._on_station_cash(0)
	check(gs.cash.gt(cash_before), "tapping the cash chip banks that station only")
	check(ec.item_pending(gs.current_venue, "ticket", 0).is_zero(),
		"collected station chip clears exactly once")

	# Upgrade affordance selects a concrete item and opens the item row.
	floor._on_station_upgrade(1)
	await process_frame
	check(view._open_dept == "ticket", "station upgrade opens the ticket sheet")
	var panel: Node = view._panels.get("ticket")
	check(panel != null and panel.selected_item == 1, "sheet targets station 2, not the department generally")
	check(panel != null and panel._item_row.visible, "selected station upgrade row is visible")
	gs.add_cash(BigNumber.from_float(1e6))
	var level_before: int = gs.item_level(gs.current_venue, "ticket", 1)
	panel._on_buy_item()
	check(gs.item_level(gs.current_venue, "ticket", 1) == level_before + 1,
		"station row purchases an individual item level")

	# The same department sheet owns contextual staffing; the player should not
	# have to leave the room, open Statistics, and rediscover which specialty
	# belongs here.
	panel._show_tab(true)
	check(panel._manager_view.visible and not panel._upgrade_view.visible,
		"department sheet switches from upgrades to its Manager tab")
	check(panel._manager_view.get_child_count() >= 3,
		"Manager tab shows post status, an open post, and Staff Passes route")
	var MS: GDScript = load("res://scripts/managers/manager_system.gd")
	MS.add_cards("docent_poppy", 1)
	MS.assign("docent_poppy", "ticket")
	await process_frame
	check(MS.assigned_to("docent_poppy") == "ticket",
		"contextual ticket manager assignment is reflected in the shared system")

	print("---")
	if failures == 0:
		print("ALL STATION UI CHECKS PASSED")
	quit(0 if failures == 0 else 1)
