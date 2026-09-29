extends SceneTree
func _initialize() -> void: call_deferred("run")
func find_screen(node: Node) -> Node:
	if node.get_script() != null and node.get_script().resource_path == "res://scenes/store/store_screen.gd": return node
	for child in node.get_children():
		var found := find_screen(child)
		if found != null: return found
	return null
func run() -> void:
	if not OS.has_environment("GRAND_EXHIBIT_TEST_RUN"): quit(2);return
	var output := OS.get_cmdline_user_args()[0];DirAccess.make_dir_recursive_absolute(output)
	var args := OS.get_cmdline_user_args()
	var height := int(args[1]) if args.size()>1 else 1280
	root.size = Vector2i(720,height)
	root.content_scale_size = Vector2i(720,height)
	root.get_node("SaveSystem").set_process(false);root.get_node("Economy").set_process(false)
	root.get_node("GameState").reset_to_new_game()
	var layer = load("res://scenes/ui/popup_layer.tscn").instantiate();root.add_child(layer)
	load("res://scripts/ui/popup_manager.gd").open("res://scenes/store/store_screen.tscn",{"source":"visual_review"})
	await create_timer(.5).timeout
	var store = find_screen(layer)
	var categories: Array = store.CATEGORIES.keys() if store.has_method("set_category") else ["before"]
	for key in categories:
		if store.has_method("set_category"): store.set_category(key)
		await create_timer(.4).timeout;await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(output+"/"+key+".png")
	quit(0)
