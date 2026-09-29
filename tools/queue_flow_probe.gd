extends SceneTree
func _initialize() -> void:call_deferred("run")
func run() -> void:
	root.get_node("SaveSystem").set_process(false)
	var gs: Node=root.get_node("GameState");gs.reset_to_new_game();gs.ready_flag=true;seed(913)
	var args:=OS.get_cmdline_user_args();var vid: String=args[0];gs.current_venue=vid
	for dept in ["ticket","archive","gallery","promotions"]:
		for track in ["staff","speed","value"]:gs.set_dept_level(vid,dept,track,8)
	var f: Node=load("res://scenes/venue/floor/venue_floor.tscn").instantiate()
	f.set_size(Vector2(720,760));root.add_child(f)
	for n in root.get_children():n.process_mode=Node.PROCESS_MODE_DISABLED
	f.set_rates({"arrival_per_s":2.0,"serve_per_s":.5,"transport_per_s":2.0,"choke_id":"ticket"})
	for step in 3600:
		f.advance_sim(.05)
		if step in [1199,2399,3599]:
			for w in f._windows_active:
				var entries: Array=[]
				for v in f._queues[w]:entries.append({"state":v.state,"pos":str(v.pos),"target":str(v.target),"next":str(v.path[0]) if not v.path.is_empty() else "none","entered":v.queue_entered})
				print("QUEUE_PROBE ",step*.05," w=",w," ",JSON.stringify(entries))
			for v in f._visitors:
				if v.departing_window>=0:print("DEPARTED ",v.departing_window," ",v.state," ",v.pos)
	quit(0)
