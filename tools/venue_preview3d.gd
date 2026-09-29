extends SceneTree
## Render each museum's "developed" 3D preview (every wing open, hero exhibits
## at the top tier, visitors walking) into art/venue_previews/<id>.png, the art
## the Next Museum / collection screens show. Needs a display (not headless).
##
##   godot --path . -s tools/venue_preview3d.gd -- [venue_id ...]
const SIZE := Vector2i(960, 720)

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var gs: Node = root.get_node("GameState")
	var dl: Node = root.get_node("DataLoader")
	root.get_node("SaveSystem").set_process(false)
	root.get_node("Economy").set_process(false)
	var ids: Array = OS.get_cmdline_user_args()
	if ids.is_empty():
		ids = dl.venue_order()
	var WS: GDScript = load("res://scripts/meta/wing_system.gd")
	var V: GDScript = load("res://scenes/venue3d/venue_3d.gd")
	for vid in ids:
		gs.reset_to_new_game()
		gs.ready_flag = true
		gs.current_venue = str(vid)
		var open: Array = []
		for w in WS.wings(str(vid)):
			open.append(str(w["id"]))
		gs.venue_state(str(vid))["wings"] = open
		var vp := SubViewport.new()
		vp.size = SIZE
		vp.own_world_3d = true
		vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		root.add_child(vp)
		var w: Node3D = V.new()
		w.venue_id = str(vid)
		w.visitor_target = 30
		vp.add_child(w)
		await process_frame
		w.set_exhibit_tier(4)
		var back := 0.0
		for f in w.floors:
			back = minf(back, (f["rect"] as Rect2).position.y)
		var cam: Camera3D = w.camera
		cam.bounds = Rect2(-50, -50, 200, 200)
		cam.max_dist = 400.0
		cam.height_at = Callable()
		# Fit the whole building (depth included) in a 4:3 frame.
		var depth: float = w.H - back + 4.0
		var width: float = w.W + 3.0
		cam.focus = Vector3(w.W * 0.5, 0.0, (back + w.H) * 0.5 + 1.5)
		cam.dist = maxf(width * 0.5 / tan(deg_to_rad(cam.fov * 0.5)), depth * 1.55)
		cam._apply()
		await create_timer(9.0).timeout
		await RenderingServer.frame_post_draw
		var img := vp.get_texture().get_image()
		var out := "res://art/venue_previews/%s.png" % vid
		img.save_png(ProjectSettings.globalize_path(out))
		print("PREVIEW ", vid, " -> ", out)
		vp.queue_free()
		await process_frame
	quit(0)
