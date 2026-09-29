extends "res://tests/venue/test_nav_reachability.gd"
const Props := preload("res://scenes/venue/floor/museum_props.gd")
func _check_all_venues() -> void:
 var gs: Node=root.get_node("GameState")
 gs.current_venue="grand_river"
 gs.set_dept_level("grand_river","ticket","staff",3)
 _floor.retheme("grand_river")
 _floor._refresh_cast()
 var court: Rect2=_floor.room_rect("scholars_court")
 check(court.position.x>=_floor.room_rect("gallery").end.x and court.end.x<=_floor.room_rect("east_gallery").position.x,"the court occupies the center between two reading wings")
 check(_floor.room_rect("archive").end.y<=_floor.room_rect("service_cloister").position.y,"rare-book conservation sits behind the rear circulation spine")
 var plan=_floor._admissions
 check(plan.authored and plan.stations.size()==3 and _floor._staff_nodes.size()==3,"three saved desks operate in the corner reception")
 var fronts: Dictionary={}
 for w in plan.stations.size():
  var station: Dictionary=plan.stations[w]
  fronts[station.front]=true
  for point in [station.center,station.porter,plan.mouth(w),plan.slot(w,0),plan.slot(w,3)]:
   check(_floor.room_rect("ticket").has_point(point),"corner desk %d operational points remain in reception" % w)
  check(_floor.tap_zone_at(_floor.Iso.to_screen(station.center))=="ticket","corner desk opens Admissions")
  check(_floor._staff_nodes[w].position.is_equal_approx(_floor._lifted(plan.point(w,Vector2(0,-.7)))),"corner clerk stands behind its own desk")
 check(fronts.size()==2,"reception wraps its corner in two directions")
 for exhibit in _floor._theme.exhibits:
  var home: Rect2=_floor.room_rect(exhibit.viewing_room)
  for point in _floor.browse_spots()[exhibit.id]:
   check(home.has_point(point),str(exhibit.id)+" audience stands in its actual gallery")
   check(not _floor._nav.is_point_solid(_floor._nav_id(point)),str(exhibit.id)+" audience does not need to be moved out of furniture")
  check(_floor.tap_zone_at(_floor.Iso.to_screen(_floor.Exhibits.v2(exhibit.anchor)))=="gallery",str(exhibit.id)+" opens Gallery from its own wing")
 for asset in ["orrery","globe","folio","counter_body-west","counter_body-north","info_body"]:
  check(Props._textures.has("res://art/environment/grand_river-%s.png" % asset),asset+" loads the original museum art")

 var map_seats:=0
 for seat in _floor._seats:
  if not _floor.room_rect("map_study").has_point(seat):continue
  map_seats+=1
  var seat_id: Vector2i=_floor._nav_id(seat)
  check(not _floor._nav.is_point_solid(seat_id) and not _floor._nav.get_id_path(_floor._nav_id(_floor._door_g),seat_id).is_empty(),"map study reading seat is reachable from arrival")
 check(map_seats==4,"the map study provides four real reading seats")
 # Reachability alone must not send a reader through a wide desk's corner.
 for seat in _floor._seats:
  if not _floor.room_rect("map_study").has_point(seat):continue
  var path: Array=[_floor._door_g]
  path.append_array(_floor._nav_path(_floor._door_g,seat));path.append(seat)
  var collision: String=""
  for spec in _floor._theme.props:
   if spec.kind!="desk" or not _floor.room_rect("map_study").has_point(_floor.Exhibits.v2(spec.at)):continue
   var occupied:=Rect2(_floor.Exhibits.v2(spec.at),_floor.Exhibits.v2(spec.size)).grow(.08)
   for leg in range(1,path.size()):
    var start: Vector2=path[leg-1]
    var finish: Vector2=path[leg]
    var steps:=maxi(1,ceili(start.distance_to(finish)/.05))
    for n in range(steps+1):
     var point:=start.lerp(finish,float(n)/steps)
     if occupied.has_point(point):collision=str(point)+" crosses "+str(occupied)
  check(collision=="","reader route clears complete desk footprints: "+str(seat)+" "+collision)
