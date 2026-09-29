extends "res://tests/venue/test_nav_reachability.gd"
## Read-only audit of real operational destinations, including rendered walls.
func _check_all_venues() -> void:
 super._check_all_venues()
 var report: Dictionary = {}
 for vid in DL.venue_order():
  root.get_node("GameState").current_venue = str(vid)
  _prepare_venue(str(vid))
  _floor.retheme(str(vid))
  _floor._windows_active = _floor._max_windows
  _floor._props_key = ""
  _floor._rebuild_props()
  check(is_equal_approx(_floor._city.canopy_point().x,_floor._door_g.x),str(vid)+" canopy aligns with the real lobby entrance")
  var routes: Array = []
  for key in _floor._browse:
   for target in _floor._browse[key]:routes.append(["exhibit:"+str(key),_floor._door_g,_floor._safe_nav_spot(target)])
  for seat in _floor._seats:routes.append(["seat",_floor._door_g,seat])
  var promo: Dictionary = _floor._theme.role("promo")
  var pr: Rect2 = promo["rect"]
  for fx in [.32,.5,.68]:
   for fy in [.58,.78]:routes.append(["promo",_floor._door_g,_floor._safe_nav_spot(pr.position+pr.size*Vector2(fx,fy))])
  routes.append(["exit",_floor._door_g,_floor._exit_door_g])
  routes.append(["entrance_gate",_floor._door_g,Vector2(_floor._door_g.x,(_floor._theme.role("lobby")["rect"] as Rect2).end.y+.5)])
  routes.append(["exit_gate",_floor._exit_door_g,_floor._exit_wall_g+Vector2(0,.5)])
  for waypoint in _floor._gallery_egress:routes.append(["egress",_floor._door_g,waypoint])

  routes.append(["vault_entry",_floor._porter_home,_floor._vault_entry])
  routes.append(["vault_drop",_floor._vault_entry,_floor._vault_drop])
  for station in _floor._admissions.stations:
   routes.append(["porter_to_counter",_floor._porter_home,station.porter])
  routes.append(["queue_aisle",_floor._door_g,_floor._queue_aisle(true)])
  for w in _floor._max_windows:
   routes.append(["queue_mouth",_floor._queue_aisle(true),_floor._queue_mouth(w)])
   routes.append(["cashier_head_departure",_floor._slot_pos(w,0),_floor._cashier_exit(w)])
   routes.append(["cashier_departure",_floor._cashier_exit(w),_floor._exit_door_g])
   for i in _floor._slots_per_window:
    routes.append(["queue_slot",_floor._queue_mouth(w),_floor._slot_pos(w,i)])
  for i in range(4):
   routes.append(["porter_home",_floor._vault_drop,_floor._porter_home+Vector2(i*_floor._porter_step,0)])
  var findings: Array = []
  for route in routes:
   if _floor._nav.is_point_solid(_floor._nav_id(route[2])):
    findings.append({"target":route[0],"problem":"blocked_destination","to":str(route[2])});continue
   var points: Array = [route[1]]
   var middle: Array = _floor._nav_path(route[1],route[2])
   points.append_array(middle);points.append(route[2])
   if middle.is_empty() and (route[1] as Vector2).distance_to(route[2])>.5:
    findings.append({"target":route[0],"problem":"no_route","from":str(route[1]),"to":str(route[2]),"blocked":_floor._nav.is_point_solid(_floor._nav_id(route[2]))});continue
   var crossing := ""
   for i in range(1,points.size()):
    crossing = _wall_crossing(points[i-1],points[i])
    if crossing=="":crossing=_cliff_crossing(points[i-1],points[i])
    if crossing!="":break
   if crossing!="":findings.append({"target":route[0],"problem":"wall_crossing","wall":crossing})
  check(findings.is_empty(), "%s: all %d operational routes clear walls, cliffs and blocked destinations%s" % [vid,routes.size(), "" if findings.is_empty() else str(findings)])
  report[str(vid)]={"routes_checked":routes.size(),"findings":findings}
  if OS.has_environment("GRAND_EXHIBIT_CONNECTIVITY_MAP"):
   var solid: Array = []
   for y in range(_floor._nav.region.position.y,_floor._nav.region.end.y):
    for x in range(_floor._nav.region.position.x,_floor._nav.region.end.x):
     if _floor._nav.is_point_solid(Vector2i(x,y)):solid.append([x*.25,y*.25])
   var seats: Array=[]
   for seat in _floor._seats:seats.append([seat.x,seat.y])
   report[str(vid)]["solid"]=solid
   report[str(vid)]["seats"]=seats
 if OS.has_environment("GRAND_EXHIBIT_CONNECTIVITY_REPORT"):
  var file:=FileAccess.open(OS.get_environment("GRAND_EXHIBIT_CONNECTIVITY_REPORT"),FileAccess.WRITE)
  file.store_string(JSON.stringify(report,"  "));file.close()
func _wall_crossing(a: Vector2,b: Vector2) -> String:
 for w in _floor._theme.walls:
  var at: Vector2=Vector2(float(w["at"][0]),float(w["at"][1])) if w["at"] is Array else w["at"]
  var x_axis: bool=str(w.get("axis","x"))=="x"
  var start: float=at.x if x_axis else at.y
  var plane: float=at.y if x_axis else at.x
  var d0: float=(a.y if x_axis else a.x)-plane
  var d1: float=(b.y if x_axis else b.x)-plane
  if d0*d1>0 or is_equal_approx(d0,d1):continue
  var t: float=-d0/(d1-d0)
  if t<0 or t>1:continue
  var p:=a.lerp(b,t)
  var along: float=p.x if x_axis else p.y
  if along<start+.03 or along>start+float(w.get("len",0))-.03:continue
  var wall_base: float=float(w.get("level",0))*74
  var foot: float=-_floor._theme.lift_at(p)
  if foot>=wall_base+float(w.get("h",52))-.5 or foot+40<wall_base:continue
  return str(at)+" "+str(w.get("axis","x"))+" len="+str(w.get("len",0))
 return ""

func _cliff_crossing(a: Vector2,b: Vector2) -> String:
 var slope := 0.0
 for point in [a,b]:
  var room: Dictionary = _floor._theme.room_at(point)
  if room.is_empty():continue
  var from_level:=int(room.get("level",0))
  var to_level:=int(room.get("rise_to",from_level))
  if from_level==to_level:continue
  var rect: Rect2=room["rect"]
  var axis: String=str(room.get("stair_axis","x" if rect.size.x>=rect.size.y else "y"))
  slope=maxf(slope,absf(to_level-from_level)*74.0/(rect.size.x if axis=="x" else rect.size.y))
 var jump: float=absf(_floor._theme.lift_at(a)-_floor._theme.lift_at(b))
 return "cliff: %s -> %s (%s px)" % [a,b,jump] if jump>slope*a.distance_to(b)+1.0 else ""

## Extension hook for testing circulation with purchased furnishings.
func _prepare_venue(_vid: String) -> void:
 pass
