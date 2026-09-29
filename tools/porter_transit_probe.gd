extends SceneTree
## Diagnostic, not a passing collision test: preserve the remaining transit issues.
func _initialize() -> void:call_deferred("run")
func heading(p: Variant) -> Vector2:
	if p.node._view_back:return Vector2.UP if p.node.facing>0 else Vector2.LEFT
	return Vector2.RIGHT if p.node.facing>0 else Vector2.DOWN
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
		for w in floor_node._max_windows:floor_node._stacks[w]=1
		var static_conflicts:=0;var moving_samples:=0;var courier_pairs:=0;var examples: Array=[]
		for step in 1200:
			floor_node._update_porters(.05)
			if step%2:continue
			for i in floor_node._porters.size():
				var p: Variant=floor_node._porters[i]
				if not p.node.walking:continue
				moving_samples+=1
				if not floor_node._porter_layout.fits(p.pos,heading(p),false):
					static_conflicts+=1
					if examples.size()<12:examples.append({"seconds":step*.05,"kind":"transit_footprint","position":str(p.pos),"state":p.state,"heading":str(heading(p))})
				for j in range(i+1,floor_node._porters.size()):
					var other: Variant=floor_node._porters[j]
					var pair:=Geometry2D.get_closest_points_between_segments(p.pos,p.pos+heading(p)*.68,other.pos,other.pos+heading(other)*.68)
					if pair[0].distance_to(pair[1])<.60:courier_pairs+=1
		records.append({"venue":vid,"moving_samples":moving_samples,"static_footprint_conflicts":static_conflicts,"courier_pair_conflicts":courier_pairs,"examples":examples})
		print("TRANSIT_DIAGNOSTIC ",vid," static=",static_conflicts," pairs=",courier_pairs)
	var f:=FileAccess.open(OS.get_cmdline_user_args()[0],FileAccess.WRITE);f.store_string(JSON.stringify(records,"\t"));f.close();quit(0)
