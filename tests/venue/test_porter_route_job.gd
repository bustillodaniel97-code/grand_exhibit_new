extends SceneTree
const Router=preload("res://scenes/venue/floor/porter_router.gd")
const Job=preload("res://scenes/venue/floor/porter_route_job.gd")
class TestLayout extends RefCounted:
 var closed := false
 func fits(at: Vector2,heading: Vector2,_claims: bool=false) -> bool:
  for forward in [-.2,0.0,.68]:
   for side in [-.24,0.0,.24]:
    var p: Vector2=at+heading*float(forward)+Vector2(heading.y,-heading.x)*float(side)
    if not Rect2(0,0,8,8).has_point(p):return false
    if Rect2(3,0,1,8 if closed else 5).has_point(p):return false
  return true
var failures:=0
func check(ok: bool,label: String) -> void:
 if not ok:failures+=1;printerr("FAIL: ",label)
func _initialize() -> void:call_deferred("run")
func finish(job: RefCounted,budget: int) -> void:
 var slices:=0
 while job.pending() and slices<100000:
  job.advance(budget,0);slices+=1
  check(job.last_operations<=budget,"a slice never exceeds its operation budget")
 check(not job.pending(),"bounded search reaches a terminal result")
func run() -> void:
 root.get_node("SaveSystem").set_process(false)
 var layout:=TestLayout.new();var router:=Router.new();router.configure(layout)
 var start:=Vector2(1,1);var target:=Vector2(6,2)
 var expected:=router.route(start,Vector2.DOWN,target,Vector2.UP)
 check(not expected.is_empty(),"fixture requires a long detour around the wall")
 for budget in [1,7,32]:
  var job:=Job.new();job.begin(router,start,Vector2.DOWN,target,Vector2.UP)
  job.advance(0,0);check(job.status=="validating" and job.last_operations==0,"zero work budget does not advance")
  finish(job,budget)
  check(job.status=="ready" and job.result==expected,"resuming at different slice boundaries preserves exact route")
 var same:=Job.new();same.begin(router,start,Vector2.DOWN,start,Vector2.DOWN);finish(same,1)
 check(same.status=="ready" and same.result.is_empty(),"already parked is distinguishable from no route")
 var invalid:=Job.new();invalid.begin(router,Vector2(-1,-1),Vector2.DOWN,target,Vector2.UP);finish(invalid,1)
 check(invalid.status=="unreachable" and invalid.result.is_empty(),"invalid start never becomes a straight-line fallback")
 var stale:=Job.new();stale.begin(router,start,Vector2.DOWN,target,Vector2.UP);stale.advance(20,0)
 router.configure(layout);stale.advance();check(stale.status=="cancelled" and stale.result.is_empty(),"geometry invalidation discards unfinished search")
 var a:=Job.new();var b:=Job.new();a.begin(router,start,Vector2.DOWN,target,Vector2.UP);b.begin(router,target,Vector2.UP,start,Vector2.DOWN)
 var slices:=0
 while (a.pending() or b.pending()) and slices<100000:
  a.advance(7,0);b.advance(9,0);slices+=1
 check(a.status=="ready" and b.status=="ready","interleaved jobs share geometry cache without sharing search state")
 check(a.result==expected,"interleaved search preserves the route")
 layout.closed=true;router.configure(layout)
 var blocked:=Job.new();blocked.begin(router,start,Vector2.DOWN,target,Vector2.UP);finish(blocked,32)
 check(blocked.status=="unreachable" and blocked.result.is_empty(),"a genuinely disconnected destination terminates safely")
 print("Porter route job failures: ",failures);quit(1 if failures else 0)
