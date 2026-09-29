extends SceneTree
## QA-only staged texture bank switching through the real Character renderer.
## Choreographed actions, not pathfinding or full venue navigation evidence.
const Character := preload("res://scenes/venue/floor/character.gd")
const Motion := preload("res://scripts/characters/motion_sprites.gd")
var vp: SubViewport
var output: String
var source: String
var records: Array = []
var packed: Dictionary = {}

func _initialize() -> void:
	call_deferred("run")

func read_texture(path: String) -> Texture2D:
	if not packed.is_empty():
		assert(packed.has(path.get_file()), "Missing packed frame: " + path)
		var entry: Dictionary = packed[path.get_file()]
		var texture := Motion._texture(entry.record,entry.folder)
		assert(texture != null, "Packed texture failed: " + path)
		return texture
	var im := Image.load_from_file(path)
	assert(im != null and not im.is_empty(), "Missing staged image: " + path)
	im.generate_mipmaps()
	return ImageTexture.create_from_image(im)

func collect_packed(value: Variant, folder: String) -> void:
	if value is Dictionary:
		if value.has("file"):
			packed[str(value.file)] = {"record":value,"folder":folder}
		else:
			for child in value.values():collect_packed(child,folder)
	elif value is Array:
		for child in value:collect_packed(child,folder)

func caption(text: String, at: Vector2) -> void:
	var label := Label.new()
	label.text = text
	label.position = at
	label.add_theme_font_size_override("font_size", 15)
	vp.add_child(label)

func capture(name: String) -> void:
	for i in 2:
		await process_frame
	await RenderingServer.frame_post_draw
	assert(vp.get_texture().get_image().save_png(output.path_join(name)) == OK)

func run() -> void:
	if not OS.has_environment("GRAND_EXHIBIT_TEST_RUN") or OS.get_environment("XDG_DATA_HOME").is_empty():
		printerr("Face activity review requires an isolated test profile")
		quit(2)
		return
	var args := OS.get_cmdline_user_args()
	assert(args.size() in [2,3])
	output = args[0]
	source = args[1]
	if args.size() == 3:
		for bank in [["npc_motion","motion.json"],["npc_seating","seating.json"],["npc_activities","activities.json"]]:
			var folder := args[2].path_join(bank[0])+"/"
			var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(folder+bank[1]))
			collect_packed(manifest.sets,folder)
	DirAccess.make_dir_recursive_absolute(output)
	for node in root.get_children():
		node.process_mode = Node.PROCESS_MODE_DISABLED
	vp = SubViewport.new()
	vp.size = Vector2i(960, 650)
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(vp)
	var background := Polygon2D.new()
	background.polygon = PackedVector2Array([Vector2.ZERO, Vector2(960,0), Vector2(960,650), Vector2(0,650)])
	background.color = Color("283541")
	vp.add_child(background)
	caption("Staged faces | actual Character renderer | actions choreographed for review", Vector2(16,12))
	var actors: Array = []
	for slot in [9,19,15]:
		var card := Node2D.new()
		card.position = Vector2(165+actors.size()*315,470)
		card.scale = Vector2.ONE*4
		vp.add_child(card)
		var c := Character.new()
		c.set_look_slot(slot)
		card.add_child(c)
		c.set_process(false)
		var base := Motion.base_for(c.identity)
		var item: Dictionary = {"stride_grid": c._motion_set.stride_grid}
		for view in ["front","back"]:
			var frames: Array[Texture2D] = []
			for i in 8:
				frames.append(read_texture(source.path_join("motion/%s/%s-%s-%d.png" % [base,base,view,i])))
			item[view] = frames
			item["idle_"+view] = read_texture(source.path_join("motion/%s/%s-%s-idle.png" % [base,base,view]))
		c._motion_set = item
		c._frames = item.front
		var seat_frames: Array[Texture2D] = []
		for view in ["front","back"]:
			for i in 9:
				seat_frames.append(read_texture(source.path_join("seating/%s/%s-%s-sit-%d.png" % [base,base,view,i])))
		c._approved_seated = seat_frames[8] if packed.is_empty() else read_texture(base+"-sit.png")
		var feed_frames: Array[Texture2D] = []
		for i in 24:
			feed_frames.append(read_texture(source.path_join("activities/%s/%s-feed-%d.png" % [base,base,i])))
		c.scale = Vector2.ONE*c.age_scale()
		caption(base.replace("visitor_",""), Vector2(25+actors.size()*315,560))
		actors.append({"node":c,"seating":seat_frames,"feeding":feed_frames,"base":base})
	for view in ["front","back"]:
		for action in ["idle","walk","sit","rise","feed","fallback_sit","idle_return"]:
			if action in ["feed","fallback_sit"] and view == "back":continue
			for item in actors:
				var c: Node = item.node
				c.end_seating()
				c.set_bird_feeding(false)
				c.walking = action == "walk"
				c._view_back = view == "back"
				c._frames = c._motion_set[view]
				c._frame = -1
				if action in ["sit","rise"]:
					c._seating_frames = item.seating
					assert(c.begin_seating(Vector2.DOWN,Vector2.ZERO))
					c._view_back = view == "back"
					c._seating_progress = 0.0 if action == "sit" else 1.0
				if action == "feed":c._feeding_frames = item.feeding
				if action == "fallback_sit":c.seated = true
			for frame in 9:
				for item in actors:
					var c: Node = item.node
					if action == "walk":c._frame = frame%8
					elif action in ["sit","rise"]:c.advance_seating(0 if frame==0 else .1,action=="sit")
					elif action == "feed":c.set_bird_feeding(true,float(frame)*.333)
					c.queue_redraw()
				await capture("%s-%s-%02d.png" % [view,action,frame])
			records.append({"view":view,"action":action,"frames":9,"identities":actors.map(func(item):return item.base)})
	var file := FileAccess.open(output.path_join("review.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify({"cases":records,"packed_textures":not packed.is_empty(),"scope":"Three staged identities, original Character draw/action functions, choreographed frame advancement. No pathfinding, actual bench contact, free-living venue behavior or target-device performance claim."},"\t"))
	file.close()
	print("FACE_CAST_ACTIVITY_REVIEW_COMPLETE ",records.size())
	quit(0)
