extends "res://tests/venue/test_nav_reachability.gd"
func _check_all_venues() -> void:
	_floor.retheme("infinite_museum")
	var plaza=_floor._plaza
	for i in 9200:
		if i==5200:plaza._spawn_clock=-10000
		plaza.advance(.05)
	for p in plaza.people:
		var next: Vector2=p.pos if p.path.is_empty() else (p.pos as Vector2).move_toward(p.path[0],.05)
		var report:={"state":p.state,"position":str(p.pos),"companion":str(p.companion_pos),"born":p.born,"blocked":p.blocked_time,"pending":str(p.pending_goal),"yield_resume":str(p.yield_resume),"path":str(p.path),"owner_clear":plaza._crowd_clear(p.pos,next,plaza._crowd_obstacles(p),true)}
		if is_instance_valid(p.get("companion")):
			var dog: Vector2=plaza._companion_target(p,next)
			report.dog_next=str(dog)
			report.dog_clear=plaza._crowd_clear(p.companion_pos,dog,plaza._crowd_obstacles(p,.17))
			report.leash_clear=plaza._crowd_clear(next,dog,plaza._crowd_obstacles(p,.025))
		print("SEATING_PLAZA_PROBE ",JSON.stringify(report))
	check(plaza.people.is_empty(),"Infinite public visitors finish")
