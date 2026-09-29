extends SceneTree
var failures := 0
func _initialize() -> void: call_deferred("run")
func check(ok: bool, label: String) -> void:
	if not ok: failures += 1
	print("PASS " if ok else "FAIL ",label)
func settle() -> void: await create_timer(.25).timeout
func tap(button: Button) -> void:
	var event := InputEventMouseButton.new();event.button_index = MOUSE_BUTTON_LEFT
	event.position = button.get_global_rect().get_center();event.pressed = true
	root.push_input(event,true)
	var release := event.duplicate();release.pressed = false;root.push_input(release,true)
	await settle()
func find_store(node: Node) -> Node:
	if node.get_script() != null and node.get_script().resource_path == "res://scenes/store/store_screen.gd": return node
	for child in node.get_children():
		var found := find_store(child)
		if found != null: return found
	return null
func texts(node: Node) -> String:
	var result: String = node.text + "\n" if node is Label or node is Button else ""
	for child in node.get_children(): result += texts(child)
	return result
func run() -> void:
	if not OS.has_environment("GRAND_EXHIBIT_TEST_RUN"): quit(2);return
	root.size = Vector2i(720,1280)
	var gs := root.get_node("GameState");gs.reset_to_new_game()
	root.get_node("SaveSystem").set_process(false);root.get_node("Economy").set_process(false)
	var layer = load("res://scenes/ui/popup_layer.tscn").instantiate();root.add_child(layer)
	var popup = load("res://scripts/ui/popup_manager.gd")
	popup.open("res://scenes/store/store_screen.tscn",{"source":"navigation_test"})
	await settle()
	var store = find_store(layer)
	var cash = gs.cash.to_save();var gems: int = gs.gems;var insight = gs.insight.to_save()
	check(store._category == "offers", "Store opens on offers")
	check(not store._impressions.has("gems_pouch"), "Hidden gem shelf does not report a product view")
	var header_rect: Rect2 = store._wallet_chips.gems.get_global_rect()
	store._scroll.scroll_vertical = 180;await settle()
	var offers_scroll: int = store._scroll.scroll_vertical
	check(offers_scroll > 0, "Offer shelf scrolls independently")
	check(store._wallet_chips.gems.get_global_rect() == header_rect, "Balances remain fixed while products scroll")
	for key in ["rewards","gems","resources","passes"]:
		await tap(store._category_buttons[key])
		check(store._category == key and store._category_panels[key].is_visible_in_tree(), "Pointer opens " + key)
		var visible := 0
		for panel in store._category_panels.values():
			if panel.is_visible_in_tree(): visible += 1
		check(visible == 1, "Only the selected shelf is visible: " + key)
		check(store._category_panels[key].size.x <= store._scroll.size.x + 1, "Shelf fits horizontally: " + key)
	check(store._impressions.has("gems_pouch"), "Showing gems records its product view")
	check(texts(store._category_panels.passes).contains("Restore purchases") and texts(store._category_panels.passes).contains("Privacy choices"), "Passes exposes restore and privacy controls")
	await tap(store._category_buttons.offers)
	check(store._scroll.scroll_vertical == offers_scroll, "Returning to Offers restores its own scroll position (%s/%s)" % [store._scroll.scroll_vertical, offers_scroll])
	store._rebuild();await settle()
	check(store._category == "offers" and store._scroll.scroll_vertical == offers_scroll, "A shelf refresh preserves category and position")
	gs.gems += 7;store._tick()
	check(texts(store._wallet_chips.gems).contains(str(gs.gems)), "Pinned gem balance updates")
	gs.gems -= 7
	check(gs.cash.to_save() == cash and gs.gems == gems and gs.insight.to_save() == insight, "Browsing and refreshing spend no currency")
	popup.close_top();await settle()
	root.size = Vector2i(720,1000);root.content_scale_size = Vector2i(720,1000)
	popup.open("res://scenes/store/store_screen.tscn",{"category":"rewards"});await settle()
	store = find_store(layer)
	check(store._category == "rewards", "Context entry opens the requested category")
	check(not store._impressions.has("starter_bundle"), "Context entry does not track unseen offer products")
	for key in ["offers","gems","resources","passes","rewards"]:
		await tap(store._category_buttons[key])
		check(store._category == key and store._category_buttons[key].size.y >= 48, "Short viewport retains working 48-pixel tab: " + key)
	popup.close_top();await settle();layer.free();await process_frame
	print("STORE_NAVIGATION_DONE failures=",failures)
	quit(0 if failures == 0 else 1)
