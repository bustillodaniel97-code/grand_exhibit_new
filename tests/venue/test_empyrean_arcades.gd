extends "res://tests/venue/test_nav_reachability.gd"
const Props := preload("res://scenes/venue/floor/museum_props.gd")
func _check_all_venues() -> void:
 var gs: Node=root.get_node("GameState")
 gs.current_venue="empyrean_palace";gs.set_dept_level("empyrean_palace","ticket","staff",5)
 _floor.retheme("empyrean_palace");_floor._refresh_cast()
 var plan=_floor._admissions;var banks: Dictionary={};var fronts: Dictionary={}
 check(plan.authored and plan.stations.size()==5,"five saved desks operate in the palace arcades")
 for w in plan.stations.size():
  var station: Dictionary=plan.stations[w];banks[station.room]=true;fronts[station.front]=true
  for point in [station.center,station.porter,station.exit,plan.mouth(w),plan.slot(w,0),plan.slot(w,5)]:
   check(_floor.room_rect(station.room).has_point(point),"station %d keeps work and six queue slots inside its arcade" % w)
  check(_floor.tap_zone_at(_floor.Iso.to_screen(station.center))=="ticket","both admission arcades select the ticket department")
 check(banks.size()==2 and fronts.has(Vector2.LEFT) and fronts.has(Vector2.RIGHT),"opposing admission banks face across the garden")
 _local(Vector2(18.5,10.5),Vector2(20.5,6.5),Rect2(18,6,4,5),"salon stair connects to actual upper and lower landings")
 var circuit: Array[Vector2]=[Vector2(9,12),Vector2(13,12),Vector2(13,16),Vector2(9,16)]
 for i in circuit.size():_local(circuit[i],circuit[(i+1)%circuit.size()],_floor.room_rect("gallery"),"garden circuit edge %d stays inside the court" % i)
 for exhibit in _floor._theme.exhibits:
  for point in _floor.browse_spots()[exhibit.id]:
   check(_floor.room_rect(exhibit.viewing_room).has_point(point),str(exhibit.id)+" audience stays in its collection: "+str(point))
   check(not _floor._nav.is_point_solid(_floor._nav_id(point)),str(exhibit.id)+" viewing position clears walls and furniture: "+str(point))
  if exhibit.get("solid_footprint",false):_solid(exhibit,_floor.Exhibits.footprint(exhibit),str(exhibit.id))
 for dept in ["gallery","promotions"]:
  for point in _floor._stations(dept):check(not _floor._nav.is_point_solid(_floor._nav_id(point)),dept+" staff have clear standing space")
 for spec in _floor._theme.props:
  if spec.get("solid_footprint",false):_solid(spec,_floor.Exhibits.v2(spec.size),str(spec.kind))
 for key in ["counter_body-east","counter_body-west"]:
  check(Props._textures.has("res://art/environment/empyrean_palace-%s.png" % key),key+" uses original palace art")
func _solid(spec: Dictionary,size: Vector2,label: String) -> void:
 var at: Vector2=_floor.Exhibits.v2(spec.at)
 for u in [.2,.5,.8]:
  for v in [.2,.5,.8]:check(_floor._nav.is_point_solid(_floor._nav_id(at+size*Vector2(u,v))),label+" reserves its complete footprint")
func _local(a: Vector2,b: Vector2,bounds: Rect2,label: String) -> void:
 var path: Array[Vector2i]=_floor._nav.get_id_path(_floor._nav_id(a),_floor._nav_id(b))
 var valid:=not path.is_empty()
 for id in path:valid=valid and bounds.has_point(Vector2(id)*.25)
 check(valid,label)
