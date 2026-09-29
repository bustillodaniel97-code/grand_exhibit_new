extends SceneTree
## Real popup flow: roster state changes, contextual entry and recruitment taps.
var failures := 0
var output := ""
func _initialize() -> void: call_deferred("run")
func check(ok: bool, message: String) -> void:
	if not ok: failures += 1
	print("PASS " if ok else "FAIL ", message)
func settle() -> void:
	await create_timer(.25).timeout
func tap(button: Button) -> void:
	var point := button.get_global_rect().get_center()
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT;event.position = point;event.pressed = true
	root.push_input(event, true)
	var release := event.duplicate();release.pressed = false;root.push_input(release, true)
	await settle()
func find_screen(node: Node, path: String) -> Node:
	if node.get_script() != null and node.get_script().resource_path == path: return node
	for child in node.get_children():
		var result := find_screen(child, path)
		if result != null: return result
	return null
func capture(label: String) -> void:
	if output.is_empty() or DisplayServer.get_name() == "headless": return
	await create_timer(1).timeout
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(output + "/" + label + ".png")
func run() -> void:
	if not OS.has_environment("GRAND_EXHIBIT_TEST_RUN"): quit(2);return
	var args := OS.get_cmdline_user_args()
	if not args.is_empty(): output = args[0];DirAccess.make_dir_recursive_absolute(output)
	root.size = Vector2i(720,1280)
	root.get_node("SaveSystem").set_process(false)
	root.get_node("Economy").set_process(false)
	var gs := root.get_node("GameState");gs.reset_to_new_game()
	var ms = load("res://scripts/managers/manager_system.gd")
	var bn = load("res://scripts/core/big_number.gd")
	ms.add_cards("docent_poppy",1);ms.add_cards("night_curator",1)
	var pop = load("res://scripts/ui/popup_manager.gd")
	var layer = load("res://scenes/ui/popup_layer.tscn").instantiate();root.add_child(layer)
	pop.open("res://scenes/managers/managers_screen.tscn")
	await settle()
	var screen = find_screen(layer,"res://scenes/managers/managers_screen.gd")
	check(screen._ids.size() == root.get_node("DataLoader").managers.size(), "All includes the complete roster")
	await tap(screen._filter_buttons["available"])
	check(screen._ids.size() == 2, "Available shows only recruited staff without a post")
	screen.select_manager("night_curator",true)
	gs.insight = bn.from_float(1000);root.get_node("EventBus").insight_changed.emit(gs.insight)
	check(screen.selected_id() == "night_curator", "Currency refresh retains the selected manager")
	await capture("available")
	if DisplayServer.get_name() != "headless":
		var portrait_ready := false
		for slot in screen._slots:
			if slot.index != roundi(screen._pos): continue
			var portrait = find_screen(slot.card,"res://scenes/managers/manager_portrait.gd")
			for child in portrait._slot.get_children():
				if child is TextureRect: portrait_ready = true
		check(portrait_ready, "The selected authored portrait remains visible after filtering")

	ms.assign("night_curator", "gallery")
	check(screen._ids.size() == 1 and screen.selected_id() == "docent_poppy", "Posting removes staff from Available and leaves a valid selection")
	await tap(screen._filter_buttons["duty"])
	check(screen._ids == ["night_curator"], "On duty shows the assigned manager")
	var visible := 0
	for slot in screen._slots:
		if slot.holder.visible: visible += 1
	check(visible == 1, "A one-person filter renders one pass, without duplicate neighbours")
	ms.unassign("night_curator")
	check(screen.selected_id().is_empty() and screen._empty_label.visible, "Standing down the last manager produces an explanatory empty roster")
	await capture("empty-duty")
	await tap(screen._filter_buttons["ready"])
	check(screen._ids.size() == 2, "Ready finds affordable upgrades")
	gs.insight = bn.zero();root.get_node("EventBus").insight_changed.emit(gs.insight)
	check(screen._ids.is_empty(), "Ready refreshes when Insight no longer covers upgrades")
	ms.add_cards("docent_poppy",ms.rank_up_cost("docent_poppy"))
	check(screen._ids == ["docent_poppy"], "Ready also finds rank upgrades with enough duplicates")
	await tap(screen._filter_buttons["sealed"])
	screen.select_manager("barker_theo",true)
	for slot in screen._slots:
		if not slot.holder.visible: continue
		check(slot.card._id == screen._ids[screen._wrap(slot.index)], "Filtered carousel also refreshes wrapped negative slots")
		var sealed_portrait = find_screen(slot.card,"res://scenes/managers/manager_portrait.gd")
		check(sealed_portrait._slot.get_child_count() == 2 and sealed_portrait._slot.get_child(0) is Label, "Every visible Sealed card hides the face")
	await capture("sealed")
	var cash_before = gs.cash.to_save();var gems_before: int = gs.gems
	await tap(screen.find_child("OpenRecruitmentCases",true,false))
	var cases = find_screen(layer,"res://scenes/managers/lootbox_screen.gd")
	check(cases != null and pop._instance._stack.size() == 2, "A real sealed-pass tap opens recruitment over the roster")
	check(gs.gems == gems_before and gs.cash.to_save() == cash_before, "Browsing recruitment spends no currency")
	await capture("cases")
	pop.close_top();await settle()
	check(screen.selected_id() == "barker_theo", "Closing recruitment returns to the same sealed manager")
	pop.close_top();await settle()
	pop.open("res://scenes/managers/managers_screen.tscn", {"specialty":"gallery","select":"night_curator"})
	await settle()
	screen = find_screen(layer,"res://scenes/managers/managers_screen.gd")
	check(screen.selected_id() == "night_curator", "Contextual popup entry selects the requested manager after ready")
	var specialty_only := true
	for id in screen._ids:
		if ms.manager_def(id).specialty != "gallery": specialty_only = false
	check(specialty_only, "Contextual roster and filter counts retain the department restriction")
	await capture("contextual")
	root.size = Vector2i(720,1000)
	root.content_scale_size = Vector2i(720,1000)
	pop.close_top();await settle()
	pop.open("res://scenes/managers/managers_screen.tscn", {"select":"night_curator"})
	await settle()
	screen = find_screen(layer,"res://scenes/managers/managers_screen.gd")
	check(screen._actions.get_global_rect().end.y <= screen.get_global_rect().end.y + 1, "All manager actions fit within the shorter popup body (actions=%s body=%s stage=%s)" % [screen._actions.get_global_rect(),screen.get_global_rect(),screen._stage.size])
	check(screen._compact_cards, "A short viewport uses the readable compact manager card")
	for button in screen._actions.find_children("*", "Button", true, false):
		check(button.get_global_rect().size.y >= 48, "Manager action retains a 48px touch target: " + button.text)
	await capture("short-manager")
	await tap(screen.find_child("RecruitManagers",true,false))
	check(pop._instance._stack.size() == 2, "Persistent Recruit button works from an owned pass")
	await capture("short-cases")
	pop.close_top();await settle()
	pop.close_top();await settle();layer.free();await process_frame
	print("MANAGER_ROSTER_DONE failures=",failures)
	quit(0 if failures == 0 else 1)
