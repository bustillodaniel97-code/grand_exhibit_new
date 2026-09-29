extends "res://tests/venue/test_nav_reachability.gd"
const Props := preload("res://scenes/venue/floor/museum_props.gd")
func _check_all_venues() -> void:
 var gs: Node=root.get_node("GameState")
 gs.current_venue="chronos_spire";gs.set_dept_level("chronos_spire","ticket","staff",5)
 _floor.retheme("chronos_spire");_floor._refresh_cast()
 var plan=_floor._admissions;var fronts: Dictionary={}
 check(plan.authored and plan.stations.size()==5,"five saved desks operate in the tower reception")
 for w in plan.stations.size():
  var station: Dictionary=plan.stations[w];fronts[station.front]=true
  for point in [station.center,station.porter,station.exit,plan.mouth(w),plan.slot(w,0),plan.slot(w,4)]:
   check(_floor.room_rect(station.room).has_point(point),"station %d keeps its work and queue positions in reception" % w)
  check(_floor.tap_zone_at(_floor.Iso.to_screen(station.center))=="ticket","active island counter selects admissions")
 check(fronts.size()==4,"admission island serves all four directions")
 # A direct entry into reception must not require visiting the staff club first.
 _local_route(Vector2(13,23.5),Vector2(13,21.25),Rect2(11,20,4,5),"arrival to admission island")
 for flight in [[Vector2(7.5,10),Vector2(11.5,10),Rect2(7,8,5,4),"winding_stair"],[Vector2(11.5,4.5),Vector2(7.5,4.5),Rect2(7,3,5,3),"escapement_stair"],[Vector2(7.5,1.5),Vector2(11.5,1.5),Rect2(7,0,5,3),"bell_stair"]]:
  _local_route(flight[0],flight[1],flight[2],flight[3])
 var floors: Dictionary={}
 for exhibit in _floor._theme.exhibits:
  floors[_floor._theme.level_at(_floor.Exhibits.v2(exhibit.at))]=true
  for point in _floor.browse_spots()[exhibit.id]:
   check(_floor.room_rect(exhibit.viewing_room).has_point(point),str(exhibit.id)+" audience stands in its own hall: "+str(point))
   check(not _floor._nav.is_point_solid(_floor._nav_id(point)),str(exhibit.id)+" viewing point clears walls and furniture: "+str(point))
  if exhibit.get("solid_footprint",false):_solid(exhibit,_floor.Exhibits.footprint(exhibit),str(exhibit.id))
 check(floors.size()==4,"all four storeys have collection destinations")
 for dept in ["gallery","promotions"]:
  for point in _floor._stations(dept):check(not _floor._nav.is_point_solid(_floor._nav_id(point)),dept+" employee has clear standing space: "+str(point))
 for spec in _floor._theme.props:
  if spec.get("solid_footprint",false):_solid(spec,_floor.Exhibits.v2(spec.size),str(spec.kind))
 for key in ["counter_body-east","counter_body-north","counter_body-west"]:
  check(Props._textures.has("res://art/environment/chronos_spire-%s.png" % key),key+" uses original clockwork art")
func _solid(spec: Dictionary,size: Vector2,label: String) -> void:
 var at: Vector2=_floor.Exhibits.v2(spec.at)
 for u in [.2,.5,.8]:
  for v in [.2,.5,.8]:check(_floor._nav.is_point_solid(_floor._nav_id(at+size*Vector2(u,v))),label+" reserves its physical footprint")
func _local_route(a: Vector2,b: Vector2,bounds: Rect2,label: String) -> void:
 var path: Array[Vector2i]=_floor._nav.get_id_path(_floor._nav_id(a),_floor._nav_id(b))
 var valid:=not path.is_empty()
 for id in path:valid=valid and bounds.has_point(Vector2(id)*.25)
 check(valid,label+" connects locally with clear landings")
