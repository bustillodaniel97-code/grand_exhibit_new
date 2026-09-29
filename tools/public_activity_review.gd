extends "res://tools/world_edges_campaign.gd"
## Natural public arrivals in every venue, then native staged time samples of
## the same feeding episode. Camera uses the production zoom and pan limits.
func run() -> void:
	output=OS.get_cmdline_user_args()[0]
	if DirAccess.make_dir_recursive_absolute(output)!=OK:
		printerr("FAIL create activity capture directory ",output);quit(1);return
	root.get_node("SaveSystem").set_process(false)
	var gs: Node=root.get_node("GameState");gs.reset_to_new_game();seed(817)
	vp=SubViewport.new();vp.size=Vector2i(720,1280);vp.render_target_update_mode=SubViewport.UPDATE_ALWAYS
	root.add_child(vp);vp.add_child(load("res://scenes/main.tscn").instantiate())
	await create_timer(2).timeout
	for i in 4:load("res://scripts/ui/popup_manager.gd").close_top()
	var floor_node: Node=find_floor(vp)
	await create_timer(.6).timeout
	for node in root.get_children():
		if node != vp:node.process_mode=Node.PROCESS_MODE_DISABLED
	vp.get_child(0).process_mode=Node.PROCESS_MODE_DISABLED
	var records: Array=[]
	for vid in root.get_node("DataLoader").venue_order():
		gs.current_venue=vid;floor_node.retheme(vid)
		for dept in ["ticket","archive","promotions","gallery"]:
			for track in ["staff","speed","value"]:gs.set_dept_level(vid,dept,track,8)
		floor_node.set_rates(root.get_node("Economy").venue_rates(vid))
		var feeder: Dictionary={}
		# Natural arrivals can now wait for a reserved narrow passage. Allow
		# three minutes to observe feeding; do not teleport the guest for a shot.
		for step in 3600:
			floor_node.advance_sim(.05)
			for p in floor_node._plaza.people:
				p.node._process(.05)
				if p.node._feeding_frame>=0:feeder=p
			if not feeder.is_empty():break
		if feeder.is_empty():printerr("FAIL no natural feeder ",vid);quit(1);return
		await capture(output+"/"+vid+"-overview.png")
		floor_node._user_zoom=3.2;floor_node._fit_canvas()
		var target: Vector2=feeder.node.position*floor_node._canvas.scale+floor_node._canvas.position
		floor_node._pan_camera(floor_node.size*.5-target)
		for time in [0.0,.75,1.125,1.5,2.5]:
			feeder.activity_time=time
			feeder.node.set_bird_feeding(true,time);feeder.node._process(0)
			for flock in floor_node._plaza.flocks:flock.queue_redraw()
			await capture(output+"/"+vid+"-feed-"+str(time)+".png")
		if vid in ["whispering_pines","infinite_museum"]:
			feeder.activity_time=0.0
			for frame in 32:
				floor_node.advance_sim(.125)
				for p in floor_node._plaza.people:p.node._process(.125)
				await capture(output+"/"+vid+"-motion-%02d.png"%frame)
		records.append({"venue":vid,"identity":feeder.node.identity,"position":str(feeder.pos),"frames":feeder.node._feeding_frames.size(),"camera_zoom":floor_node._user_zoom})
		print("ACTIVITY_CAPTURE ",vid)
	var file:=FileAccess.open(output+"/capture-manifest.json",FileAccess.WRITE);file.store_string(JSON.stringify(records,"\t"));file.close()
	quit(0)
