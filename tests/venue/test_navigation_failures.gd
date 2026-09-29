extends "res://tests/venue/test_nav_reachability.gd"
## A missing route may not turn into a straight walk; subpixel drift may not
## put a pedestrian on the wrong side of a three-storey platform boundary.
func _check_all_venues() -> void:
 root.get_node("GameState").current_venue="infinite_museum"
 _floor.retheme("infinite_museum")
 _floor._spawn_t=10
 _floor._try_spawn()
 check(not _floor._visitors.is_empty(),"spawned a real visitor for movement regression")
 if _floor._visitors.is_empty():return
 var visitor = _floor._visitors[0]
 # A controlled nearly-arrived waypoint at the current three-storey edge.
 # This isolates numerical placement; real stair/wall routes are tested separately.
 var observatory: Rect2=_floor.room_rect("observatory")
 var waypoint:=Vector2(observatory.end.x,observatory.end.y-1.5)
 visitor.pos=waypoint-Vector2(.00002,.01)
 visitor.path=[waypoint]
 visitor.target=waypoint+Vector2(.5,0)
 check(_floor._theme.level_at(visitor.pos)==3,"drift fixture starts just inside the current observatory edge")
 _floor._place(visitor.node,visitor.pos)
 var first_distance: float=visitor.pos.distance_to(waypoint)
 var remaining_distance: float=visitor.speed*.05-first_distance
 _floor._move(visitor,.05)
 check(visitor.pos.distance_to(waypoint+Vector2(remaining_distance,0))<.00001,"waypoint snap consumes the exact remaining distance on the next leg")
 check(visitor.path.is_empty() and visitor.target==waypoint+Vector2(.5,0),"reached waypoint retires while the exact final destination is retained")
 check(visitor.pos.y==waypoint.y and is_zero_approx(_floor._theme.lift_at(visitor.pos)),"continuation stays on the snapped ground-side axis without cliff drift")
 var stayed_on_ground:=true
 for i in range(50):
  _floor._move(visitor,.05)
  if not is_zero_approx(_floor._theme.lift_at(visitor.pos)):stayed_on_ground=false
 check(stayed_on_ground,"moving away from the observatory edge stays at ground level")
 check(visitor.pos==visitor.target,"visitor actually moves away from the edge instead of passing by remaining stuck")
 var target:=Vector2(15,6.5)
 check(not _floor._nav.is_point_solid(_floor._nav_id(target)) and not _floor._nav_ids(Vector2(14,6.5),target).is_empty(),"isolation fixture has a real open route before it is blocked")
 var center: Vector2i=_floor._nav_id(target)
 for y in range(center.y-1,center.y+2):
  for x in range(center.x-1,center.x+2):_floor._nav.set_point_solid(Vector2i(x,y),true)
 var path: Array=[]
 check(not _floor._prepare_indoor_segment(Vector2(14,6.5),target,path),"an isolated destination stops movement instead of tunnelling through obstacles")
 check(path.is_empty(),"a failed route creates no fake direct path")
