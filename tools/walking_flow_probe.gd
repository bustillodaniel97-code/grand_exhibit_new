extends SceneTree
func _initialize() -> void:call_deferred("run")
func run() -> void:
	root.get_node("SaveSystem").set_process(false)
	var gs: Node=root.get_node("GameState");gs.reset_to_new_game();gs.ready_flag=true
	var args:=OS.get_cmdline_user_args();var out:=args[0]
	var venue: String=args[1] if args.size()>1 else "whispering_pines"
	var run_seed: int=int(args[2]) if args.size()>2 else 817
	gs.current_venue=venue;seed(run_seed)
	var floor_node: Node=load("res://scenes/venue/floor/venue_floor.tscn").instantiate()
	floor_node.set_size(Vector2(720,760));root.add_child(floor_node);floor_node.time_scale=0
	for n in root.get_children():n.process_mode=Node.PROCESS_MODE_DISABLED
	var report:={"venue":venue,"seed":run_seed,"first_trip":-1,"samples":[]}
	for step in 3600:
		if step%10==0:floor_node.set_rates(root.get_node("Economy").venue_rates(venue))
		floor_node.advance_sim(.05)
		if floor_node._porter_trips>0 and report.first_trip<0:report.first_trip=step*.05
		if step%100==0:
			var states: Dictionary={};var porters: Array=[]
			for v in floor_node._visitors:states[v.state]=int(states.get(v.state,0))+1
			for p in floor_node._porters:porters.append({"state":p.state,"pos":str(p.pos),"target":str(p.target),"remaining_points":p.path.size()})
			report.samples.append({"t":step*.05,"visitors":states,"stacks":floor_node._stacks.duplicate(),"porters":porters,"trips":floor_node._porter_trips})
	var f:=FileAccess.open(out,FileAccess.WRITE);f.store_string(JSON.stringify(report,"\t"));f.close()
	print("WALK_FLOW ",venue," first delivery=",report.first_trip," trips=",floor_node._porter_trips)
	quit(0)
