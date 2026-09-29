extends SceneTree
const Router:=preload("res://scenes/venue/floor/porter_router.gd")
func _initialize() -> void:call_deferred("run")
func run() -> void:
	root.get_node("SaveSystem").set_process(false)
	var args:=OS.get_cmdline_user_args();var vid:=args[0]
	var gs: Node=root.get_node("GameState");gs.reset_to_new_game();gs.ready_flag=true;gs.current_venue=vid
	for dept in ["ticket","archive","gallery","promotions"]:
		for track in ["staff","speed","value"]:gs.set_dept_level(vid,dept,track,8)
	var floor_node: Node=load("res://scenes/venue/floor/venue_floor.tscn").instantiate();floor_node.set_size(Vector2(720,760));root.add_child(floor_node);floor_node.retheme(vid);floor_node.set_rates(root.get_node("Economy").venue_rates(vid))
	for n in root.get_children():n.process_mode=Node.PROCESS_MODE_DISABLED
	var layout: RefCounted=floor_node._porter_layout
	if not layout.failures.is_empty():printerr("FAIL allocation ",layout.failures);quit(1);return
	var router:=Router.new();router.configure(layout)
	var bay: Dictionary=layout.drops[0];var start:=router.key(bay.at,bay.heading)
	var reached: Dictionary={start:true};var queue: Array[Vector3i]=[start];var cursor:=0
	while cursor<queue.size():
		var a:=queue[cursor];cursor+=1
		var dir: Vector2=router.DIRECTIONS[a.z]
		for movement in [-1,1]:
			var b:=Vector3i(a.x+int(dir.x)*movement,a.y+int(dir.y)*movement,a.z)
			if not reached.has(b) and router.can_move(a,b):reached[b]=true;queue.append(b)
		for turn in [-1,1]:
			var b:=Vector3i(a.x,a.y,posmod(a.z+turn,4))
			if not reached.has(b) and router.can_turn(a,b):reached[b]=true;queue.append(b)
	var cells: Array=[];var nav: AStarGrid2D=floor_node._nav
	for y in range(nav.region.position.y,nav.region.end.y):
		for x in range(nav.region.position.x,nav.region.end.x):
			if nav.is_point_solid(Vector2i(x,y)):continue
			var mask:=0
			for h in 4:
				if reached.has(Vector3i(x,y,h)):mask|=1<<h
			cells.append([x*.25,y*.25,mask])
	var docks: Array=[]
	for c in layout.counters:docks.append({"at":[c.at.x,c.at.y],"heading":[c.heading.x,c.heading.y]})
	var staff: Array=[]
	for s in layout.fixed_staff:staff.append([s.x,s.y])
	var rects: Array=[]
	for r in layout.counter_rects:rects.append([r.position.x,r.position.y,r.size.x,r.size.y])
	var f:=FileAccess.open(args[1],FileAccess.WRITE);f.store_string(JSON.stringify({"venue":vid,"cells":cells,"docks":docks,"staff":staff,"counter_rects":rects,"reachable_poses":reached.size()}));f.close();print("CLEARANCE_MAP ",vid," poses=",reached.size());quit(0)
