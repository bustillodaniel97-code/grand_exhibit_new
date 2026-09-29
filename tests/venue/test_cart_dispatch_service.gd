extends SceneTree
const Geometry:=preload("res://scenes/venue/floor/cart_traffic_geometry.gd")
var failures:=0
func check(ok: bool,label: String) -> void:
	if not ok:failures+=1;printerr("FAIL: ",label)
func _initialize() -> void:call_deferred("run")
func run() -> void:
	root.get_node("SaveSystem").set_process(false)
	var gs: Node=root.get_node("GameState");gs.reset_to_new_game();gs.ready_flag=true
	var floor_node: Node=load("res://scenes/venue/floor/venue_floor.tscn").instantiate();floor_node.set_size(Vector2(720,760));root.add_child(floor_node)
	# Simulated-time lifecycle uses the deterministic work budget; wall-time
	# responsiveness is measured separately in native/default-budget runs.
	floor_node._porter_planning_budget_usec=0
	for n in root.get_children():n.process_mode=Node.PROCESS_MODE_DISABLED
	check(floor_node._porters[0].staged,"initial porter gets a bay even when the prop cache is current")
	for step in 20:floor_node._update_porters(.05)
	var before_hiring: Vector2=floor_node._porters[0].pos
	var records: Array=[]
	var overlap_samples:=0;var concurrent_samples:=0;var checked_pairs:=0
	for vid in root.get_node("DataLoader").venue_order():
		if OS.has_environment("PORTER_STAGING_ONLY") and vid not in OS.get_environment("PORTER_STAGING_ONLY").split(","):continue
		var venue_overlaps:=0
		gs.current_venue=vid
		for dept in ["ticket","archive","gallery","promotions"]:
			for track in ["staff","speed","value"]:gs.set_dept_level(vid,dept,track,1)
		floor_node.retheme(vid);floor_node.set_rates(root.get_node("Economy").venue_rates(vid))
		check(floor_node._porter_layout.failures.is_empty(),vid+" initial one-porter venue also has legal staging")
		for step in 20:floor_node._update_porters(.05)
		before_hiring=floor_node._porters[0].pos
		for dept in ["ticket","archive","gallery","promotions"]:
			for track in ["staff","speed","value"]:gs.set_dept_level(vid,dept,track,8)
		floor_node.retheme(vid);floor_node.set_rates(root.get_node("Economy").venue_rates(vid))
		check(floor_node._porters[0].pos.distance_to(before_hiring)<.0001,vid+" hiring colleagues does not teleport an active courier")
		var layout: RefCounted=floor_node._porter_layout
		check(layout.failures.is_empty(),vid+" every counter and personal bay fits")
		for w in floor_node._windows_active:
			var edge: Vector2=floor_node._admissions.point(w,Vector2(layout.counter_size.x*.42,0))
			check(not layout.fits(edge,floor_node._admissions.stations[w].front,false),vid+" actual desk edge blocks a parked cart beyond the old anchor disc")
		var poses: Array=layout.counters+layout.drops
		for dock in poses:
			if dock.is_empty():continue
			check(layout.fits(dock.at,dock.heading,false),vid+" whole parked footprint clears staff/furniture/elevation edges")
			for t in [.25,.5,.75]:check(layout.fits(dock.at-dock.heading*t,dock.heading,false),vid+" straight parking approach fits")
		for i in poses.size():
			for j in range(i+1,poses.size()):
				if poses[i].is_empty() or poses[j].is_empty():continue
				var a: Dictionary=poses[i];var b: Dictionary=poses[j]
				var pair:=Geometry2D.get_closest_points_between_segments(a.at,a.at+a.heading*.68,b.at,b.at+b.heading*.68)
				check(pair[0].distance_to(pair[1])>=.60-.0001,vid+" distinct parked trolleys cannot intersect")
		var parked:=0;var deposits:=0
		for w in floor_node._max_windows:floor_node._stacks[w]=1
		var seen: Dictionary={};var seen_deposit: Dictionary={}
		# Full physical return paths in the largest museums exceed the old
		# point-path 150-second fixture window. Keep eventual service bounded.
		for step in 6000:
			floor_node._update_porters(.05)
			var moving:=0
			for a in floor_node._porters.size():
				var pa: Variant=floor_node._porters[a]
				if not pa.motion_step.is_empty():moving+=1
				for b in range(a+1,floor_node._porters.size()):
					var pb: Variant=floor_node._porters[b]
					if absf(floor_node._porter_layout._height_at(pa.pos)-floor_node._porter_layout._height_at(pb.pos))>=73.0:continue
					checked_pairs+=1
					if Geometry.overlap(pa.pos,Geometry.heading(pa),pb.pos,Geometry.heading(pb)):overlap_samples+=1;venue_overlaps+=1
			if moving>1:concurrent_samples+=1
			for p in floor_node._porters:
				if p.state in ["collect","deposit"]:
					var expected: Dictionary=floor_node._porter_counter(p.window) if p.state=="collect" else floor_node._porter_bay(p)
					check(p.pos.distance_to(expected.at)<.001,vid+" collection is at its actual counter and unloading at its personal bay")
					check(p.pos.distance_to(p.dock.at)<.001,vid+" real actor reaches its allocated dock")
					check(p.node.position.distance_to(floor_node._lifted(p.pos))<.001,vid+" rendered actor matches simulation dock")
					check(not p.node.walking and is_equal_approx(p.node.modulate.a,1),vid+" parked actor is planted and opaque")
					check(layout.fits(p.pos,p.dock.heading,false),vid+" actual parked cart clears fixed staff and furniture")
					if p.state=="collect" and not seen.has(p.window):seen[p.window]=true;parked+=1
					if p.state=="deposit" and not seen_deposit.has(p.window):seen_deposit[p.window]=true;deposits+=1
			if parked==floor_node._max_windows and deposits==floor_node._max_windows:break
		check(parked==floor_node._max_windows and deposits==floor_node._max_windows,vid+" every station reaches collection and unloading")
		if parked!=floor_node._max_windows or deposits!=floor_node._max_windows:
			for p in floor_node._porters:
				var hold: Dictionary=floor_node._cart_dispatch.holds.get(p,{})
				printerr("STALLED_PORTER ",vid," ",JSON.stringify({"index":floor_node._porters.find(p),"position":str(p.pos),"heading":str(p.heading),"target":str(p.target),"state":p.state,"window":p.window,"job":p.route_job.status if p.route_job!=null else "none","refuge":p.state=="yielding","remaining":p.route_steps.size()-p.route_cursor,"held_for":floor_node._porters.find(hold.get("winner",null)),"hold_arrived":hold.get("arrived",false),"stacks":str(floor_node._stacks)}))
			for request in floor_node._cart_dispatch.requests:
				printerr("STALLED_REQUEST ",vid," ",JSON.stringify({"porter":floor_node._porters.find(request.p),"phase":request.phase,"sequence":request.sequence,"ticket":request.get("schedule_ticket",-1),"tried":request.tried,"revision":floor_node._cart_dispatch.revision,"intent":request.intent.size(),"skip":request.skip.size()}))
		records.append({"venue":vid,"collections":parked,"deposits":deposits,"layout_failures":layout.failures})
		print("PORTER_STAGING ",vid," collections=",parked," deposits=",deposits," cart_overlaps=",venue_overlaps)
	if OS.get_cmdline_user_args().size()>0:
		var f:=FileAccess.open(OS.get_cmdline_user_args()[0],FileAccess.WRITE);f.store_string(JSON.stringify(records,"\t"));f.close()
	check(overlap_samples==0,"all live carts remain disjoint while completing bounded service")
	check(concurrent_samples>0,"independent carts move concurrently in the campaign")
	print("DISPATCH_SERVICE overlap_samples=",overlap_samples," checked_pairs=",checked_pairs," concurrent_samples=",concurrent_samples)
	print("Porter staging failures: ",failures);quit(1 if failures else 0)
