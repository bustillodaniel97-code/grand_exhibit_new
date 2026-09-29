extends "res://tools/walking_campaign_review.gd"
## Actual admission flow under a ticket-service bottleneck. No pose placement.
func run() -> void:
	output=OS.get_cmdline_user_args()[0];DirAccess.make_dir_recursive_absolute(output)
	root.get_node("SaveSystem").set_process(false)
	var gs: Node=root.get_node("GameState");gs.reset_to_new_game();seed(913)
	vp=SubViewport.new();vp.size=Vector2i(720,1280);vp.render_target_update_mode=SubViewport.UPDATE_ALWAYS
	root.add_child(vp);vp.add_child(load("res://scenes/main.tscn").instantiate())
	await create_timer(2).timeout
	for i in 4:load("res://scripts/ui/popup_manager.gd").close_top()
	var floor_node: Node=find_floor(vp)
	for n in root.get_children():
		if n!=vp:n.process_mode=Node.PROCESS_MODE_DISABLED
	vp.get_child(0).process_mode=Node.PROCESS_MODE_DISABLED
	var records: Array=[]
	for vid in root.get_node("DataLoader").venue_order():
		gs.current_venue=vid
		for dept in ["ticket","archive","gallery","promotions"]:
			for track in ["staff","speed","value"]:gs.set_dept_level(vid,dept,track,8)
		floor_node.retheme(vid)
		floor_node.set_rates({"arrival_per_s":2.0,"serve_per_s":.5,"transport_per_s":2.0,"choke_id":"ticket"})
		# Suspend service for this visual fixture so every lane can fill through
		# real arrivals. Service itself is covered by the campaign flow tests.
		floor_node._serve_t.fill(-10000.0)
		var captured: Dictionary={}
		for step in 3600:
			floor_node._serve_t.fill(-10000.0)
			floor_node.advance_sim(.05)
			for w in floor_node._windows_active:
				if captured.has(w):continue
				var q: Array=floor_node._queues[w]
				var full: bool=q.size()==floor_node._slots_per_window
				for v in q:full=full and v.state=="queue"
				if not full:continue
				update_characters(vp,0)
				floor_node._user_zoom=3.2;floor_node._fit_canvas()
				var at: Vector2=floor_node._lifted(floor_node._admissions.slot(w,0))
				var target: Vector2=at*floor_node._canvas.scale+floor_node._canvas.position
				floor_node._pan_camera(floor_node.size*.5-target)
				await capture(output+"/"+vid+"-station-%d.png"%w)
				captured[w]=true
				records.append({"venue":vid,"station":w,"time":step*.05,"count":q.size(),"gap":floor_node._admissions.slot_gap,"service_paused_for_capture":true})
			if captured.size()==floor_node._windows_active:break
		if captured.size()!=floor_node._windows_active:
			printerr("QUEUE_CAPTURE_INCOMPLETE ",vid," ",captured.keys())
		print("QUEUE_NATIVE_CAPTURE ",vid," ",captured.size(),"/",floor_node._windows_active)
	var file:=FileAccess.open(output+"/capture-manifest.json",FileAccess.WRITE);file.store_string(JSON.stringify(records,"\t"));file.close()
	quit(0)
