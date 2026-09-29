extends "res://tools/campaign_circulation_audit.gd"
## Check production movement against every physically grounded palace exhibit.
func _observe_step(kind: String,a: Vector2,b: Vector2,state: String) -> void:
 super._observe_step(kind,a,b,state)
 for spec in _floor._theme.exhibits:
  if not spec.get("solid_footprint",false):continue
  var rect:=Rect2(_floor.Exhibits.v2(spec.at),_floor.Exhibits.footprint(spec)).grow(-.01)
  if _floor._plaza._interval(a,b,rect).is_finite():
   violations+=1
   if crossings.size()<8:crossings[kind+":"+state+" exhibit "+str(spec.id)]=[str(a),str(b)]
