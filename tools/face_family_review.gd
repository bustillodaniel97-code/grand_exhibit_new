extends "res://tools/walking_campaign_review.gd"
## QA-only comparison of staged structural faces on real, moving visitors.
func read_frame(path: String) -> Texture2D:
	var im:=Image.load_from_file(path)
	if im==null or im.is_empty():printerr("Missing face study frame: ",path);quit(1);return null
	im.generate_mipmaps();return ImageTexture.create_from_image(im)
func run() -> void:
	if not OS.has_environment("GRAND_EXHIBIT_TEST_RUN") or OS.get_environment("XDG_DATA_HOME").is_empty():
		printerr("Face review requires an isolated test profile");quit(2);return
	var args:=OS.get_cmdline_user_args();output=args[0]
	DirAccess.make_dir_recursive_absolute(output)
	var studies: Array=JSON.parse_string(FileAccess.get_file_as_string(args[1]+"/all-studies.json"))
	root.get_node("SaveSystem").set_process(false)
	var gs: Node=root.get_node("GameState");gs.reset_to_new_game();seed(918)
	vp=SubViewport.new();vp.size=Vector2i(720,1280);vp.render_target_update_mode=SubViewport.UPDATE_ALWAYS
	root.add_child(vp);vp.add_child(load("res://scenes/main.tscn").instantiate())
	await create_timer(2).timeout
	for i in 4:load("res://scripts/ui/popup_manager.gd").close_top()
	for node in root.get_children():
		if node!=vp:node.process_mode=Node.PROCESS_MODE_DISABLED
	vp.get_child(0).process_mode=Node.PROCESS_MODE_DISABLED
	var f: Node=find_floor(vp)
	for dept in ["ticket","archive","gallery","promotions"]:
		for track in ["staff","speed","value"]:gs.set_dept_level(gs.current_venue,dept,track,8)
	f.set_rates(root.get_node("Economy").venue_rates(gs.current_venue))
	for tick in 900:f.advance_sim(.05)
	var records: Array=[]
	for study in studies:
		var case_name: String=study.family+"-"+study.gender
		if args.size()>2 and not case_name in args[2].split(","):continue
		var subject: Variant=null
		for attempt in 4:
			for v in f._visitors:
				if v.node.walking and v.state in ["to_queue","browse","to_exit"] and v.pos.distance_to(v.target)>1.5 and v.path.size()>4 and v.node.identity.age_group==study.age and v.node.identity.gender==study.gender:
					subject=v;break
			if subject!=null:break
			for tick in 200:f.advance_sim(.05)
		if subject==null:printerr("No suitable walking visitor: ",case_name);quit(1);return
		var character: Node=subject.node;var original_slot: int=character.look_slot()
		var slot: int=(0 if study.age=="child" else 2)+(1 if study.gender=="female" else 0)
		character.set_look_slot(slot)
		var control: Dictionary=character._motion_set;var staged: Dictionary=control.duplicate()
		for view in ["front","back"]:
			var frames: Array[Texture2D]=[]
			for frame in 8:frames.append(read_frame(args[1]+"/"+case_name+"/motion/%s-%d.png"%[view,frame]))
			staged[view]=frames;staged["idle_"+view]=read_frame(args[1]+"/"+case_name+"/motion/%s-idle.png"%view)
		var record: Dictionary={"case":case_name,"identity":character.identity.duplicate(),"position":str(subject.pos),"state":subject.state,"frames":[]}
		for mode in ["control","study"]:
			character._motion_set=control if mode=="control" else staged
			character._frames=character._motion_set.back if character._view_back else character._motion_set.front
			character.queue_redraw()
			f._camera_pan=Vector2.ZERO;f._user_zoom=3.0;f._fit_canvas()
			var point: Vector2=character.position*f._canvas.scale+f._canvas.position
			f._pan_camera(f.size*.5-point)
			await capture(output+"/"+case_name+"-"+mode+"-close.png")
		f._camera_pan=Vector2.ZERO;f._user_zoom=1.0;f._fit_canvas()
		await capture(output+"/"+case_name+"-study-overview.png")
		# A short real-motion proof for each family. No forced walking or position edits.
		f._user_zoom=3.0;f._fit_canvas()
		var point: Vector2=character.position*f._canvas.scale+f._canvas.position
		f._pan_camera(f.size*.5-point)
		for frame in 20:
			f.advance_sim(.05);update_characters(vp,.05)
			if not is_instance_valid(character) or subject.state in ["rest","rise"]:break
			record.frames.append({"frame":frame,"position":str(subject.pos),"state":subject.state,"walking":character.walking,"back_view":character._view_back,"pose":character._frame})
			await capture(output+"/"+case_name+"-motion-%03d.png"%frame)
		if is_instance_valid(character):character.set_look_slot(original_slot)
		records.append(record)
		var file:=FileAccess.open(output+"/review.json",FileAccess.WRITE)
		file.store_string(JSON.stringify({"venue":gs.current_venue,"cases":records,"scope":"Uninstalled structural studies on real visitors. Existing role, path, movement and rig; only test-node textures overridden. Seating/activity banks and live game save untouched. Not device FPS or full-cast approval."},"\t"));file.close()
		print("FACE_FAMILY_NATIVE_READY ",case_name," frames=",record.frames.size())
	quit(0)
