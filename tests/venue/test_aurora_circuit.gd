extends "res://tests/venue/test_nav_reachability.gd"
const Props := preload("res://scenes/venue/floor/museum_props.gd")
func _check_all_venues() -> void:
 var gs: Node=root.get_node("GameState")
 gs.current_venue="aurora_world"
 gs.set_dept_level("aurora_world","ticket","staff",4)
 _floor.retheme("aurora_world")
 _floor._refresh_cast()
 var plan=_floor._admissions
 check(plan.authored and plan.stations.size()==4 and _floor._staff_nodes.size()==4,"four saved desks operate around the reception island")
 var fronts: Dictionary={}
 var home: Rect2=_floor.room_rect("ticket")
 for w in plan.stations.size():
  var station: Dictionary=plan.stations[w]
  fronts[station.front]=true
  for point in [station.center,station.porter,station.exit,plan.mouth(w),plan.slot(w,0),plan.slot(w,3)]:
   check(home.has_point(point),"island desk %d operational points remain in reception" % w)
  var outward: Vector2=station.center-home.get_center()
  check(outward.dot(station.front)>0 and outward.dot(station.front)>=absf(outward.dot(station.right)),"each admission face points outward on its own side of the island")
  check(_floor.tap_zone_at(_floor.Iso.to_screen(station.center))=="ticket","each active island face opens Admissions")
  check(_floor._staff_nodes[w].position.is_equal_approx(_floor._lifted(plan.point(w,Vector2(0,-.7)))),"island clerk works behind its own counter")
 check(fronts.size()==4,"admissions use all four sides of the island")
 check(_floor.room_rect("lobby").position.x>=_floor.room_rect("gallery").end.x,"arrival occupies the lateral wing")
 check(_floor.room_rect("archive").end.x<=_floor.room_rect("ticket").position.x,"conservation is across the building from reception")
 check(_floor._theme.level_at(_floor.room_rect("gallery").get_center())==0,"the rotunda belongs to the ground collection circuit")
 check(_floor._theme.level_at(_floor.room_rect("observatory").get_center())==1 and _floor._theme.level_at(_floor.room_rect("northwing").get_center())==1,"both observatories occupy a raised side wing")
 var flight: Rect2=_floor.room_rect("south_stair")
 check(flight.position.x>=home.end.x and is_equal_approx(flight.position.y,_floor.room_rect("observatory").end.y) and is_equal_approx(flight.end.y,_floor.room_rect("east_concourse").position.y),"side flight joins the actual observatory and lower concourse")
 for exhibit in _floor._theme.exhibits:
  if not exhibit.has("views"):continue
  var viewing: Rect2=_floor.room_rect(exhibit.viewing_room)
  for point in _floor.browse_spots()[exhibit.id]:
   check(viewing.has_point(point),str(exhibit.id)+" audience stays in its own collection space")
   check(not _floor._nav.is_point_solid(_floor._nav_id(point)),str(exhibit.id)+" viewers do not need to escape an obstacle")
 for asset in ["counter_body-east","counter_body-west","counter_body-north"]:
  check(Props._textures.has("res://art/environment/aurora_world-%s.png" % asset),asset+" uses original rotated counter geometry")
