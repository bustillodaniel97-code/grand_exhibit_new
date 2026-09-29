extends "res://tests/venue/test_nav_reachability.gd"
## The branch plan needs usable local doors and exhibit viewpoints, not only a
## connected room graph that can hide a blocked doorway behind a long detour.
const Props := preload("res://scenes/venue/floor/museum_props.gd")
func _check_all_venues() -> void:
 var gs: Node=root.get_node("GameState")
 gs.current_venue="celestial_conservatory"
 gs.set_dept_level("celestial_conservatory","ticket","staff",4)
 _floor.retheme("celestial_conservatory");_floor._refresh_cast()
 var plan=_floor._admissions
 check(plan.authored and plan.stations.size()==4 and _floor._staff_nodes.size()==4,"four saved desks operate in the two greenhouse reception branches")
 var homes: Dictionary={};var fronts: Dictionary={}
 for w in plan.stations.size():
  var station: Dictionary=plan.stations[w]
  homes[station.room]=true;fronts[station.front]=true
  var home: Rect2=_floor.room_rect(station.room)
  for point in [station.center,station.porter,station.exit,plan.mouth(w),plan.slot(w,0),plan.slot(w,4)]:
   check(home.has_point(point),"desk %d operational points stay in its own reception branch" % w)
  check(_floor.tap_zone_at(_floor.Iso.to_screen(station.center))=="ticket","both reception branches open the correct station department")
  check(_floor._staff_nodes[w].position.is_equal_approx(_floor._lifted(plan.point(w,Vector2(0,-.7)))),"each branch clerk stands behind the appropriate counter")
 check(homes.size()==2 and fronts.size()==2,"two separate reception branches have different queue directions")
 for dept in ["gallery","promotions"]:
  for point in _floor._stations(dept):
   check(not _floor._nav.is_point_solid(_floor._nav_id(point)),dept+" employee stands in clear working space: "+str(point))
 for door in [[Vector2(6.5,7),Vector2(7.5,7)],[Vector2(12.5,7),Vector2(13.5,7)],[Vector2(10,2.5),Vector2(10,3.5)],[Vector2(10,9.5),Vector2(10,10.5)],[Vector2(5.5,1.5),Vector2(6.5,1.5)],[Vector2(13.5,1.5),Vector2(14.5,1.5)]]:
  var path: Array[Vector2i]=_floor._nav.get_id_path(_floor._nav_id(door[0]),_floor._nav_id(door[1]))
  check(not path.is_empty() and path.size()<=9,"greenhouse/service doorway has a short local crossing: "+str(door))
 for exhibit in _floor._theme.exhibits:
  var viewing: Rect2=_floor.room_rect(exhibit.viewing_room)
  for point in _floor.browse_spots()[exhibit.id]:
   check(viewing.has_point(point),str(exhibit.id)+" audience remains in its own greenhouse")
   check(not _floor._nav.is_point_solid(_floor._nav_id(point)),str(exhibit.id)+" authored viewpoint is clear before any navigation snapping")
 for spec in _floor._theme.props:
  if not spec.get("solid_footprint",false):continue
  var at: Vector2=_floor.Exhibits.v2(spec.at)
  var size: Vector2=_floor.Exhibits.v2(spec.size)
  for u in [.2,.5,.8]:
   for v in [.2,.5,.8]:
    check(_floor._nav.is_point_solid(_floor._nav_id(at+size*Vector2(u,v))),"working furniture keeps its complete footprint solid")
 check(_floor._theme.levels()==[0],"greenhouse branches require no false stairs or floating rooms")
 for asset in ["counter_body-east","counter_body-north"]:
  check(Props._textures.has("res://art/environment/celestial_conservatory-%s.png" % asset),asset+" uses original counter geometry at the correct facing")
