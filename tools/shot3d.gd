extends SceneTree
## Screenshot the 3D venue scene after it has settled.
##
##   godot --path . -s tools/shot3d.gd -- out=C:/abs/shot.png [venue=whispering_pines]
##         [secs=12] [zoom=1.0] [pan=x,z]
##
## zoom < 1 moves the camera closer (0.5 = twice as close); pan offsets the
## camera focus on the ground plane. Needs a real window (not --headless):
## the 3D renderer and the tilt-shift pass both have to run.

func _initialize() -> void:
	var args := {}
	for a in OS.get_cmdline_user_args():
		var kv := a.split("=", true, 1)
		if kv.size() == 2:
			args[kv[0]] = kv[1]
	var scene: Node3D = load("res://scenes/venue3d/venue_3d.tscn").instantiate()
	scene.set("venue_id", str(args.get("venue", "whispering_pines")))
	root.add_child(scene)
	var secs := float(args.get("secs", "12"))
	await create_timer(0.5).timeout
	var cam = scene.get("camera")
	if cam:
		cam.dist *= float(args.get("zoom", "1.0"))
		if args.has("pan"):
			var p := str(args["pan"]).split(",")
			cam.focus += Vector3(float(p[0]), 0.0, float(p[1]))
		cam._apply()
	await create_timer(secs).timeout
	await process_frame
	var img := root.get_texture().get_image()
	var out := str(args.get("out", "user://shot3d.png"))
	img.save_png(out)
	print("SHOT ", out, " ", img.get_size())
	quit()
