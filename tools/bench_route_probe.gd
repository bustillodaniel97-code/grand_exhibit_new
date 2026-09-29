extends "res://tests/venue/test_occupied_bench_routing.gd"
func run() -> void:
	root.get_node("SaveSystem").set_process(false)
	var gs: Node=root.get_node("GameState");gs.reset_to_new_game();gs.ready_flag=true;gs.current_venue="pelagic_crown"
	for dept in ["ticket","archive","gallery","promotions"]:
		for track in ["staff","speed","value"]:gs.set_dept_level(gs.current_venue,dept,track,8)
	VF=load("res://scenes/venue/floor/venue_floor.gd");floor_node=load("res://scenes/venue/floor/venue_floor.tscn").instantiate();floor_node.set_size(Vector2(720,760));root.add_child(floor_node)
	floor_node.retheme(gs.current_venue);floor_node.set_rates(root.get_node("Economy").venue_rates(gs.current_venue))
	for n in root.get_children():n.process_mode=Node.PROCESS_MODE_DISABLED
	var seat_at:=Vector2(1.925,20.5);var resting=guest(seat_at,7);resting.state="rest";resting.seat=floor_node._seats.find(seat_at);resting.node.seated=true;resting.departing_window=0;resting.pos=floor_node._seating_front(resting)
	var arrival=guest(Vector2(1.587288,19.5),0);arrival.speed=.8728828
	floor_node._assign_to_window(arrival,3);print("SEAT ",resting.seat," PATH ",arrival.path)
	for y in range(74,89):
		var line:=""
		for x in range(0,21):line+="#" if floor_node._nav.is_point_solid(Vector2i(x,y)) else "."
		print(y*.25," ",line)
	for i in 20:floor_node._move(arrival,.05)
	print("AFTER ",arrival.pos," PATH ",arrival.path);quit(0)
