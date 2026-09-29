extends SceneTree
## test_courier_coordination.gd — dispatcher coordination unit regressions.
##
## Three focused cases over the fake-floor harness (deterministic, fast):
##  1. REFUGE CLEARANCE: a refuge pose overlapping a parked colleague must be
##     rejected. The old is_refuge checked only the winner's path, so a
##     relocated porter could rest intersecting another cart - and every later
##     tick sampled another overlap fault (5,908 such samples on grand_river).
##  2. SILENCE BREAKER: when every pending request is tried-gated and nothing
##     moves, the dispatcher must re-arm the oldest gated request instead of
##     stalling quietly until process end.
##  3. NO RELOCATE OF SEARCHERS: a colleague mid-search must not be yanked
##     into refuge (discarding a cold search); a colleague with no live search
##     keeps the existing relocation path.
const Dispatch:=preload("res://scenes/venue/floor/cart_dispatch.gd")
const Snapshot:=preload("res://scenes/venue/floor/cart_dispatch_geometry.gd")
const Geometry:=preload("res://scenes/venue/floor/cart_traffic_geometry.gd")
const Router:=preload("res://scenes/venue/floor/porter_router.gd")
class Layout extends RefCounted:
 var narrow:=false
 func _height_at(_at: Vector2) -> float:return 0.0
 func fits(at: Vector2,heading: Vector2,_claims: bool=false) -> bool:
  for forward in [-.2,0.0,.68]:
   for side in [-.24,0.0,.24]:
    var point: Vector2=at+heading*forward+Vector2(heading.y,-heading.x)*side
    if not Rect2(0,0,8,8).has_point(point):return false
    if narrow and point.x>2 and point.x<6 and (point.y<2 or point.y>3):return false
  return true
class Body extends RefCounted:
 var walking:=false
class Cart extends RefCounted:
 var node:=Body.new()
 var pos:=Vector2.ZERO
 var heading:=Vector2.RIGHT
 var dock: Dictionary={}
 var target:=Vector2.ZERO
 var state:="to_vault"
 var carried:=3
 var window:=-1
 var route_job: RefCounted
 var route_steps: Array=[]
 var route_cursor:=0
 var motion_step: Dictionary={}
 var turn_progress:=0.0
 var dispatch_standby:=false
class Floor extends Node:
 var _porters: Array=[]
 var _porter_layout:=Layout.new()
 var _porter_router:=Router.new()
var failures:=0
var checks:=0
func check(ok: bool,label: String) -> void:
 checks+=1
 if not ok:failures+=1;printerr("FAIL: ",label)
 else:print("PASS ",label)
func cart(at: Vector2,to: Vector2,heading: Vector2) -> RefCounted:
 var p:=Cart.new();p.pos=at;p.heading=heading;p.target=to;p.dock={"at":to,"heading":heading};return p
func _initialize() -> void:call_deferred("run")
func run() -> void:
 root.get_node("SaveSystem").set_process(false)
 _test_refuge_clears_colleagues()
 _test_silence_breaker_rearms()
 _test_searchers_not_relocated()
 print("---")
 print("courier coordination: %d failure(s)" % failures)
 quit(0 if failures == 0 else 1)

# A refuge admitted onto a parked colleague rests intersecting it. The pose
# must be rejected when a colleague occupies it, accepted when clear.
func _test_refuge_clears_colleagues() -> void:
 print("-- refuge clearance --")
 var f:=Floor.new();root.add_child(f);f._porter_router.configure(f._porter_layout)
 var parked := {"at":Vector2(4,4),"heading":Vector2.RIGHT,"height":0.0}
 var snap:=Snapshot.new();snap.configure(f._porter_router,[parked],[])
 snap.origin=Vector2.ZERO
 var over_key: Vector3i = snap.key(Vector2(4,4),Vector2.RIGHT)
 var clear_key: Vector3i = snap.key(Vector2(6.5,6.5),Vector2.RIGHT)
 check(not snap.is_refuge(over_key),"refuge overlapping a parked colleague is rejected")
 check(snap.is_refuge(clear_key),"refuge on clear ground is still accepted")
 f.queue_free()

# Two tried-gated requests and no motion anywhere: without a silence breaker
# the dispatcher idles with an empty active set forever.
func _test_silence_breaker_rearms() -> void:
 print("-- silence breaker --")
 var f:=Floor.new();root.add_child(f);f._porter_router.configure(f._porter_layout)
 var dispatch:=Dispatch.new();dispatch.configure(f)
 var a:=cart(Vector2(1,2),Vector2(7,2),Vector2.RIGHT)
 var b:=cart(Vector2(1,6),Vector2(7,6),Vector2.RIGHT)
 f._porters=[a,b];dispatch.enqueue(a);dispatch.enqueue(b)
 for request in dispatch.requests:request.tried=dispatch.revision
 check(dispatch.active.is_empty(),"fixture starts with no active request")
 dispatch.advance(8,0)
 check(not dispatch.active.is_empty(),"all-gated silence re-arms the oldest request instead of stalling")
 f.queue_free()

# A colleague mid-search is about to move on its own: validation failure
# must route around (or wait for) it, never convert its cold search into a
# refuge victim. A colleague with no live search keeps today's behavior.
func _test_searchers_not_relocated() -> void:
 print("-- searchers not relocated --")
 var f:=Floor.new();root.add_child(f);f._porter_router.configure(f._porter_layout)
 var dispatch:=Dispatch.new();dispatch.configure(f)
 var a:=cart(Vector2(1,2),Vector2(7,2),Vector2.RIGHT)
 var b:=cart(Vector2(4,2),Vector2(7,2),Vector2.RIGHT)
 f._porters=[a,b];dispatch.enqueue(a);dispatch.enqueue(b)
 var areq: Dictionary=dispatch._find(a)
 areq.envelope=[{"at":Vector2(4,2),"heading":Vector2.RIGHT,"height":0.0}]
 var occ:=Snapshot.new()
 occ.configure(f._porter_router,[{"at":Vector2(4,2),"heading":Vector2.RIGHT,"height":0.0}],[])
 areq.envelope_index=occ.occupied
 areq.intent=[0]
 b.route_job=RefCounted.new()
 check(not dispatch._try_relocation(areq),"a searching colleague is not relocated")
 check(not dispatch.holds.has(b),"a searching colleague keeps its own work")
 f.queue_free()
 # Fresh fixture: preservation must hold independently of the case above.
 var f2:=Floor.new();root.add_child(f2);f2._porter_router.configure(f2._porter_layout)
 var dispatch2:=Dispatch.new();dispatch2.configure(f2)
 var c:=cart(Vector2(1,2),Vector2(7,2),Vector2.RIGHT)
 var d:=cart(Vector2(4,2),Vector2(7,2),Vector2.RIGHT)
 f2._porters=[c,d];dispatch2.enqueue(c);dispatch2.enqueue(d)
 var creq: Dictionary=dispatch2._find(c)
 creq.envelope=[{"at":Vector2(4,2),"heading":Vector2.RIGHT,"height":0.0}]
 var occ2:=Snapshot.new()
 occ2.configure(f2._porter_router,[{"at":Vector2(4,2),"heading":Vector2.RIGHT,"height":0.0}],[])
 creq.envelope_index=occ2.occupied
 creq.intent=[0]
 check(dispatch2._try_relocation(creq),"a colleague with no live search keeps the relocation path")
 check(dispatch2.holds.has(d),"the relocation hold is recorded for an idle blocker")
 f2.queue_free()
 print("COURIER_COORDINATION checks=", checks, " failures=", failures)
