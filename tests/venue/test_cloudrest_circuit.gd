extends "res://tests/venue/test_nav_reachability.gd"
const Props := preload("res://scenes/venue/floor/museum_props.gd")
func _check_all_venues() -> void:
 var gs: Node=root.get_node("GameState")
 gs.current_venue="cloudrest"
 gs.set_dept_level("cloudrest","ticket","staff",4)
 _floor.retheme("cloudrest")
 _floor._refresh_cast()
 var plan=_floor._admissions
 check(plan.authored and plan.stations.size()==4 and _floor._staff_nodes.size()==4,"all four saved reception desks operate")
 var fronts: Dictionary={}
 for w in plan.stations.size():
  var station: Dictionary=plan.stations[w]
  fronts[station.front]=true
  for point in [station.center,station.porter,station.exit,plan.mouth(w),plan.slot(w,0),plan.slot(w,3)]:
   check(_floor.room_rect("ticket").has_point(point),"desk %d operational points stay in west reception" % w)
  check(_floor.tap_zone_at(_floor.Iso.to_screen(station.center))=="ticket","each active desk opens Admissions")
 check(fronts.has(Vector2.RIGHT) and fronts.has(Vector2.UP),"reception turns a corner instead of repeating one counter row")
 var archive: Rect2=_floor.room_rect("archive")
 var arrival: Rect2=_floor.room_rect("lobby")
 check(archive.position.x>arrival.end.x and _floor._theme.level_at(archive.get_center())==0,"conservation occupies the opposite ground wing")
 var span: Dictionary=_floor._theme.by_id.span
 check(span.support_style=="bridge" and span.level==1,"the sky bridge has actual structural supports")
 var span_rect: Rect2=span.rect
 check(is_equal_approx(span_rect.position.x,_floor.room_rect("gallery").end.x) and is_equal_approx(span_rect.end.x,_floor.room_rect("east_gallery").position.x),"the bridge joins both collection wings")
 # Each side must genuinely reach its own upper wing without detouring across
 # the opposite flight. Overall room reachability alone misses a sealed landing.
 for pair in [["west_approach",Vector2(1.2,5.4),true],["east_landing",Vector2(15.5,8.2),false]]:
  var origin: Vector2=_floor.room_rect(pair[0]).get_center()
  var route: Array=_floor._nav_path(origin,pair[1])
  check(not route.is_empty(),str(pair[0])+" reaches its collection wing")
  var local_route:=true
  for point in route:
   local_route=local_route and (point.x<7.25 if pair[2] else point.x>13.5)
  check(local_route,str(pair[0])+" uses its own climb and landing")
 for exhibit in _floor._theme.exhibits:
  if not exhibit.has("views"):continue
  var home: Rect2=_floor.room_rect(exhibit.viewing_room)
  for point in _floor.browse_spots()[exhibit.id]:
   check(home.has_point(point),str(exhibit.id)+" viewers stand in their collection wing")
   check(not _floor._nav.is_point_solid(_floor._nav_id(point)),str(exhibit.id)+" raw views clear the furniture")
 for asset in ["counter_body-east","counter_body-north","shelf-220","cairn"]:
  check(Props._textures.has("res://art/environment/cloudrest-%s.png" % asset),asset+" uses original Cloudrest art")
