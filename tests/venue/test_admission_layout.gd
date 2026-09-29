extends "res://tests/venue/test_nav_reachability.gd"
const Layout := preload("res://scenes/venue/floor/admission_layout.gd")
const Props := preload("res://scenes/venue/floor/museum_props.gd")

func _check_all_venues() -> void:
	# Independent coordinate expectations cover all four directions, including
	# fronts that point toward decreasing grid coordinates.
	var layout := Layout.new()
	var entries := [
		{"at":[2,2],"front":[0,1]}, {"at":[5,2],"front":[1,0]},
		{"at":[2,5],"front":[0,-1]}, {"at":[5,5],"front":[-1,0]}]
	layout.configure(Rect2(10,20,8,8),{"stations":entries,"slot_lead":1.0,"slot_gap":.5},4,3,.5)
	var expected := [Vector2(12,24),Vector2(17,22),Vector2(12,23),Vector2(13,25)]
	for w in 4:
		check(layout.slot(w,2).is_equal_approx(expected[w]),"queue extends in authored direction %d" % w)
		check(layout.queue_bounds(w).has_point(layout.slot(w,1)),"oriented queue paint encloses its waiting customers")
		var service: Vector2 = layout.stations[w].porter-layout.stations[w].center
		check(service.dot(layout.stations[w].front)<-1,"service remains behind directional desk %d" % w)

	var gs: Node = root.get_node("GameState")
	gs.current_venue = "whispering_pines"
	gs.dept_items("whispering_pines","ticket")
	gs.set_dept_level("whispering_pines","ticket","staff",5)
	gs.ready_flag = true
	_floor.retheme("whispering_pines")
	# Same-venue retheme is deliberately a no-op; apply the staffing change.
	_floor._refresh_cast()
	_floor._rebuild_props()
	var plan = _floor._admissions
	check(_floor._staff_nodes.size()==5,"all five staffed desks create their actual clerks")
	if _floor._staff_nodes.size()!=5:return
	check(plan.authored and plan.stations.size()==5,"Pines retains five saved station indices in an authored plan")
	var rooms := {}
	var fronts := {}
	for w in 5:
		var station: Dictionary = plan.stations[w]
		rooms[station.room] = true
		fronts[station.front] = true
		var room: Rect2 = _floor.room_rect(station.room)
		for point in [station.center,plan.slot(w,0),plan.slot(w,5),plan.mouth(w),station.porter]:
			check(room.has_point(point),"station %d and its operational positions occupy their actual room" % w)
		check(_floor.station_center(w).is_equal_approx(_floor._lifted(station.center)),"station %d controls follow the actual desk" % w)
		check(_floor.tap_zone_at(_floor.Iso.to_screen(station.center))=="ticket","station %d opens Admissions from its room" % w)
		check(_floor._staff_nodes[w].position.is_equal_approx(_floor._lifted(plan.point(w,Vector2(0,-.7)))),"station %d clerk stands behind its working face" % w)
		for side in [-plan.lane_offset,plan.lane_offset]:
			check(_floor._nav.is_point_solid(_floor._nav_id(plan.rope(w,side,2))),"station %d rotated rail is physically blocked" % w)
	check(rooms.size()==2 and fronts.size()==2,"Pines admissions actually span two rooms and two desk directions")
	check(Props._textures.has("res://art/environment/whispering_pines-counter_body-east.png"),"turned desks use original re-rendered counter art")
