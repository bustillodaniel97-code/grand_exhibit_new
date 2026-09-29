extends "res://tools/world_edges_campaign.gd"
## Stage visitors at real seat approaches, then exercise the production lifecycle.
## Saves remain isolated. No direct seated pose or progress assignments are used.
func run() -> void:
	output=OS.get_cmdline_user_args()[0];DirAccess.make_dir_recursive_absolute(output)
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
	var Floor=load("res://scenes/venue/floor/venue_floor.gd")
	var Character=load("res://scenes/venue/floor/character.gd")
	var records: Array=[];var cast_index:=0
	for vid in root.get_node("DataLoader").venue_order():
		gs.current_venue=vid;floor_node.retheme(vid)
		var visitors: Array=[]
		for i in floor_node._seats.size():
			var seat: Vector2=floor_node._seats[i]
			var c=Character.new();c.set_look_slot(cast_index%24);cast_index+=1
			floor_node._canvas.add_child(c);c.set_process(false)
			var route: Array=floor_node._nav_path(floor_node._door_g,seat)
			if route.is_empty():printerr("SEAT_HAS_NO_ENTRANCE_ROUTE ",vid," ",seat);quit(1);return
			var v=Floor.Visitor.new();v.node=c;v.pos=route[maxi(0,route.size()-2)]
			v.target=seat;v.path=route.slice(maxi(0,route.size()-1));v.state="rest";v.seat=i
			floor_node._seat_taken[i]=true;floor_node._visitors.append(v);visitors.append(v)
			floor_node._place(c,v.pos)
		for frame in 120:
			floor_node._update_visitors(.025)
			for v in visitors:v.node._process(.025)
		var seated:=0
		for v in visitors:
			if v.node.seated and v.node._seating_progress>=1:seated+=1;v.wait=100.0
		if seated!=visitors.size():
			for v in visitors:
				if not v.node.seated:printerr("SEATING_NOT_REACHED ",vid," seat=",v.target," pos=",v.pos," state=",v.state," path=",v.path)
			quit(1);return
		floor_node._user_zoom=1.0;floor_node._fit_canvas()
		await capture(output+"/"+vid+"-overview.png")
		floor_node._user_zoom=3.2;floor_node._fit_canvas()
		for i in visitors.size():
			var v=visitors[i]
			var target: Vector2=v.node.position*floor_node._canvas.scale+floor_node._canvas.position
			floor_node._pan_camera(floor_node.size*.5-target)
			await capture(output+"/"+vid+"-seat-%02d.png"%i)
			records.append({"venue":vid,"seat":i,"identity":v.node.identity,"position":str(v.pos),"contact":str(v.target),"facing":str(floor_node._seat_facings[v.target]),"progress":v.node._seating_progress})
		# Let the actual rest timer expire; reserve the seat until standing ends.
		for v in visitors:v.wait=0
		for frame in 40:
			floor_node._update_visitors(.025)
			for v in visitors:v.node._process(.025)
			if vid=="whispering_pines":await capture(output+"/pines-rise-%02d.png"%frame)
		for v in visitors:
			if v.node.seated or v.seat>=0 or not v.node._seating_frames.is_empty():printerr("SEAT_NOT_RELEASED ",vid);quit(1);return
		print("CAMPAIGN_SEATING ",vid," seats=",seated)
	var file:=FileAccess.open(output+"/capture-manifest.json",FileAccess.WRITE);file.store_string(JSON.stringify(records,"\t"));file.close()
	quit(0)
