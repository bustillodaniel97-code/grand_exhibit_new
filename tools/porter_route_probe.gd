extends SceneTree
const Router:=preload("res://scenes/venue/floor/porter_router.gd")
func _initialize() -> void:call_deferred("run")
func run() -> void:
	root.get_node("SaveSystem").set_process(false)
	var gs: Node=root.get_node("GameState");gs.reset_to_new_game();gs.ready_flag=true
	var floor_node: Node=load("res://scenes/venue/floor/venue_floor.tscn").instantiate();floor_node.set_size(Vector2(720,760));root.add_child(floor_node)
	for n in root.get_children():n.process_mode=Node.PROCESS_MODE_DISABLED
	var records: Array=[]
	for vid in root.get_node("DataLoader").venue_order():
		gs.current_venue=vid
		for dept in ["ticket","archive","gallery","promotions"]:
			for track in ["staff","speed","value"]:gs.set_dept_level(vid,dept,track,8)
		floor_node.retheme(vid);floor_node.set_rates(root.get_node("Economy").venue_rates(vid))
		var router:=Router.new();router.configure(floor_node._porter_layout)
		var routes: Array=[];var failed:=0;var began:=Time.get_ticks_msec()
		for i in 3:
			var bay: Dictionary=floor_node._porter_layout.drops[i]
			for w in floor_node._max_windows:
				var counter: Dictionary=floor_node._porter_layout.counters[w]
				var path:=router.route(bay.at,bay.heading,counter.at,counter.heading)
				if path.is_empty():failed+=1
				routes.append({"porter":i,"station":w,"steps":path.size(),"expanded":router.last_expanded,"bay":str(bay),"counter":str(counter)})
		records.append({"venue":vid,"failed":failed,"routes":routes,"cached_poses":router.fit_cache.size(),"elapsed_ms":Time.get_ticks_msec()-began})
		print("ORIENTED_ROUTE ",vid," failures=",failed," of ",routes.size()," cached=",router.fit_cache.size()," ms=",Time.get_ticks_msec()-began)
		if OS.has_environment("GRAND_EXHIBIT_ROUTE_FIRST"):break
	var f:=FileAccess.open(OS.get_cmdline_user_args()[0],FileAccess.WRITE);f.store_string(JSON.stringify(records,"\t"));f.close();quit(0)
