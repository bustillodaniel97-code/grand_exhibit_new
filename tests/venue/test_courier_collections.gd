extends SceneTree
var failures:=0
func check(ok: bool,label: String) -> void:
	if not ok:failures+=1;printerr("FAIL: ",label)
func _initialize() -> void:call_deferred("run")
func run() -> void:
	root.get_node("SaveSystem").set_process(false)
	var gs: Node=root.get_node("GameState");gs.reset_to_new_game();gs.ready_flag=true
	var floor_node: Node=load("res://scenes/venue/floor/venue_floor.tscn").instantiate()
	floor_node.set_size(Vector2(720,760));root.add_child(floor_node)
	for n in root.get_children():n.process_mode=Node.PROCESS_MODE_DISABLED
	for vid in root.get_node("DataLoader").venue_order():
		gs.current_venue=vid
		for dept in ["ticket","archive","gallery","promotions"]:
			for track in ["staff","speed","value"]:gs.set_dept_level(vid,dept,track,8)
		floor_node.retheme(vid);floor_node.set_rates(root.get_node("Economy").venue_rates(vid))
		floor_node._windows_active=floor_node._max_windows
		for w in floor_node._windows_active:floor_node._stacks[w]=1
		var start: int=floor_node._porter_trips
		var collisions:=0
		for step in 3000:
			floor_node._update_porters(.05)
			var claimed: Array=[]
			for p in floor_node._porters:
				if p.state in ["to_window","collect"]:
					if p.window in claimed:collisions+=1
					claimed.append(p.window)
			if floor_node._porter_trips-start>=floor_node._windows_active:break
		check(collisions==0,vid+" each collection point has one courier")
		check(floor_node._porter_trips-start>=floor_node._windows_active,vid+" every single-sale batch reaches the archive without another sale")
		for p in floor_node._porters:
			check(floor_node._porter_speed(p)/p.node.preferred_walk_speed(1)<=1.95+.0001,"upgraded courier keeps a bounded working cadence")
		print("COURIER_COLLECTION ",vid," deliveries=",floor_node._porter_trips-start)
	print("Courier collection failures: ",failures)
	quit(1 if failures else 0)
