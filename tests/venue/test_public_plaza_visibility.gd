extends "res://tests/venue/test_nav_reachability.gd"
## The user's ordinary portrait, not a zoomed art preview: all public activity
## destinations and each complete active dog-walk leg must remain in view.
func _check_all_venues() -> void:
 _floor.set_size(Vector2(720,910))
 var visible := Rect2(Vector2(24,48),_floor.size-Vector2(48,64))
 for vid in DL.venue_order():
  root.get_node("GameState").current_venue = str(vid)
  _floor.retheme(str(vid))
  _floor._fit_canvas()
  var plaza = _floor._plaza
  for fixture in plaza.fixtures:
   var rect: Rect2 = fixture.rect
   var inside := true
   for corner in [rect.position,Vector2(rect.end.x,rect.position.y),rect.end,Vector2(rect.position.x,rect.end.y)]:
    inside = inside and visible.has_point(_floor.grid_to_view(corner))
   check(inside,str(vid)+" complete "+fixture.kind+" footprint is visible without panning")
  for activity in plaza.activities:
   check(visible.has_point(_floor.grid_to_view(activity.at)),str(vid)+" "+activity.kind+" activity is in the normal portrait")
   if activity.kind=="rest":
    check(visible.has_point(_floor.grid_to_view(activity.seat)),str(vid)+" seated visitor is in view")
   if activity.kind=="feed":
    var birds_clear := true
    var birds_visible := true
    for i in 3:
     for tick in 160:
      var ground: Vector2 = plaza.bird_position(activity,i,tick*.1)
      birds_clear = birds_clear and plaza.walkable(ground)
      birds_visible = birds_visible and visible.has_point(_floor.grid_to_view(ground))
    check(birds_clear,str(vid)+" complete bird hop cycle remains on clear pavement")
    check(birds_visible,str(vid)+" entire flock stays inside the normal portrait")
   if activity.kind=="dog":
    var cursor: Vector2 = activity.at
    for raw in activity.walk:
     var target: Vector2 = plaza._authored_point(raw)
     var path: Array = plaza.route(cursor,target)
     var inside := not path.is_empty()
     for point in path:
      if not visible.has_point(_floor.grid_to_view(point)):
       print("OUTDOOR_ROUTE_OFFSCREEN ",vid," grid=",point," view=",_floor.grid_to_view(point))
       inside = false
     check(inside,str(vid)+" active dog-walk route stays in view")
     cursor = target
