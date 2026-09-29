extends SceneTree
const Character:=preload("res://scenes/venue/floor/character.gd")
var failures:=0
var floor_node: Node
var VF: GDScript
func check(ok: bool,label: String) -> void:
	if not ok:failures+=1;printerr("FAIL: ",label)
func guest(at: Vector2,slot: int):
	var v=VF.Visitor.new();var c:=Character.new();c.set_look_slot(slot)
	floor_node._canvas.add_child(c);v.node=c;v.pos=at;floor_node._place(c,at)
	floor_node._visitors.append(v);return v
func _initialize() -> void:call_deferred("run")
func run() -> void:
	root.get_node("SaveSystem").set_process(false)
	var gs: Node=root.get_node("GameState");gs.reset_to_new_game();gs.ready_flag=true
	VF=load("res://scenes/venue/floor/venue_floor.gd")
	floor_node=load("res://scenes/venue/floor/venue_floor.tscn").instantiate()
	floor_node.set_size(Vector2(720,760));root.add_child(floor_node)
	for n in root.get_children():n.process_mode=Node.PROCESS_MODE_DISABLED
	floor_node.set_rates(root.get_node("Economy").venue_rates(gs.current_venue))
	var first=guest(floor_node._door_g,0);var arrived=guest(floor_node._queue_mouth(0),5)
	floor_node._assign_to_window(first,0);floor_node._assign_to_window(arrived,0)
	floor_node._enter_waiting_line(arrived)
	check(floor_node._queues[0][0]==arrived,"mouth arrival determines service order")
	arrived.state="queue";arrived.path=[]
	floor_node._serve_t[0]=100;floor_node._update_serve(.01)
	check(floor_node._stacks[0]==0,"a stale ready flag away from the till cannot receive service")
	arrived.pos=floor_node._slot_pos(0,0);arrived.target=arrived.pos
	floor_node._update_serve(.01)
	check(floor_node._stacks[0]==1 and arrived.state=="browse","stationary head visitor receives service once")
	first.pos=floor_node._queue_mouth(0);first.path=[];floor_node._enter_waiting_line(first)
	floor_node._serve_t[0]=100;floor_node._update_serve(.01)
	check(floor_node._stacks[0]==1 and first.state=="to_queue","advancing toward a vacant head is not service-ready")
	floor_node._spawn_t=10;floor_node._try_spawn()
	var outside=floor_node._visitors.back()
	check(outside.state=="arriving" and outside.window==-1,"off-screen arrival reserves no indoor queue position")
	var a=guest(floor_node._door_g,7);var b=guest(floor_node._door_g,8)
	check(floor_node._hold_in_lobby(a) and floor_node._hold_in_lobby(b),"lobby offers separate waiting positions")
	var original: Vector2=b.target
	floor_node._crowd.erase(a)
	var c=guest(floor_node._door_g,9)
	check(floor_node._hold_in_lobby(c) and c.target.distance_to(original)>=.64,"refilling a freed lobby slot cannot duplicate the last occupant")
	floor_node._windows_active=floor_node._max_windows
	var before: Array=[];var ids: Array=[]
	for y in range(floor_node._nav.region.position.y,floor_node._nav.region.end.y):
		for x in range(floor_node._nav.region.position.x,floor_node._nav.region.end.x):
			var id:=Vector2i(x,y);ids.append(id);before.append(floor_node._nav.is_point_solid(id))
	for w in floor_node._windows_active:
		check(not floor_node._queue_entry_path(floor_node._door_g,w).is_empty(),"tail entry remains reachable at counter "+str(w))
	var restored:=true
	for i in ids.size():restored=restored and floor_node._nav.is_point_solid(ids[i])==before[i]
	check(restored,"temporary waiting-lane avoidance restores every navigation cell")
	print("Queue protocol failures: ",failures)
	quit(1 if failures else 0)
