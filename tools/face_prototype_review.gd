extends "res://tools/walking_campaign_review.gd"
## QA-only texture override on one real visitor in an isolated native venue.
func read_frame(path: String) -> Texture2D:
	var im:=Image.load_from_file(path)
	if im==null or im.is_empty():push_error("Missing prototype frame: "+path);quit(1);return null
	im.generate_mipmaps();return ImageTexture.create_from_image(im)
func run() -> void:
	var args:=OS.get_cmdline_user_args();output=args[0]
	DirAccess.make_dir_recursive_absolute(output)
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
	var subject: Variant=null
	for v in f._visitors:
		if v.node.walking and v.path.size()>8 and v.node.identity.age_group=="young_adult":subject=v;break
	if subject==null:printerr("No walking young adult available for prototype review");quit(1);return
	var character: Node=subject.node;character.set_look_slot(3)
	var control: Dictionary=character._motion_set
	var prototype: Dictionary=control.duplicate()
	for view in ["front","back"]:
		var frames: Array[Texture2D]=[]
		for frame in 8:frames.append(read_frame(args[1]+"/%s-%d.png"%[view,frame]))
		prototype[view]=frames;prototype["idle_"+view]=read_frame(args[1]+"/%s-idle.png"%view)
	for mode in ["control","prototype"]:
		character._motion_set=control if mode=="control" else prototype
		character._frames=character._motion_set.back if character._view_back else character._motion_set.front
		character.queue_redraw()
		for zoom in [1.0,3.0]:
			f._user_zoom=zoom;f._fit_canvas()
			if zoom>1:
				var point: Vector2=character.position*f._canvas.scale+f._canvas.position
				f._pan_camera(f.size*.5-point)
			await capture(output+"/%s-%s.png"%[mode,"overview" if zoom==1 else "close"])
	var frames: Array=[]
	for frame in 40:
		f.advance_sim(.05);update_characters(vp,.05)
		if not is_instance_valid(character) or subject.state in ["rest","rise"]:break
		frames.append({"frame":frame,"position":str(subject.pos),"state":subject.state,"walking":character.walking,"back_view":character._view_back})
		await capture(output+"/motion-%03d.png"%frame)
	var report:={"venue":gs.current_venue,"identity":character.identity if is_instance_valid(character) else {},"frames":frames,"scope":"One uninstalled face override in actual native venue rendering. Existing body rig and game movement; seating and broader cast unchanged. Not a phone performance test."}
	var file:=FileAccess.open(output+"/review.json",FileAccess.WRITE);file.store_string(JSON.stringify(report,"\t"));file.close()
	print("FACE_PROTOTYPE_NATIVE_READY frames=",frames.size());quit(0)
