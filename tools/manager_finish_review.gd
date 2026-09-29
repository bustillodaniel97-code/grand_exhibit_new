extends SceneTree
## Optional authoring-only foreground/background folders and comma-separated identities
## allow genuine in-game pilot review before replacing production PNGs.
var output := ""
var failures := 0
func _initialize() -> void: call_deferred("run")
func check(ok: bool, message: String) -> void:
	if not ok: failures += 1
	print("PASS " if ok else "FAIL ", message)
func find_screen(node: Node, path: String) -> Node:
	if node.get_script() != null and node.get_script().resource_path == path: return node
	for child in node.get_children():
		var result := find_screen(child, path)
		if result != null: return result
	return null
func capture(label: String) -> void:
	await create_timer(.2).timeout
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(output + "/" + label + ".png")
func run() -> void:
	if not OS.has_environment("GRAND_EXHIBIT_TEST_RUN"): quit(2); return
	output = OS.get_cmdline_user_args()[0]; DirAccess.make_dir_recursive_absolute(output)
	root.size = Vector2i(720,1280); root.content_scale_size = Vector2i(720,1280)
	root.get_node("SaveSystem").set_process(false); root.get_node("Economy").set_process(false)
	var gs := root.get_node("GameState"); gs.reset_to_new_game()
	var ms = load("res://scripts/managers/manager_system.gd")
	var bn = load("res://scripts/core/big_number.gd")
	gs.insight = bn.from_float(1000)
	var dl := root.get_node("DataLoader")
	var args := OS.get_cmdline_user_args()
	var portraits = load("res://scenes/managers/manager_portrait.gd")
	if args.size() > 1:
		for id in dl.managers:
			var path: String = args[1].path_join(str(id)+".png")
			if FileAccess.file_exists(path):
				var image := Image.load_from_file(path)
				image.generate_mipmaps()
				portraits._textures[id] = ImageTexture.create_from_image(image)
	if args.size() > 2:
		for dept in portraits.DEPARTMENTS:
			var path: String = args[2].path_join(str(dept)+".png")
			if FileAccess.file_exists(path):
				var image := Image.load_from_file(path)
				image.generate_mipmaps()
				portraits._backgrounds[dept] = ImageTexture.create_from_image(image)
	var review_ids: Array = Array(args[3].split(",")) if args.size() > 3 else dl.managers.keys()
	for id in dl.managers: ms.add_cards(id,1)
	var pop = load("res://scripts/ui/popup_manager.gd")
	var layer = load("res://scenes/ui/popup_layer.tscn").instantiate(); root.add_child(layer)
	pop.open("res://scenes/managers/managers_screen.tscn")
	await create_timer(.3).timeout
	var screen = find_screen(layer,"res://scenes/managers/managers_screen.gd")
	for canvas in [Vector2i(720,1280),Vector2i(720,1000)]:
		root.size = canvas; root.content_scale_size = canvas
		await create_timer(.2).timeout
		for id in review_ids:
			screen.select_manager(id,true)
			await capture(str(canvas.y)+"-"+id)
			for button in screen._actions.find_children("*", "Button", true, false):
				check(button.get_global_rect().size.y >= 48, "%s/%d touch height %.1f" % [button.text,canvas.y,button.get_global_rect().size.y])
			check(screen._actions.get_global_rect().end.y <= screen.get_global_rect().end.y + 1, "%s/%d actions fit" % [id,canvas.y])
			for slot in screen._slots:
				if slot.index != roundi(screen._pos): continue
				check(slot.card.size.y <= screen._card_size.y + 1, "%s/%d card content fits" % [id,canvas.y])
				for label in slot.card.find_children("*", "Label", true, false):
					if label.is_visible_in_tree():
						check(label.size.y + 1 >= label.get_minimum_size().y, "%s/%d label height fits: %s" % [id,canvas.y,label.text])
	pop.close_top(); await create_timer(.2).timeout; layer.free(); await process_frame
	print("MANAGER_FINISH_REVIEW_DONE failures=",failures)
	quit(0 if failures == 0 else 1)
