extends "res://tools/world_edges_campaign.gd"
const Character:=preload("res://scenes/venue/floor/character.gd")
func update_characters(n: Node,dt: float) -> void:
	if n is Character:n._process(dt)
	for child in n.get_children():update_characters(child,dt)
func run() -> void:
	output=OS.get_cmdline_user_args()[0];DirAccess.make_dir_recursive_absolute(output)
	root.get_node("SaveSystem").set_process(false)
	var gs: Node=root.get_node("GameState");gs.reset_to_new_game();seed(817)
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
		gs.current_venue=vid;floor_node.retheme(vid)
		floor_node.set_rates(root.get_node("Economy").venue_rates(vid))
		floor_node.advance_sim(75);update_characters(vp,0)
		floor_node._user_zoom=1.0;floor_node._fit_canvas()
		await capture(output+"/"+vid+"-overview.png")
		var actors: Array=[]
		for v in floor_node._visitors:
			actors.append({"identity":v.node.identity,"speed":v.speed,"cycles_per_second":v.speed/v.node.preferred_walk_speed(1),"state":v.state})
		records.append({"venue":vid,"visitors":actors,"porter_trips_at_75s":floor_node._porter_trips})
		if vid in ["whispering_pines","infinite_museum"]:
			for zoom in [1.0,2.4]:
				floor_node._user_zoom=zoom;floor_node._fit_canvas()
				if zoom>1:
					var target: Vector2=floor_node._porters[0].node.position*floor_node._canvas.scale+floor_node._canvas.position
					floor_node._pan_camera(floor_node.size*.5-target)
				for frame in 90:
					floor_node.advance_sim(1.0/30.0);update_characters(vp,1.0/30.0)
					await capture(output+"/"+vid+"-"+("close" if zoom>1 else "normal")+"-%03d.png"%frame)
		print("WALKING_CAMPAIGN_CAPTURE ",vid)
	var file:=FileAccess.open(output+"/capture-manifest.json",FileAccess.WRITE);file.store_string(JSON.stringify(records,"\t"));file.close()
	quit(0)
