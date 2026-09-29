extends SceneTree
const Router:=preload("res://scenes/venue/floor/porter_router.gd")
var failures:=0
func check(ok: bool,label: String) -> void:
	if not ok:failures+=1;printerr("FAIL: ",label)
func _initialize() -> void:call_deferred("run")
func run() -> void:
	root.get_node("SaveSystem").set_process(false)
	var gs: Node=root.get_node("GameState");gs.reset_to_new_game();gs.ready_flag=true
	var floor_node: Node=load("res://scenes/venue/floor/venue_floor.tscn").instantiate();floor_node.set_size(Vector2(720,760));root.add_child(floor_node)
	for n in root.get_children():n.process_mode=Node.PROCESS_MODE_DISABLED
	var router:=Router.new()
	var checked:=0;var turns:=0;var reversing:=0;var sweep_failures:=0
	# Other museums remain tracked by the campaign probe until their physical
	# service passages can accommodate the full trolley.
	for vid in ["whispering_pines","copper_kettle","grand_river","sunspire","cloudrest","aurora_world","celestial_conservatory","ironwood_citadel","pelagic_crown","chronos_spire","empyrean_palace","infinite_museum"]:
		if OS.has_environment("GRAND_EXHIBIT_ROUTER_ONLY") and vid!=OS.get_environment("GRAND_EXHIBIT_ROUTER_ONLY"):continue
		gs.current_venue=vid
		for dept in ["ticket","archive","gallery","promotions"]:
			for track in ["staff","speed","value"]:gs.set_dept_level(vid,dept,track,8)
		floor_node.retheme(vid);floor_node.set_rates(root.get_node("Economy").venue_rates(vid))
		check(floor_node._porter_layout.failures.is_empty(),vid+": parking allocation exists")
		if not floor_node._porter_layout.failures.is_empty():continue
		router.configure(floor_node._porter_layout)
		for bay in floor_node._porter_layout.drops:
			for counter in floor_node._porter_layout.counters:
				for reverse_trip in [false,true]:
					var start: Dictionary=counter if reverse_trip else bay
					var finish: Dictionary=bay if reverse_trip else counter
					var path:=router.route(start.at,start.heading,finish.at,finish.heading)
					check(not path.is_empty(),vid+": directional path exists both ways for every bay/counter pair")
					if path.is_empty():continue
					var at: Vector2=start.at;var heading: Vector2=start.heading
					for step in path:
						check(floor_node._porter_layout.fits(step.at,step.heading,false),"trolley pose clears actual static geometry")
						if step.turn:
							turns+=1;check(at==step.at,"steering does not teleport the body")
						else:
							check(is_equal_approx(at.distance_to(step.at),.25),"movement is one grid step")
							check(heading==step.heading,"movement retains facing")
							check(bool(step.reverse)==((step.at-at).dot(heading)<0),"backing direction matches the rig")
							if step.reverse:reversing+=1
						# Denser verification than the planner's midpoint/32-part turn samples.
						for j in range(1,128):
							var t:=j/128.0;var point:=at.lerp(step.at,t)
							var direction:=heading.rotated(heading.angle_to(step.heading)*t)
							if not floor_node._porter_layout.fits(point,direction,false):sweep_failures+=1
						at=step.at;heading=step.heading;checked+=1
					check(at==finish.at and heading==finish.heading,"path reaches exact dock and facing")
	check(sweep_failures==0,"dense sweep samples clear geometry; failures="+str(sweep_failures))
	check(turns>0 and reversing>0,"paths exercise turns and reversing")
	check(router.route(Vector2(-100,-100),Vector2.DOWN,Vector2.ZERO,Vector2.DOWN).is_empty(),"invalid origin never becomes a straight-line fallback")
	print("Porter router failures: ",failures," checked_steps=",checked," turns=",turns," reversing=",reversing," sweep_failures=",sweep_failures)
	quit(1 if failures else 0)
