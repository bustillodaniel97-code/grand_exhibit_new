extends "res://tools/campaign_circulation_audit.gd"
## Observe every production movement segment against the actual ground exhibits,
## in addition to the shared wall/cliff and destination audit.
var departure_crossings := 0
func _check_all_venues() -> void:
 super._check_all_venues()
 check(departure_crossings>0,"live visitors actually leave through the separate east departure hall")
 print("PELAGIC_DEPARTURES ",departure_crossings)
func _observe_step(kind: String,a: Vector2,b: Vector2,state: String) -> void:
 super._observe_step(kind,a,b,state)
 if kind=="visitor" and state=="exit" and a.y<_floor._exit_wall_g.y and b.y>=_floor._exit_wall_g.y:
  departure_crossings+=1
  if absf(b.x-_floor._exit_wall_g.x)>.9:
   violations+=1;crossings["departure used the wrong facade"]=[str(a),str(b)]
 for spec in _floor._theme.exhibits:
  if not spec.get("solid_footprint",false):continue
  var rect:=Rect2(_floor.Exhibits.v2(spec.at),_floor.Exhibits.footprint(spec)).grow(-.01)
  if _floor._plaza._interval(a,b,rect).is_finite():
   violations+=1
   if crossings.size()<8:crossings[kind+":"+state+" water/exhibit "+str(spec.id)]=[str(a),str(b)]
