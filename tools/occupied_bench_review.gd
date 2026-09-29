extends "res://tools/walking_campaign_review.gd"
var VF: GDScript
func guest(floor_node: Node,at: Vector2,look: int):
	var v=VF.Visitor.new();v.node=Character.new();v.node.set_look_slot(look);v.pos=at;v.target=at
	floor_node._canvas.add_child(v.node);floor_node._visitors.append(v);floor_node._place(v.node,at);return v
func run() -> void:
	VF=load("res://scenes/venue/floor/venue_floor.gd")
	output=OS.get_cmdline_user_args()[0];DirAccess.make_dir_recursive_absolute(output)
	root.get_node("SaveSystem").set_process(false)
	var gs: Node=root.get_node("GameState");gs.reset_to_new_game();seed(817)
	vp=SubViewport.new();vp.size=Vector2i(720,1280);vp.render_target_update_mode=SubViewport.UPDATE_ALWAYS
	root.add_child(vp);vp.add_child(load("res://scenes/main.tscn").instantiate());await create_timer(2).timeout
	for i in 4:load("res://scripts/ui/popup_manager.gd").close_top()
	var floor_node: Node=find_floor(vp)
	for n in root.get_children():
		if n!=vp:n.process_mode=Node.PROCESS_MODE_DISABLED
	vp.get_child(0).process_mode=Node.PROCESS_MODE_DISABLED
	gs.current_venue=OS.get_environment("BENCH_REVIEW_VENUE") if OS.has_environment("BENCH_REVIEW_VENUE") else "empyrean_palace"
	for dept in ["ticket","archive","gallery","promotions"]:
		for track in ["staff","speed","value"]:gs.set_dept_level(gs.current_venue,dept,track,8)
	floor_node.retheme(gs.current_venue);floor_node.set_rates(root.get_node("Economy").venue_rates(gs.current_venue))
	for v in floor_node._visitors:v.node.queue_free()
	floor_node._visitors.clear();floor_node._crowd.clear()
	for queue in floor_node._queues:queue.clear()
	var pelagic: bool=gs.current_venue=="pelagic_crown"
	var seat_at:=Vector2(1.925,20.5) if pelagic else Vector2(8.375,20.3)
	var resting=guest(floor_node,seat_at,7)
	var arrival=guest(floor_node,Vector2(1.587288,19.5) if pelagic else Vector2(8.75,21.0),10)
	arrival.speed=.8728828 if pelagic else .9749043
	# Select the path first, then occupy the bench: this exercises live replanning.
	floor_node._assign_to_window(arrival,3 if pelagic else 2)
	resting.seat=floor_node._seats.find(seat_at);resting.state="rest";resting.departing_window=2
	var facing: Vector2=floor_node._seat_facings.get(seat_at,Vector2.DOWN)
	resting.pos=seat_at+facing*resting.node.seating_foot_distance();floor_node._place(resting.node,resting.pos)
	if not resting.node.begin_seating(facing,floor_node.Iso.to_screen(seat_at)-floor_node.Iso.to_screen(resting.pos)):printerr("FAIL seating fixture");quit(1);return
	resting.node.advance_seating(1,true);update_characters(vp,0)
	floor_node._user_zoom=2.5;floor_node._fit_canvas()
	var target: Vector2=floor_node._lifted(Vector2(2.5,20.4) if pelagic else Vector2(9,20))*floor_node._canvas.scale+floor_node._canvas.position
	floor_node._pan_camera(floor_node.size*.5-target)
	await capture(output+"/before.png")
	var samples: Array=[];var reached:=false
	for frame in 500:
		var previous: Vector2=arrival.pos
		reached=floor_node._move(arrival,.05);update_characters(vp,.05)
		var pair:=Geometry2D.get_closest_points_between_segments(previous,arrival.pos,seat_at,floor_node._seating_front(resting))
		samples.append({"time":(frame+1)*.05,"position":str(arrival.pos),"clearance":pair[0].distance_to(pair[1]),"seated":resting.node.seated,"detour_retry":arrival.seating_detour_retry})
		if frame<60 and (not OS.has_environment("BENCH_REVIEW_STILLS") or frame in [0,20,40,59]):await capture(output+"/frame-%03d.png"%frame)
		if reached:break
	await capture(output+"/arrival.png")
	var f:=FileAccess.open(output+"/movement.json",FileAccess.WRITE);f.store_string(JSON.stringify({"reached":reached,"samples":samples},"\t"));f.close()
	print("BENCH_NATIVE reached=",reached," seconds=",samples.size()*.05);quit(0 if reached else 1)
