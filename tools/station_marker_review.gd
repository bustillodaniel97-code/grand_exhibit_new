extends "res://tools/walking_campaign_review.gd"
## Real native UI at initial/ready/cooldown states across all twelve layouts.
func run() -> void:
	output=OS.get_cmdline_user_args()[0];DirAccess.make_dir_recursive_absolute(output)
	root.get_node("SaveSystem").set_process(false)
	var gs: Node=root.get_node("GameState");gs.reset_to_new_game();seed(918)
	vp=SubViewport.new();vp.size=Vector2i(720,1280);vp.render_target_update_mode=SubViewport.UPDATE_ALWAYS
	root.add_child(vp);vp.add_child(load("res://scenes/main.tscn").instantiate());await create_timer(2).timeout
	for i in 4:load("res://scripts/ui/popup_manager.gd").close_top()
	for node in root.get_children():
		if node!=vp:node.process_mode=Node.PROCESS_MODE_DISABLED
	vp.get_child(0).process_mode=Node.PROCESS_MODE_DISABLED
	var f: Node=find_floor(vp);var records: Array=[]
	for vid in root.get_node("DataLoader").venue_order():
		gs.current_venue=vid
		for dept in ["ticket","archive","gallery","promotions"]:
			for track in ["staff","speed","value"]:gs.set_dept_level(vid,dept,track,8)
		f.retheme(vid);f.set_rates(root.get_node("Economy").venue_rates(vid))
		for tick in 600:f.advance_sim(.05)
		update_characters(vp,0)
		var items: Array=gs.dept_items(vid,"ticket")
		for i in items.size():
			items[i].pending=BigNumber.from_float(123000 if i%3==0 else 0).to_save()
			items[i].collect_ready_at=int(Time.get_unix_time_from_system())+23 if i%3==1 else 0
		f._refresh_station_ui()
		var markers: Array=[]
		for i in f._station_chips.size():markers.append({"station":i,"text":f._station_chips[i].text,"size":str(f._station_chips[i].size),"minimum":str(f._station_chips[i].get_combined_minimum_size())})
		for zoom in [1.0,2.0]:
			f._user_zoom=zoom;f._fit_canvas()
			if zoom>1:
				var target:=Vector2.ZERO
				for i in f._station_chips.size():target+=f.station_center(i)
				target/=maxi(1,f._station_chips.size())
				f._pan_camera(f.size*.5-(target*f._canvas.scale+f._canvas.position))
			await capture(output+"/%s-%s.png"%[vid,"overview" if zoom==1 else "close"])
		records.append({"venue":vid,"markers":markers})
		print("STATION_MARKER_CAPTURE ",vid)
	var file:=FileAccess.open(output+"/review.json",FileAccess.WRITE);file.store_string(JSON.stringify(records,"\t"));file.close()
	quit(0)
