extends "res://tools/world_edges_campaign.gd"
## Natural exterior arrival; only the seated dwell is shortened for the review.
func run() -> void:
	output=OS.get_cmdline_user_args()[0];DirAccess.make_dir_recursive_absolute(output)
	root.get_node("SaveSystem").set_process(false)
	var gs: Node=root.get_node("GameState");gs.reset_to_new_game()
	vp=SubViewport.new();vp.size=Vector2i(720,1280);vp.render_target_update_mode=SubViewport.UPDATE_ALWAYS
	root.add_child(vp);vp.add_child(load("res://scenes/main.tscn").instantiate())
	await create_timer(2).timeout
	for i in 4:load("res://scripts/ui/popup_manager.gd").close_top()
	var floor_node: Node=find_floor(vp)
	await create_timer(.6).timeout
	for node in root.get_children():
		if node!=vp:node.process_mode=Node.PROCESS_MODE_DISABLED
	vp.get_child(0).process_mode=Node.PROCESS_MODE_DISABLED
	var records: Array=[]
	for vid in root.get_node("DataLoader").venue_order():
		gs.current_venue=vid;floor_node.retheme(vid)
		var plaza=floor_node._plaza;var sitter: Dictionary={}
		for step in 3600:
			plaza.advance(.05)
			for p in plaza.people:
				p.node._process(.05)
				if p.state=="sit_down" and p.node.seated:sitter=p
			if not sitter.is_empty():break
		if sitter.is_empty():printerr("NO_NATURAL_SITTER ",vid);quit(1);return
		floor_node._user_zoom=3.2;floor_node._fit_canvas()
		var target: Vector2=sitter.node.position*floor_node._canvas.scale+floor_node._canvas.position
		floor_node._pan_camera(floor_node.size*.5-target)
		var phases: Array=[]
		for frame in 40:
			if sitter.state=="activity":sitter.wait=0
			plaza.advance(.05)
			for p in plaza.people:p.node._process(.05)
			phases.append({"state":sitter.state,"progress":sitter.node._seating_progress,"position":str(sitter.pos)})
			if frame in [0,6,14,22,30,39] or vid=="whispering_pines":
				await capture(output+"/"+vid+"-%02d.png"%frame)
		records.append({"venue":vid,"identity":sitter.node.identity,"natural_arrival_seconds":plaza.elapsed-2.0,"dwell_shortened":true,"frames":phases})
		print("PUBLIC_SEATING_CAPTURE ",vid)
	var file:=FileAccess.open(output+"/capture-manifest.json",FileAccess.WRITE);file.store_string(JSON.stringify(records,"\t"));file.close()
	quit(0)
