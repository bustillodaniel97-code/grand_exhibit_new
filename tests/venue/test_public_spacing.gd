extends "res://tests/venue/test_public_plaza.gd"
var overlaps := 0
var stale_visitors := 0
var samples := 0
var reports: Dictionary = {}
var last_progress: Dictionary = {}

func check_population(plaza,vid: String) -> void:
	super.check_population(plaza,vid)
	if not reports.has(vid):reports[vid]={"pairs":0,"overlaps":0,"stale":0,"max_visit_seconds":0.0,"max_wait_seconds":0.0}
	for p in plaza.people:
		var age: float=plaza.elapsed-p.born
		reports[vid].max_visit_seconds=maxf(reports[vid].max_visit_seconds,age)
		var id: int=p.node.get_instance_id()
		if not last_progress.has(id):last_progress[id]={"pos":p.pos,"time":plaza.elapsed}
		if p.pos.distance_to(last_progress[id].pos)>.05 or (p.state=="activity" and not (p.pending_goal as Vector2).is_finite()):
			last_progress[id]={"pos":p.pos,"time":plaza.elapsed}
		reports[vid].max_wait_seconds=maxf(reports[vid].max_wait_seconds,plaza.elapsed-float(last_progress[id].time))
		if plaza.elapsed-float(last_progress[id].time)>60:
			reports[vid].stale+=1
			if stale_visitors<4:check(false,"outdoor visitor cannot make progress for over 60 seconds: "+vid+" "+str(p.state)+" "+str(p.pos))
			stale_visitors+=1
	for i in plaza.people.size():
		var a: Dictionary=plaza.people[i]
		for j in range(i+1,plaza.people.size()):
			var b: Dictionary=plaza.people[j]
			samples+=1;reports[vid].pairs+=1
			var contact: bool=a.pos.distance_to(b.pos)<plaza.body_radius(a)+plaza.body_radius(b)+.055
			for pair in [[a,b],[b,a]]:
				if is_instance_valid(pair[0].get("companion")):
					contact = contact or pair[0].companion_pos.distance_to(pair[1].pos)<plaza.body_radius(pair[1])+.225
					contact = contact or plaza._segment_gap(pair[0].pos,pair[0].companion_pos,pair[1].pos,pair[1].pos)<plaza.body_radius(pair[1])+.02
			if contact:
				reports[vid].overlaps+=1
				if overlaps<4:check(false,"outdoor bodies or leash overlap: "+vid+" "+str(a.pos)+" / "+str(b.pos))
				overlaps+=1

func _after_public_venue(plaza,vid: String) -> void:
	plaza._spawn_clock=-10000.0
	var drain_start: float=plaza.elapsed
	for step in 4000:
		if plaza.people.is_empty():break
		plaza.advance(.05);check_population(plaza,vid)
	check(plaza.people.is_empty(),vid+" every remaining visitor departs after new arrivals stop")
	var remaining: Array=[]
	for p in plaza.people:
		remaining.append({"state":p.state,"position":str(p.pos),"goal":str(p.path.back()) if not p.path.is_empty() else str(p.pending_goal),"kind":plaza.activities[p.activity_index].kind,"age":plaza.elapsed-p.born})
	reports[vid]["remaining"]=remaining
	reports[vid]["drain_seconds"]=plaza.elapsed-drain_start
	reports[vid]["completed"]=plaza.completed.duplicate()
	reports[vid]["yield_maneuvers"]=plaza.crowd_yields
	reports[vid]["detours"]=plaza.crowd_detours
	reports[vid]["waiting_steps"]=plaza.crowd_wait_steps
	var changed_cells:=0
	for y in range(plaza.graph.region.position.y,plaza.graph.region.end.y):
		for x in range(plaza.graph.region.position.x,plaza.graph.region.end.x):
			var id:=Vector2i(x,y);var at: Vector2=Vector2(id)*plaza.STEP
			if plaza.graph.is_point_solid(id)==plaza._line_clear(at,at,.02):changed_cells+=1
	check(changed_cells==0,vid+" temporary crowd reservations restore every original navigation cell")
	reports[vid]["changed_navigation_cells"]=changed_cells

func _check_all_venues() -> void:
	var plaza = _floor._plaza
	check(not plaza._crowd_clear(Vector2.ZERO,Vector2(2,0),[{"a":Vector2(1,0),"b":Vector2(1,0),"radius":.25}]),"swept movement cannot tunnel through a person between clear endpoints")
	check(is_zero_approx(plaza._segment_gap(Vector2(0,0),Vector2(1,1),Vector2(0,1),Vector2(1,0))),"crossing a thin leash is detected between its endpoints")
	super._check_all_venues()
	print("PUBLIC_SPACING ",JSON.stringify(reports))
	var out:=OS.get_environment("PUBLIC_SPACING_REPORT")
	if not out.is_empty():
		var file:=FileAccess.open(out,FileAccess.WRITE);file.store_string(JSON.stringify(reports,"\t"));file.close()
	check(samples>10000,"spacing audit samples a sustained population across all venues")
	check(overlaps==0,"public bodies and leashes stay separated")
	check(stale_visitors==0,"no public visitor remains stuck for the audit")
