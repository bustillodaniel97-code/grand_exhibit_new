extends SceneTree
const Character:=preload("res://scenes/venue/floor/character.gd")
var failures:=0
var checks:=0
var floor_node: Node
var VF: GDScript
func check(ok: bool,label: String) -> void:
	checks+=1
	if not ok:failures+=1;printerr("FAIL: ",label)
func guest(at: Vector2):
	var v=VF.Visitor.new();v.node=Character.new();v.node.set_look_slot(0)
	floor_node._canvas.add_child(v.node);v.node.set_process(false)
	v.pos=at;v.target=at;v.speed=1.07;v.state="browse"
	floor_node._place(v.node,at);return v
func discard(v) -> void:v.node.free()
func _initialize() -> void:call_deferred("run")
func run() -> void:
	root.get_node("SaveSystem").set_process(false)
	var gs=root.get_node("GameState");gs.reset_to_new_game();gs.ready_flag=true
	VF=load("res://scenes/venue/floor/venue_floor.gd")
	floor_node=load("res://scenes/venue/floor/venue_floor.tscn").instantiate();root.add_child(floor_node)
	for n in root.get_children():n.process_mode=Node.PROCESS_MODE_DISABLED
	# Deliberately unobstructed exterior line isolates time conservation from
	# route choice. Every call still uses the production mover and safety hooks.
	for fps in [30,60,120]:
		for spacing in [.25,.013]:
			var start:=Vector2(-10,-10);var v=guest(start);v.target=start+Vector2(10,0)
			for i in range(1,int(10/spacing)):v.path.append(start+Vector2(i*spacing,0))
			for tick in fps*2:
				var before: Vector2=v.pos
				check(not floor_node._move(v,1.0/fps),"incomplete trajectory remains travelling")
				check(absf(v.pos.distance_to(before)-v.speed/fps)<.00003,"no lost time or idle pause at waypoint")
				check(v.node.walking,"walking remains active across waypoints")
			check(absf(v.pos.x-start.x-2*v.speed)<.0001,"two-second distance independent of FPS and waypoint spacing")
			print("CONTINUITY fps=",fps," spacing=",spacing," distance=",v.pos.x-start.x)
			discard(v)
	# An arbitrary partition must match one catch-up call around a corner,
	# while retaining ownership of the not-yet-reached waypoint.
	var partition_positions: Array=[]
	for pieces in [[.7],[.11,.017,.2,.003,.37]]:
		var walker=guest(Vector2(-10,-10));walker.speed=1
		walker.path=[Vector2(-9.75,-10),Vector2(-9.75,-9)];walker.target=Vector2(-8,-9)
		for seconds in pieces:floor_node._move(walker,seconds)
		check(walker.pos.distance_to(Vector2(-9.75,-9.55))<.00001,"arbitrary time partition conserves corner travel distance")
		check(walker.path==[Vector2(-9.75,-9)],"unreached waypoint retains ownership after partial travel")
		partition_positions.append(walker.pos);discard(walker)
	check(partition_positions[0].distance_to(partition_positions[1])<.00001,"one catch-up and uneven frames agree")
	# Exact terminal arrivals, duplicate points and corners consume only their
	# true travel time. No extra frame is required just to pop a reached point.
	var v=guest(Vector2(100,100));v.speed=1;v.target=Vector2(100.1,100.1)
	v.path=[v.pos,v.pos,Vector2(100.1,100),Vector2(100.1,100)]
	check(floor_node._move(v,.2),"terminal arrival on the frame that reaches the destination")
	check(v.pos.distance_to(v.target)<.00001 and not v.node.walking,"corner reaches exact target and stops")
	discard(v)
	v=guest(Vector2(100,100));v.target+=Vector2.RIGHT;v.cart_retry=2;v.seating_detour_retry=2
	for i in 100:v.path.append(v.pos)
	floor_node._move(v,.1)
	check(v.path.size()==36,"duplicate work is bounded without recursion")
	check(is_equal_approx(v.cart_retry,1.9) and is_equal_approx(v.seating_detour_retry,1.9),"retry timers decrement once per tick")
	discard(v)
	# Queue collision lies beyond the first waypoint; a large delta must not
	# skip the second segment's swept exclusion check.
	v=guest(Vector2(100,100));v.speed=3;v.window=0;v.target+=Vector2(2,0)
	v.path=[v.pos+Vector2(.25,0)]
	var other=guest(Vector2(101,100));other.window=0;floor_node._visitors.append(other)
	check(not floor_node._move(v,1),"queue blocker stops a multi-segment move")
	check(v.pos.x<=100.40001 and v.pos.x>100.24,"queue boundary checked after reached waypoint")
	check(not v.node.walking,"blocked queue mover stops its gait")
	floor_node._visitors.erase(other);discard(other);discard(v)
	# Final seat contact is the planted feet, not the hips; backing is retained.
	v=guest(Vector2(100,101));v.speed=1;v.state="rest";v.target=Vector2(100,100)
	floor_node._seat_facings[v.target]=Vector2.DOWN
	var feet: Vector2=v.target+Vector2.DOWN*v.node.seating_foot_distance()
	v.pos=feet+Vector2(0,.2);v.path=[v.pos+Vector2(0,-.05)]
	check(floor_node._move(v,.3),"seating approach completes through short waypoints")
	check(v.pos.distance_to(feet)<.00001 and v.node.walk_backwards,"seat backing stops at planted feet")
	discard(v)
	# A cart beyond the first point still blocks catch-up travel. The visitor
	# must not tunnel through the body even though the eventual goal is clear.
	v=guest(Vector2(100,100));v.speed=3;v.target+=Vector2(3,0)
	v.path=[v.pos+Vector2(.25,0)];v.cart_retry=2
	var cart_at:=Vector2(101.5,100)
	floor_node._crowd_traffic.cart_poses=[{"at":cart_at,"heading":Vector2.RIGHT,"height":floor_node._porter_layout._height_at(v.pos)}]
	check(not floor_node._move(v,1),"cart stops long multi-segment catch-up")
	check(v.pos.x>100.24 and v.pos.x<=101.00001,"cart guard reruns after first waypoint")
	check(not floor_node._crowd_traffic.overlaps_segment(v.pos,v.pos,floor_node._crowd_traffic.cart_poses[0]),"stopped guest clears cart body")
	floor_node._crowd_traffic.cart_poses=[];discard(v)
	# The traffic signal is checked again when an initial sidewalk waypoint
	# reaches the kerb during the same call.
	var city=floor_node._city
	check(not city._cars.is_empty(),"crossing fixture has actual road traffic")
	if not city._cars.is_empty():
		city._cars[0]["gx"]=city.CROSS_GX
		var far: Vector2=city.map_point(city.CROSS_FAR)
		var near: Vector2=city.map_point(city.CROSS_NEAR)
		v=guest(far+Vector2(.25,0));v.speed=3;v.path=[far];v.target=near
		check(not floor_node._move(v,1),"occupied zebra blocks after sidewalk waypoint")
		check(v.pos.distance_to(far)<.00001,"visitor waits exactly at kerb")
		discard(v)
	# Real rest/rise state transitions use the arrival returned by _move.
	# Claim an authored seat and approach only its final planted-foot edge.
	check(not floor_node._seats.is_empty(),"seat lifecycle uses real authored furniture")
	if not floor_node._seats.is_empty():
		v=guest(floor_node._seats[0]);v.target=floor_node._seats[0];v.seat=0;v.state="rest"
		floor_node._seat_taken[0]=true;v.node.prepare_seating()
		var front: Vector2=floor_node._seat_facings.get(v.target,Vector2.DOWN)
		var planted: Vector2=v.target+front*v.node.seating_foot_distance()
		v.pos=planted+front*.02;v.path=[]
		floor_node._visitors.append(v)
		floor_node._update_visitors(.05)
		check(v.node.seated and v.state=="rest" and v.pos.distance_to(planted)<.00001,"final approach begins seating on arrival frame")
		var initial_wait: float=v.wait
		for tick in 25:floor_node._update_visitors(.05)
		check(v.node.seated and v.wait<=initial_wait and floor_node._seat_taken.has(0),"seating does not restart or lose reservation")
		v.wait=0
		for tick in 40:
			floor_node._update_visitors(.05)
			if v.seat<0:break
		check(v.seat==-1 and not v.node.seated and not floor_node._seat_taken.has(0),"rise releases seat once and resumes exit")
		floor_node._visitors.erase(v);discard(v)
	# Missing indoor routes remain a hard stop even when reached after a
	# legal quarter-tile first segment in the same simulation tick.
	floor_node.retheme("infinite_museum")
	var target:=Vector2(15,6.5);var center: Vector2i=floor_node._nav_id(target)
	for y in range(center.y-1,center.y+2):
		for x in range(center.x-1,center.x+2):floor_node._nav.set_point_solid(Vector2i(x,y),true)
	v=guest(Vector2(13.75,6.5));v.target=target;v.speed=3;v.path=[Vector2(14,6.5)]
	check(not floor_node._move(v,1),"unreachable indoor target blocks after first segment")
	check(v.pos==Vector2(14,6.5),"no fallback direct walk through the blocked destination")
	discard(v)
	print("Visitor continuity checks: ",checks," failures: ",failures)
	quit(1 if failures else 0)
