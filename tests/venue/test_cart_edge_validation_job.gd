extends SceneTree
const EdgeJob:=preload("res://scenes/venue/floor/cart_edge_validation_job.gd")
const Router:=preload("res://scenes/venue/floor/porter_router.gd")
const Snapshot:=preload("res://scenes/venue/floor/cart_dispatch_geometry.gd")
class Layout extends RefCounted:
 var blocked_angle:=false
 func _height_at(_at: Vector2)->float:return 0.0
 func fits(_at: Vector2,heading: Vector2,_claims: bool=false)->bool:
  return not blocked_angle or absf(heading.angle_to(Vector2.RIGHT))>.20
var failures:=0
func check(ok: bool,label: String)->void:
 if not ok:failures+=1;printerr("FAIL: ",label)
func incremental(snapshot: RefCounted,a: Vector3i,b: Vector3i,turning: bool,slice: int=3)->Dictionary:
 var job:=EdgeJob.new();job.begin(snapshot,a,b,turning);var yielded:=false
 while job.status!="ready":job.advance(slice,0);yielded=yielded or job.status!="ready"
 return {"result":job.result,"yielded":yielded,"samples":job.sample}
func _initialize()->void:
 root.get_node("SaveSystem").set_process(false)
 var layout:=Layout.new();var router:=Router.new();router.configure(layout)
 var a:=router.key(Vector2(2,2),Vector2.RIGHT);var move:=router.key(Vector2(2.25,2),Vector2.RIGHT);var turn:=router.key(Vector2(2,2),Vector2.DOWN)
 var poses: Array=[{"at":Vector2(4,4),"heading":Vector2.RIGHT,"height":0.0}]
 var points: Array=[[{"at":Vector2(5,5),"radius":.22,"height":0.0}]]
 var sync:=Snapshot.new();sync.begin_configure(router,[poses],[],points)
 while sync.setup_pending:sync.advance_setup(100,0)
 var expected_move:=sync.can_move(a,move);var expected_turn:=sync.can_turn(a,turn)
 var sliced:=Snapshot.new();sliced.begin_configure(router,[poses],[],points)
 while sliced.setup_pending:sliced.advance_setup(100,0)
 var got_move:=incremental(sliced,a,move,false,2);var got_turn:=incremental(sliced,a,turn,true,4)
 check(got_move.result==expected_move and got_turn.result==expected_turn,"incremental decisions match uncached current geometry")
 check(got_turn.yielded and int(got_turn.samples)==65,"turn validation yields between angular samples and preserves 31+33 samples")
 var cached:=EdgeJob.new();cached.begin(sliced,a,turn,true)
 check(cached.status=="ready" and cached.result==expected_turn,"completed decisions populate and reuse the existing edge cache")
 var person: Array=[[{"at":Vector2(2.67,2),"radius":.22,"height":0.0}]]
 var person_sync:=Snapshot.new();person_sync.begin_configure(router,[],[],person)
 while person_sync.setup_pending:person_sync.advance_setup(100,0)
 var person_expected:=person_sync.can_move(a,move)
 var person_slice:=Snapshot.new();person_slice.begin_configure(router,[],[],person)
 while person_slice.setup_pending:person_slice.advance_setup(100,0)
 check(incremental(person_slice,a,move,false,1).result==person_expected and not person_expected,
  "five dynamic translation poses retain point-obstacle rejection")
 var upstairs: Array=[[{"at":Vector2(2.67,2),"radius":.22,"height":73.0}]]
 var upstairs_slice:=Snapshot.new();upstairs_slice.begin_configure(router,[],[],upstairs)
 while upstairs_slice.setup_pending:upstairs_slice.advance_setup(100,0)
 check(incremental(upstairs_slice,a,move,false,1).result,
  "incremental point checks preserve the 73-pixel storey clearance")
 layout.blocked_angle=true;router.configure(layout)
 var blocked_sync:=Snapshot.new();blocked_sync.configure(router,[]);var blocked_expected:=blocked_sync.can_turn(a,turn)
 var blocked_slice:=Snapshot.new();blocked_slice.configure(router,[]);var blocked_got:=incremental(blocked_slice,a,turn,true,1)
 check(blocked_got.result==blocked_expected and not blocked_got.result,"static interior angular rejection matches current geometry")
 print("Cart edge validation failures: ",failures);quit(1 if failures else 0)
