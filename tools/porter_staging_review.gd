extends "res://tools/walking_campaign_review.gd"
func centered(floor_node: Node,point: Vector2) -> void:
	floor_node._user_zoom=2.5;floor_node._fit_canvas()
	var target: Vector2=floor_node._lifted(point)*floor_node._canvas.scale+floor_node._canvas.position
	floor_node._pan_camera(floor_node.size*.5-target)
func run() -> void:
	output=OS.get_cmdline_user_args()[0];DirAccess.make_dir_recursive_absolute(output)
	root.get_node("SaveSystem").set_process(false)
	var gs: Node=root.get_node("GameState");gs.reset_to_new_game();seed(817)
	vp=SubViewport.new();vp.size=Vector2i(720,1280);vp.render_target_update_mode=SubViewport.UPDATE_ALWAYS
	root.add_child(vp);vp.add_child(load("res://scenes/main.tscn").instantiate());await create_timer(2).timeout
	for i in 4:load("res://scripts/ui/popup_manager.gd").close_top()
	var floor_node: Node=find_floor(vp)
	for n in root.get_children():
		if n!=vp:n.process_mode=Node.PROCESS_MODE_DISABLED
	vp.get_child(0).process_mode=Node.PROCESS_MODE_DISABLED
	var records: Array=[]
	for vid in root.get_node("DataLoader").venue_order():
		if OS.has_environment("GRAND_EXHIBIT_STAGING_ONLY") and vid not in OS.get_environment("GRAND_EXHIBIT_STAGING_ONLY").split(","):continue
		gs.current_venue=vid
		for dept in ["ticket","archive","promotions","gallery"]:
			for track in ["staff","speed","value"]:gs.set_dept_level(vid,dept,track,8)
		floor_node.retheme(vid);floor_node.set_rates(root.get_node("Economy").venue_rates(vid));update_characters(vp,0)
		if not floor_node._porter_layout.failures.is_empty():printerr("FAIL layout ",vid);quit(1);return
		floor_node._user_zoom=1.0;floor_node._camera_pan=Vector2.ZERO;floor_node._fit_canvas()
		await capture(output+"/"+vid+"-overview.png")
		var passages: Dictionary={"cloudrest":[Vector2(8.7,15.7)],"celestial_conservatory":[Vector2(12.25,5.75)],"ironwood_citadel":[Vector2(11.5,10.3),Vector2(2.75,12.1)],"chronos_spire":[Vector2(19.2,10.75)],"infinite_museum":[Vector2(16,21.9)]}
		var passage_index:=0
		for point in passages.get(vid,[]):
			centered(floor_node,point);await capture(output+"/"+vid+"-passage-%d.png"%passage_index);passage_index+=1
		for i in floor_node._porters.size():
			var p: Variant=floor_node._porters[i];centered(floor_node,p.pos)
			await capture(output+"/"+vid+"-bay-%d.png"%i)
		floor_node._stacks.fill(0)
		for w in floor_node._max_windows:floor_node._stacks[w]=1
		var seen: Dictionary={}
		for step in 3000:
			# Single-sale fixture exercises actual courier states without visitor
			# service obscuring the parked staff with a fresh crowd every capture.
			floor_node._update_porters(.05);floor_node._update_reactive_doors(.05);update_characters(vp,.05)
			for p in floor_node._porters:
				if p.state not in ["collect","deposit"]:continue
				var expected: Dictionary=floor_node._porter_counter(p.window) if p.state=="collect" else floor_node._porter_bay(p)
				if p.pos.distance_to(expected.at)>.001:printerr("FAIL wrong service location ",vid," ",p.state);quit(1);return
				var key:="%s-%d"%[p.state,p.window]
				if seen.has(key):continue
				seen[key]=true;centered(floor_node,p.pos)
				var before:={"state":p.state,"pos":str(p.pos),"node":str(p.node.position),"dock":str(p.dock),"screen":str(p.node.get_global_transform_with_canvas().origin)}
				await capture(output+"/"+vid+"-"+key+".png")
				records.append({"venue":vid,"key":key,"position":str(p.pos),"heading":str(p.dock.heading),"porter":p.node.identity.id,"before_capture":before,"after_state":p.state,"after_node":str(p.node.position)})
			if seen.size()==floor_node._max_windows*2:break
		if seen.size()!=floor_node._max_windows*2:printerr("FAIL incomplete service lifecycle ",vid);quit(1);return
		# Preserve completed venues if a long native-render run is interrupted.
		var f:=FileAccess.open(output+"/capture-manifest.json",FileAccess.WRITE);f.store_string(JSON.stringify(records,"\t"));f.close()
		print("STAGING_CAPTURE ",vid," ",seen.size(),"/",floor_node._max_windows*2)
	quit(0)
