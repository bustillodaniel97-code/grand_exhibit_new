extends "res://tools/walking_campaign_review.gd"
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
		for dept in ["ticket","archive","promotions","gallery"]:
			for track in ["staff","speed","value"]:gs.set_dept_level(vid,dept,track,8)
		floor_node.set_rates(root.get_node("Economy").venue_rates(vid))
		for p in floor_node._porters:
			if p.node._cart_set.is_empty():printerr("FAIL missing live cart asset ",vid);quit(1);return
		var seen: Dictionary={}
		for step in 900:
			floor_node.advance_sim(.2);update_characters(vp,.2)
			for i in floor_node._porters.size():
				var p: Variant=floor_node._porters[i]
				if p.state not in ["to_window","to_vault"]:continue
				var key:="%d-%s"%[i,"loaded" if p.carried>0 else "empty"]
				if seen.has(key):continue
				seen[key]=true
				floor_node._user_zoom=2.5;floor_node._fit_canvas()
				var target: Vector2=p.node.position*floor_node._canvas.scale+floor_node._canvas.position
				floor_node._pan_camera(floor_node.size*.5-target)
				await capture(output+"/"+vid+"-"+key+".png")
				records.append({"venue":vid,"key":key,"identity":p.node.identity,"state":p.state,"position":str(p.pos),"carried":p.carried,"seconds":(step+1)*.2})
				if vid=="whispering_pines" and key=="0-loaded":
					for zoom in [1.0,2.5]:
						floor_node._user_zoom=zoom;floor_node._fit_canvas()
						if zoom>1:
							var center: Vector2=p.node.position*floor_node._canvas.scale+floor_node._canvas.position
							floor_node._pan_camera(floor_node.size*.5-center)
						for frame in 90:
							floor_node.advance_sim(1.0/30.0);update_characters(vp,1.0/30.0)
							await capture(output+"/pines-"+("close" if zoom>1 else "normal")+"-%03d.png"%frame)
			if seen.size()==floor_node._porters.size()*2:break
		floor_node._user_zoom=1.0;floor_node._fit_canvas();await capture(output+"/"+vid+"-overview.png")
		print("CART_CAMPAIGN ",vid," observed ",seen.size(),"/",floor_node._porters.size()*2)
	var file:=FileAccess.open(output+"/capture-manifest.json",FileAccess.WRITE);file.store_string(JSON.stringify(records,"\t"));file.close()
	quit(0)
