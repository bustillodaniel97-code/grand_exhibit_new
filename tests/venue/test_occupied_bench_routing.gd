extends SceneTree
const Character:=preload("res://scenes/venue/floor/character.gd")
var failures:=0
var floor_node: Node
var VF: GDScript
func check(ok: bool,label: String) -> void:
	if not ok:failures+=1;printerr("FAIL: ",label)
func guest(at: Vector2,look: int):
	var v=VF.Visitor.new();v.node=Character.new();v.node.set_look_slot(look)
	floor_node._canvas.add_child(v.node);v.pos=at;v.target=at;floor_node._place(v.node,at)
	floor_node._visitors.append(v);return v
func _initialize() -> void:call_deferred("run")
func run() -> void:
	root.get_node("SaveSystem").set_process(false)
	var gs: Node=root.get_node("GameState");gs.reset_to_new_game();gs.ready_flag=true;gs.current_venue="empyrean_palace"
	for dept in ["ticket","archive","gallery","promotions"]:
		for track in ["staff","speed","value"]:gs.set_dept_level(gs.current_venue,dept,track,8)
	VF=load("res://scenes/venue/floor/venue_floor.gd")
	floor_node=load("res://scenes/venue/floor/venue_floor.tscn").instantiate();floor_node.set_size(Vector2(720,760));root.add_child(floor_node)
	floor_node.retheme(gs.current_venue);floor_node.set_rates(root.get_node("Economy").venue_rates(gs.current_venue))
	for n in root.get_children():n.process_mode=Node.PROCESS_MODE_DISABLED
	# Exact occupied-bench obstruction from the reproducible campaign trace.
	var seat_at:=Vector2(8.375,20.3);var seat_index: int=floor_node._seats.find(seat_at)
	check(seat_index>=0,"fixture uses a real authored bench seat")
	var ids: Array=[];var solids: Array=[]
	for y in range(floor_node._nav.region.position.y,floor_node._nav.region.end.y):
		for x in range(floor_node._nav.region.position.x,floor_node._nav.region.end.x):
			var id:=Vector2i(x,y);ids.append(id);solids.append(floor_node._nav.is_point_solid(id))
	for appears_later in [false,true]:
		seat_at=Vector2(9.125,20.3) if appears_later else Vector2(8.375,20.3)
		seat_index=floor_node._seats.find(seat_at)
		check(seat_index>=0,"both occupancy cases use real bench seats")
		for former_station in [2,4]:
			var resting=guest(seat_at,7);resting.state="browse";resting.departing_window=former_station
			# The second seat occupies the clear end of the empty bench's route.
			var arrival=guest(Vector2(8.75,21.0),0);arrival.speed=.9749043
			if not appears_later:
				resting.seat=seat_index;resting.state="rest";resting.node.seated=true
			floor_node._assign_to_window(arrival,2)
			check(not arrival.path.is_empty(),"admission has a real path")
			if appears_later:
				resting.seat=seat_index;resting.state="rise";resting.node.seated=true
			resting.pos=floor_node._seating_front(resting)
			var arrived:=false;var smallest:=INF;var elapsed:=0.0;var detoured:=false;var bench_contacts:=0
			for step in 1000:
				var before: Vector2=arrival.pos
				arrived=floor_node._move(arrival,.05);elapsed+=.05
				var pair:=Geometry2D.get_closest_points_between_segments(before,arrival.pos,seat_at,floor_node._seating_front(resting))
				smallest=minf(smallest,pair[0].distance_to(pair[1]))
				for spec in floor_node._theme.props:
					if str(spec.get("kind",""))!="bench":continue
					var body: Rect2=floor_node.Exhibits.solid_rect(spec).grow(.14)
					for sample in 5:
						if body.has_point(before.lerp(arrival.pos,sample/4.0)):bench_contacts+=1
				detoured=detoured or arrival.seating_detour_retry>0
				if arrived:break
			check(arrived and elapsed<25,"arrival reaches empty queue while the seated guest stays put")
			check(smallest>=.599,"entire movement segments clear the occupied seat/stand-up footprint")
			check(bench_contacts==0,"detour cannot cross the unoccupied end of any bench")
			check(not appears_later or detoured,"a newly occupied bench triggers a new route")
			check(arrival.pos.distance_to(floor_node._queue_mouth(2))<.001,"arrival reaches the actual queue mouth")
			print("BENCH_DETOUR later=",appears_later," former_station=",former_station," seconds=",elapsed," clearance=",smallest)
			floor_node._queues[2].erase(arrival);floor_node._visitors.erase(arrival);floor_node._visitors.erase(resting)
			arrival.node.queue_free();resting.node.queue_free()
	var restored:=true
	for i in ids.size():restored=restored and floor_node._nav.is_point_solid(ids[i])==solids[i]
	check(restored,"temporary seating reservations restore all shared navigation cells")
	# A second regression covers the physical passage behind Pelagic's lobby
	# bench. Its old position trapped a waiting guest between seat and wall.
	gs.current_venue="pelagic_crown"
	for dept in ["ticket","archive","gallery","promotions"]:
		for track in ["staff","speed","value"]:gs.set_dept_level(gs.current_venue,dept,track,8)
	floor_node.retheme(gs.current_venue);floor_node.set_rates(root.get_node("Economy").venue_rates(gs.current_venue))
	var pelagic_seat:=Vector2(1.925,20.5)
	var pelagic_index: int=floor_node._seats.find(pelagic_seat)
	check(pelagic_index>=0,"Pelagic uses its relocated physical bench")
	var resting=guest(pelagic_seat,7);resting.seat=pelagic_index;resting.state="rest";resting.node.seated=true;resting.departing_window=0
	resting.pos=floor_node._seating_front(resting)
	for window in [0,3]:
		var arrival=guest(Vector2(1.587288,19.5),0);arrival.speed=.8728828
		floor_node._assign_to_window(arrival,window)
		check(not arrival.path.is_empty(),"Pelagic passage offers an actual admission route")
		var arrived:=false;var smallest:=INF;var elapsed:=0.0
		for step in 700:
			var before: Vector2=arrival.pos
			arrived=floor_node._move(arrival,.05);elapsed+=.05
			var pair:=Geometry2D.get_closest_points_between_segments(before,arrival.pos,pelagic_seat,floor_node._seating_front(resting))
			smallest=minf(smallest,pair[0].distance_to(pair[1]))
			if arrived:break
		check(arrived and elapsed<25,"Pelagic admission walker passes the continuously occupied bench")
		check(smallest>=.599,"Pelagic movement clears the occupied seat")
		print("PELAGIC_BENCH window=",window," seconds=",elapsed," clearance=",smallest)
		floor_node._queues[window].erase(arrival);floor_node._visitors.erase(arrival);arrival.node.queue_free()
	floor_node._visitors.erase(resting);resting.node.queue_free()
	# Chronos formerly assigned lobby waiting positions to a bench's open
	# seating cells. Waiting people must keep those approach lanes available
	# even before a future occupant claims the seat.
	gs.current_venue="chronos_spire"
	for dept in ["ticket","archive","gallery","promotions"]:
		for track in ["staff","speed","value"]:gs.set_dept_level(gs.current_venue,dept,track,8)
	floor_node.retheme(gs.current_venue);floor_node.set_rates(root.get_node("Economy").venue_rates(gs.current_venue))
	var waiting: Array=[]
	for i in 6:
		var v=guest(floor_node._door_g,i)
		check(floor_node._hold_in_lobby(v),"Chronos offers usable lobby waiting space")
		waiting.append(v)
		for spec in floor_node._theme.props:
			if str(spec.get("kind",""))=="bench":check(not floor_node.Exhibits.solid_rect(spec).grow(.29).has_point(v.target),"lobby waiting point stays outside the bench body")
		for seat in floor_node._seats:
			var approach: Vector2=floor_node._seat_approaches.get(seat,seat)
			check(Geometry2D.get_closest_point_to_segment(v.target,seat,approach).distance_to(v.target)>=.639,"waiting guests leave the seating approach clear")
	for i in waiting.size():
		for j in range(i+1,waiting.size()):check(waiting[i].target.distance_to(waiting[j].target)>=.639,"relocated waiting positions remain separate")
	var all_arrived:=true
	for v in waiting:
		var arrived:=false
		for step in 600:
			if floor_node._move(v,.05):arrived=true;break
		all_arrived=all_arrived and arrived
	check(all_arrived,"lobby guests actually walk to their replacement standing positions")
	print("Occupied bench routing failures: ",failures);quit(1 if failures else 0)
