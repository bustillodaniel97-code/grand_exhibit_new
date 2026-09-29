extends SceneTree
## Desktop window check: boot the real game in a real window (the display
## settings a PC build uses) and capture it. Dev tool only.
##   godot --path . --resolution 1280x800 -s tools/desktop_shot.gd -- /abs/out.png
func _initialize() -> void:
	root.add_child((load("res://scenes/main.tscn") as PackedScene).instantiate())
	await create_timer(4.0).timeout
	await RenderingServer.frame_post_draw
	var out := OS.get_cmdline_user_args()[0] if not OS.get_cmdline_user_args().is_empty() else "user://desktop.png"
	root.get_texture().get_image().save_png(out)
	print("DESKTOP_SHOT ", out, " window=", DisplayServer.window_get_size())
	quit(0)
