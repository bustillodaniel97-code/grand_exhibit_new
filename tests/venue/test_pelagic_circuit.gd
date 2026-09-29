extends "res://tests/venue/test_nav_reachability.gd"
const Props := preload("res://scenes/venue/floor/museum_props.gd")
func _check_all_venues() -> void:
 var gs: Node=root.get_node("GameState")
 gs.current_venue="pelagic_crown";gs.set_dept_level("pelagic_crown","ticket","staff",5)
 _floor.retheme("pelagic_crown");_floor._refresh_cast()
 var arrival: Rect2=_floor.room_rect("lobby");var departure: Rect2=_floor.room_rect("departure")
 check(arrival.has_point(_floor._door_g) and departure.has_point(_floor._exit_door_g),"arrival and departure triggers belong to their different halls")
 check(_floor._exit_wall_g.is_equal_approx(departure.position+Vector2(3.8,7)),"exit facade belongs to the authored departure wall")
 check(not arrival.has_point(_floor._exit_door_g),"visitors do not return to the arrival lobby to leave")
 var exterior: Vector2=_floor._exit_wall_g+Vector2(0,.65)
 check(not _floor._plaza.route(exterior,_floor._plaza.spawn_points[0]).is_empty(),"departure hall connects to the actual public street route")
 var plan=_floor._admissions;var homes: Dictionary={};var fronts: Dictionary={}
 check(plan.authored and plan.stations.size()==5,"five saved desks operate in the new aquarium")
 for w in plan.stations.size():
  var station: Dictionary=plan.stations[w];homes[station.room]=true;fronts[station.front]=true
  for point in [station.center,station.porter,station.exit,plan.mouth(w),plan.slot(w,0),plan.slot(w,4)]:
   check(_floor.room_rect(station.room).has_point(point),"station %d keeps its work and queue positions in the correct reception" % w)
  check(_floor.tap_zone_at(_floor.Iso.to_screen(station.center))=="ticket","both active admission banks select the ticket department")
 check(homes.size()==2 and fronts.has(Vector2.RIGHT) and fronts.has(Vector2.UP),"west admission wall and lagoon reception face different directions")
 var pool:=Rect2(7.4,8,5.2,3.9)
 for u in [.1,.5,.9]:
  for v in [.1,.5,.9]:check(_floor._nav.is_point_solid(_floor._nav_id(pool.position+pool.size*Vector2(u,v))),"the complete enlarged lagoon is water, not walkable floor")
 var circuit: Array[Vector2]=[Vector2(7,7.5),Vector2(13.2,7.5),Vector2(13.2,12.8),Vector2(7,12.8)]
 for i in circuit.size():
  var path: Array[Vector2i]=_floor._nav.get_id_path(_floor._nav_id(circuit[i]),_floor._nav_id(circuit[(i+1)%circuit.size()]))
  var local:=not path.is_empty()
  for id in path:local=local and _floor.room_rect("gallery").has_point(Vector2(id)*.25)
  check(local,"lagoon edge %d is traversable inside the gallery without detouring through another wing" % i)
 for dept in ["gallery","promotions"]:
  for point in _floor._stations(dept):check(not _floor._nav.is_point_solid(_floor._nav_id(point)),dept+" employee has clear standing space: "+str(point))
 for exhibit in _floor._theme.exhibits:
  for point in _floor.browse_spots()[exhibit.id]:
   check(_floor.room_rect(exhibit.viewing_room).has_point(point),str(exhibit.id)+" audience stands in its own hall")
   check(not _floor._nav.is_point_solid(_floor._nav_id(point)),str(exhibit.id)+" viewing point clears water, walls and furniture: "+str(point))
 for spec in _floor._theme.props:
  if not spec.get("solid_footprint",false):continue
  var at: Vector2=_floor.Exhibits.v2(spec.at);var size: Vector2=_floor.Exhibits.v2(spec.size)
  for u in [.2,.5,.8]:
   for v in [.2,.5,.8]:check(_floor._nav.is_point_solid(_floor._nav_id(at+size*Vector2(u,v))),"research furniture reserves its full footprint")
 for key in ["counter_body-east","counter_body-north","crown_lagoon"]:
  check(Props._textures.has("res://art/environment/pelagic_crown-%s.png" % key),key+" uses original aquarium art")
 for i in 32:
  var texture: Texture2D=load("res://art/environment/pelagic_crown-crown_lagoon-motion-%02d.png" % i)
  check(texture.get_size()==Vector2(384,384),"lagoon frame %d uses the sharper authored resolution" % i)
