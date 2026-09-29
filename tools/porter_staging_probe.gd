extends SceneTree
const Layout:=preload("res://scenes/venue/floor/porter_layout.gd")
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
		var layout:=Layout.new();var began:=Time.get_ticks_usec();layout.configure(floor_node)
		var allocation_ms:=(Time.get_ticks_usec()-began)/1000.0
		print("STAGING ",vid," failures=",layout.failures)
		if "counter:4" in layout.failures:
			var station: Dictionary=floor_node._admissions.stations[4]
			var before:=layout.claimed.duplicate();layout.claimed.clear()
			print("COUNTER4 ",station," independent=",layout.pick(layout.around(station.porter,station.front,12),station.center,2.4))
			layout.claimed=before
		records.append({"venue":vid,"failures":layout.failures,"counters":layout.counters,"homes":layout.homes,"drops":layout.drops,"allocation_ms":allocation_ms})
	var f:=FileAccess.open(OS.get_cmdline_user_args()[0],FileAccess.WRITE);f.store_string(JSON.stringify(records,"\t"));f.close();quit(0)
