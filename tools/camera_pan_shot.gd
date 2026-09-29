extends "res://tools/shot.gd"
## Capture a real panned view using the production camera limits.
var panned := false
func _process(delta: float) -> bool:
 if not panned and _t > 1.5:
  var floor_node := _find_floor(root)
  if floor_node != null:
   floor_node._pan_camera(Vector2(float(_args.get("pan_x",-10000)),0))
   panned = true
 return super._process(delta)
