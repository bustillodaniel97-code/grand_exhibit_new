extends SceneTree
## Native visual review. Isolated profiles only; browsing never buys or rewards.
var failures := 0
func _initialize() -> void: call_deferred("run")
func check(ok: bool, label: String) -> void:
	if not ok: failures += 1
	print("PASS " if ok else "FAIL ",label)
func find_store(node: Node) -> Node:
	if node.get_script() != null and node.get_script().resource_path == "res://scenes/store/store_screen.gd": return node
	for child in node.get_children():
		var found := find_store(child)
		if found != null: return found
	return null
func inspect_art(node: Node) -> int:
	var count := 0
	if node.has_meta("store_art_asset"):
		count = 1
		check(node is TextureRect and node.texture != null, "Loaded " + str(node.get_meta("store_art_asset")))
		if node is TextureRect and node.texture != null:
			check(node.texture.get_size() == Vector2(512,512) and node.texture.get_image().has_mipmaps(), "512px art has native mipmaps")
			check(node.mouse_filter == Control.MOUSE_FILTER_IGNORE, "Artwork does not intercept touches")
	for child in node.get_children(): count += inspect_art(child)
	return count
func capture(output: String, name: String) -> void:
	await create_timer(.3).timeout
	await RenderingServer.frame_post_draw
	check(root.get_texture().get_image().save_png(output+"/"+name+".png") == OK,"Native capture " + name)
func run() -> void:
	if not OS.has_environment("GRAND_EXHIBIT_TEST_RUN"): quit(2);return
	var args := OS.get_cmdline_user_args()
	var output := args[0];DirAccess.make_dir_recursive_absolute(output)
	var height := int(args[1]) if args.size()>1 else 1280
	root.size = Vector2i(720,height);root.content_scale_size = Vector2i(720,height)
	root.get_node("SaveSystem").set_process(false);root.get_node("Economy").set_process(false)
	var gs := root.get_node("GameState");gs.reset_to_new_game()
	var cash = gs.cash.to_save();var gems = gs.gems;var insight = gs.insight.to_save()
	var layer = load("res://scenes/ui/popup_layer.tscn").instantiate();root.add_child(layer)
	load("res://scripts/ui/popup_manager.gd").open("res://scenes/store/store_screen.tscn",{"source":"art_review"})
	await create_timer(.4).timeout
	var store = find_store(layer)
	check(inspect_art(store)>20,"Complete store uses product imagery throughout")
	for key in store.CATEGORIES:
		store.set_category(key)
		store._scroll.scroll_vertical = 0
		await capture(output,key)
		check(store._category_panels[key].size.x <= store._scroll.size.x+1,"Shelf fits width: " + key)
		store._scroll.scroll_vertical = int(store._scroll.get_v_scroll_bar().max_value)
		await capture(output,key+"-bottom")
	for buttons in store._product_buttons.values():
		for button in buttons:
			check(button.size.y >= 56,"Purchase touch area remains at least 56px")
	check(cash == gs.cash.to_save() and gems == gs.gems and insight == gs.insight.to_save(),"Review changes no currency")
	print("STORE_ART_REVIEW_DONE failures=",failures)
	quit(0 if failures == 0 else 1)
