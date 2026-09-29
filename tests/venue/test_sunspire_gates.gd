extends "res://tests/venue/test_nav_reachability.gd"
const Props := preload("res://scenes/venue/floor/museum_props.gd")
func _check_all_venues() -> void:
 var gs: Node=root.get_node("GameState")
 gs.current_venue="sunspire"
 gs.set_dept_level("sunspire","ticket","staff",5)
 _floor.retheme("sunspire")
 _floor._refresh_cast()
 var plan=_floor._admissions
 check(plan.authored and plan.stations.size()==5 and _floor._staff_nodes.size()==5,"all five saved desks work across the paired gates")
 var rooms: Dictionary={}
 var fronts: Dictionary={}
 for w in plan.stations.size():
  var station: Dictionary=plan.stations[w]
  rooms[station.room]=true;fronts[station.front]=true
  var home: Rect2=_floor.room_rect(station.room)
  for point in [station.center,station.porter,station.exit,plan.mouth(w),plan.slot(w,0),plan.slot(w,3)]:
   check(home.has_point(point),"gate %d operational points stay in its own bank" % w)
  check(_floor.tap_zone_at(_floor.Iso.to_screen(station.center))=="ticket","each active gate opens Admissions")
  check(_floor._staff_nodes[w].position.is_equal_approx(_floor._lifted(plan.point(w,Vector2(0,-.7)))),"gate clerk stands behind its own desk")
 check(rooms.size()==2 and fronts.has(Vector2.LEFT) and fronts.has(Vector2.RIGHT),"the two gates face across an open processional passage")
 var hall: Rect2=_floor.room_rect("axial_hall")
 for y in range(45,68):
  var point:=Vector2(hall.get_center().x,y*.25)
  check(not _floor._nav.is_point_solid(_floor._nav_id(point)),"the axial passage remains unobstructed")
 var stair: Rect2=_floor.room_rect("sun_stair")
 var upper: Rect2=_floor.room_rect("sun_landing")
 var lower: Rect2=_floor.room_rect("lower_landing")
 check(stair.position.x>=_floor.room_rect("processional").end.x,"the ascent is beside the court")
 check(is_equal_approx(upper.end.y,stair.position.y) and is_equal_approx(lower.position.y,stair.end.y),"the flight joins actual top and bottom landings")
 check(_floor._theme.level_at(upper.get_center())==1 and _floor._theme.level_at(lower.get_center())==0,"landings meet the correct storeys")
 for exhibit in _floor._theme.exhibits:
  if not exhibit.has("views"):continue
  var home: Rect2=_floor.room_rect(exhibit.viewing_room)
  for point in _floor.browse_spots()[exhibit.id]:
   check(home.has_point(point),str(exhibit.id)+" audience stands in its own court or collection room")
   check(not _floor._nav.is_point_solid(_floor._nav_id(point)),str(exhibit.id)+" view does not require escaping an obstacle")
 for asset in ["counter_body-east","counter_body-west","desk-130","lion"]:
  check(Props._textures.has("res://art/environment/sunspire-%s.png" % asset),asset+" uses the original Sunspire furnishing")
