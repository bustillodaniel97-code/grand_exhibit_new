extends "res://tests/venue/test_nav_reachability.gd"
## Prove the cloister is a usable ground circuit even with the inner keep and
## armory unavailable. A generic connected-room graph cannot establish that.
const Props := preload("res://scenes/venue/floor/museum_props.gd")
func _check_all_venues() -> void:
 var gs: Node=root.get_node("GameState")
 gs.current_venue="ironwood_citadel";gs.set_dept_level("ironwood_citadel","ticket","staff",5)
 _floor.retheme("ironwood_citadel");_floor._refresh_cast()
 var plan=_floor._admissions
 check(plan.authored and plan.stations.size()==5 and _floor._staff_nodes.size()==5,"five saved desks operate in the fortress gatehouse")
 var homes: Dictionary={};var fronts: Dictionary={}
 for w in plan.stations.size():
  var station: Dictionary=plan.stations[w];homes[station.room]=true;fronts[station.front]=true
  for point in [station.center,station.porter,station.exit,plan.mouth(w),plan.slot(w,0),plan.slot(w,4)]:
   check(_floor.room_rect(station.room).has_point(point),"gatehouse desk %d keeps its operational points in its own hall" % w)
  check(_floor.tap_zone_at(_floor.Iso.to_screen(station.center))=="ticket","both gatehouse faces open Admissions")
 check(homes.size()==2 and fronts.has(Vector2.DOWN) and fronts.has(Vector2.LEFT),"front and east gatehouses face different approaches")
 var closed: Array[Vector2i]=[]
 for rid in ["archive","gallery","keep_stair"]:
  var rect: Rect2=_floor.room_rect(rid)
  for x in range(int(rect.position.x*4),int(rect.end.x*4)+1):
   for y in range(int(rect.position.y*4),int(rect.end.y*4)+1):
    var id:=Vector2i(x,y)
    if not _floor._nav.is_point_solid(id):closed.append(id);_floor._nav.set_point_solid(id,true)
 var circuit: Array[Vector2]=[Vector2(4.5,7.5),Vector2(10,-1.5),Vector2(17.5,8.5),Vector2(12,11.5)]
 for i in circuit.size():
  var path: Array[Vector2i]=_floor._nav.get_id_path(_floor._nav_id(circuit[i]),_floor._nav_id(circuit[(i+1)%circuit.size()]))
  check(not path.is_empty(),"cloister leg %d remains usable without entering conservation or climbing the armory" % i)
 for id in closed:_floor._nav.set_point_solid(id,false)
 var stair_route: Array=_floor._nav_path(Vector2(17,2),Vector2(12,2))
 check(not stair_route.is_empty(),"rear side climb reaches the real upper landing")
 var saw_stair:=false;var local:=true
 for point in stair_route:
  saw_stair=saw_stair or _floor.room_rect("keep_stair").has_point(point)
  local=local and point.x>=11.5 and point.y<4
 check(saw_stair and local,"armory route uses its transverse flight without a remote detour")
 for dept in ["gallery","promotions"]:
  for point in _floor._stations(dept):check(not _floor._nav.is_point_solid(_floor._nav_id(point)),dept+" employee has clear standing space: "+str(point))
 for exhibit in _floor._theme.exhibits:
  for point in _floor.browse_spots()[exhibit.id]:
   check(_floor.room_rect(exhibit.viewing_room).has_point(point),str(exhibit.id)+" audience stays in the correct collection space")
   check(not _floor._nav.is_point_solid(_floor._nav_id(point)),str(exhibit.id)+" viewpoint is clear before navigation adjustment: "+str(point))
 for spec in _floor._theme.props:
  if not spec.get("solid_footprint",false):continue
  var at: Vector2=_floor.Exhibits.v2(spec.at);var size: Vector2=_floor.Exhibits.v2(spec.size)
  for u in [.2,.5,.8]:
   for v in [.2,.5,.8]:check(_floor._nav.is_point_solid(_floor._nav_id(at+size*Vector2(u,v))),"keep furniture reserves its complete physical footprint")
 check(Props._textures.has("res://art/environment/ironwood_citadel-counter_body-west.png"),"east gatehouse uses original west-facing counter geometry")
