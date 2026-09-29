extends "res://tests/venue/test_nav_reachability.gd"
## Exercise real graph routes, including the apron seats used after browsing.
func _check_all_venues() -> void:
 _floor.retheme("cloudrest")
 _floor._props_key = ""
 _floor._rebuild_props()
 var origin: Vector2i = _walkable_in(_floor._theme.role("lobby")["rect"])
 for stair in _floor._theme.rooms:
  if stair.level==stair.rise_to:continue
  var rect: Rect2=stair.rect
  var sides: Array=[Vector2(rect.get_center().x,rect.position.y),Vector2(rect.get_center().x,rect.end.y-.25)] if stair.get("stair_axis","y")=="x" else [Vector2(rect.position.x,rect.get_center().y),Vector2(rect.end.x-.25,rect.get_center().y)]
  for middle_side in sides:
   check(_floor._nav.is_point_solid(_floor._nav_id(middle_side)),"Cloudrest blocks each stair's middle side boundary")
 for seat in _floor._seats:
  var route: Array[Vector2i] = _floor._nav.get_id_path(origin, _floor._nav_id(seat))
  check(not route.is_empty(), "Cloudrest seat has a real route: %s" % seat)
  for i in range(1, route.size()):
   var from: Vector2 = Vector2(route[i-1]) * .25
   var to: Vector2 = Vector2(route[i]) * .25
   var jump: float = absf(_floor._theme.lift_at(from) - _floor._theme.lift_at(to))
   if jump > 8:
    check(false, "Seat route crosses a cliff: %s -> %s (%s pixels)" % [from, to, jump])
    break
