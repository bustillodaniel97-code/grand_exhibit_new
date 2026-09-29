extends "res://tools/campaign_circulation_audit.gd"
## Inspect actual movement and collection use through the final museum.
var occupied_floors: Dictionary={}
func _check_all_venues() -> void:
 super._check_all_venues()
 check(occupied_floors.size()==4,"live visitors browse collections on all four museum floors")
 print("INFINITE_OCCUPIED_FLOORS ",occupied_floors.keys())
func _observe_step(kind: String,a: Vector2,b: Vector2,state: String) -> void:
 super._observe_step(kind,a,b,state)
 var room: Dictionary=_floor._theme.room_at(b)
 if kind=="visitor" and state=="browse" and int(room.get("rise_to",0))==int(room.get("level",0)):
  occupied_floors[_floor._theme.level_at(b)]=true
 for spec in _floor._theme.exhibits:
  if not spec.get("solid_footprint",false):continue
  var rect:=Rect2(_floor.Exhibits.v2(spec.at),_floor.Exhibits.footprint(spec)).grow(-.01)
  if _floor._plaza._interval(a,b,rect).is_finite():
   violations+=1
   if crossings.size()<8:crossings[kind+":"+state+" exhibit "+str(spec.id)]=[str(a),str(b)]
