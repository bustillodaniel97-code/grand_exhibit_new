extends "res://tests/venue/test_nav_reachability.gd"
const Props := preload("res://scenes/venue/floor/museum_props.gd")
func _check_all_venues() -> void:
 var gs: Node=root.get_node("GameState")
 gs.current_venue="infinite_museum";gs.set_dept_level("infinite_museum","ticket","staff",5)
 _floor.retheme("infinite_museum");_floor._refresh_cast()
 var plan=_floor._admissions;var banks: Dictionary={};var fronts: Dictionary={}
 check(plan.authored and plan.stations.size()==5,"five saved desks operate across the linked wings")
 for w in plan.stations.size():
  var station: Dictionary=plan.stations[w];banks[station.room]=true;fronts[station.front]=true
  for point in [station.center,station.porter,station.exit,plan.mouth(w),plan.slot(w,0),plan.slot(w,3)]:
   check(_floor.room_rect(station.room).has_point(point),"station %d keeps its work and waiting positions inside the correct reception" % w)
  check(_floor.tap_zone_at(_floor.Iso.to_screen(station.center))=="ticket","distributed active desks select admissions")
 check(banks.size()==3 and fronts.size()==3,"three separate reception locations have three facing directions")
 for flight in [[Vector2(2.5,7.5),Vector2(6.5,7.5),Rect2(2,6,5,3),"west_stair"],[Vector2(19.5,7.5),Vector2(15.5,7.5),Rect2(15,6,5,3),"east_stair"],[Vector2(7.5,3.5),Vector2(7.5,-.5),Rect2(6,-1,3,5),"atrium_stair"],[Vector2(15.5,1.5),Vector2(19.5,1.5),Rect2(15,0,5,3),"observatory_stair"]]:
  _local(flight[0],flight[1],flight[2],flight[3]+" connects to its own high and low landing")
 var circuit: Array[Vector2]=[Vector2(9,12),Vector2(13,12),Vector2(13,17),Vector2(9,17)]
 for i in circuit.size():_local(circuit[i],circuit[(i+1)%circuit.size()],_floor.room_rect("atrium"),"atrium circuit edge %d is local and usable" % i)
 var storeys: Dictionary={}
 for exhibit in _floor._theme.exhibits:
  storeys[_floor._theme.level_at(_floor.Exhibits.v2(exhibit.at))]=true
  for point in _floor.browse_spots()[exhibit.id]:
   check(_floor.room_rect(exhibit.viewing_room).has_point(point),str(exhibit.id)+" viewers stand in their own collection: "+str(point))
   check(not _floor._nav.is_point_solid(_floor._nav_id(point)),str(exhibit.id)+" raw viewing position clears walls and furniture: "+str(point))
  if exhibit.get("solid_footprint",false):_solid(exhibit,_floor.Exhibits.footprint(exhibit),str(exhibit.id))
 check(storeys.size()==4,"every storey has real collection destinations")
 for dept in ["gallery","promotions"]:
  for point in _floor._stations(dept):check(not _floor._nav.is_point_solid(_floor._nav_id(point)),dept+" employee stands clear of furniture")
 for spec in _floor._theme.props:
  if spec.get("solid_footprint",false):_solid(spec,_floor.Exhibits.v2(spec.size),str(spec.kind))
 for key in ["counter_body-east","counter_body-north","counter_body-west"]:
  check(Props._textures.has("res://art/environment/infinite_museum-%s.png" % key),key+" uses original museum art")
func _solid(spec: Dictionary,size: Vector2,label: String) -> void:
 var at: Vector2=_floor.Exhibits.v2(spec.at)
 for u in [.2,.5,.8]:
  for v in [.2,.5,.8]:check(_floor._nav.is_point_solid(_floor._nav_id(at+size*Vector2(u,v))),label+" reserves its complete footprint")
func _local(a: Vector2,b: Vector2,bounds: Rect2,label: String) -> void:
 var path: Array[Vector2i]=_floor._nav.get_id_path(_floor._nav_id(a),_floor._nav_id(b))
 var valid:=not path.is_empty()
 for id in path:valid=valid and bounds.has_point(Vector2(id)*.25)
 check(valid,label)
