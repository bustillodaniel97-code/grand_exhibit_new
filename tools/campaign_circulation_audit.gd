extends "res://tests/venue/test_operational_routes.gd"
## Seeded, accelerated simulation with actual per-step movement observations.
## No actor is teleported to an objective or assigned a synthetic destination.
var observations: Dictionary = {}
var crossings: Dictionary = {}
var movement_steps := 0
var observed_rooms: Dictionary = {}
var violations := 0
func _check_all_venues() -> void:
 var old_floor: Control = _floor
 root.remove_child(old_floor);old_floor.free()
 _floor=load("res://tools/circulation_audit_floor.gd").new()
 _floor.set_size(Vector2(720,760));_floor.audit_step=_observe_step
 root.add_child(_floor);_floor.time_scale=0
 var gs: Node=root.get_node("GameState")
 var ec: Node=root.get_node("Economy")
 ec.set_process(false)
 var requested := OS.get_environment("GRAND_EXHIBIT_AUDIT_VENUE")
 check(requested=="" or requested in DL.venue_order(),"requested museum exists")
 for vid in DL.venue_order():
  if requested != "" and str(vid) != requested:continue
  seed(8107)
  gs.current_venue=str(vid)
  for dept in ["ticket","archive","promotions","gallery"]:
   for track in ["staff","speed","value"]:gs.set_dept_level(str(vid),dept,track,8)
  _floor.retheme(str(vid));_floor.set_rates(ec.venue_rates(str(vid)))
  crossings={};observations={};observed_rooms={};movement_steps=0;violations=0
  var before_trips: int=_floor.get_porter_trips()
  _floor.advance_sim(240)
  print("LIVE_CIRCULATION ",vid," steps=",movement_steps," states=",observations," rooms=",observed_rooms.keys()," porter_trips=",_floor.get_porter_trips()-before_trips," violations=",violations," route_failures=",_floor._unreachable_targets," crossings=",crossings)
  check(crossings.is_empty(),str(vid)+" live movement never crosses walls or cliffs")
  check(_floor._unreachable_targets.is_empty(),str(vid)+" live movement has no failed indoor routes")
  check(_floor.get_porter_trips()>before_trips,str(vid)+" porters complete deliveries")
  check(observations.has("visitor:browse") and observations.has("visitor:exit"),str(vid)+" guests reach exhibits and leave")
func _observe_step(kind: String,a: Vector2,b: Vector2,state: String) -> void:
 movement_steps+=1
 observations[kind+":"+state]=true
 var room: Dictionary=_floor._theme.room_at(b)
 observed_rooms[str(room.get("id","outside"))]=true
 var crossing:=_wall_crossing(a,b)
 if crossing=="":crossing=_cliff_crossing(a,b)
 if crossing!="":
  violations+=1
  if crossings.size()<8:crossings[kind+":"+state+" "+crossing]=[str(a),str(b)]
