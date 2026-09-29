extends SceneTree
const Crowd:=preload("res://scenes/venue/floor/crowd_traffic.gd")
class Layout extends RefCounted:
 func _height_at(_at: Vector2) -> float:return 0.0
class Cart extends RefCounted:
 var pos:=Vector2.ZERO
 var heading:=Vector2.RIGHT
 var motion_step: Dictionary={}
 var turn_progress:=0.0
 var staged:=true
class Floor extends Node:
 var _visitors: Array=[]
 var _rejected: Array=[]
 var _porters: Array=[]
 var _cart_dispatch:=preload("res://scenes/venue/floor/cart_dispatch.gd").new()
 var _porter_layout:=Layout.new()
 var _nav:=AStarGrid2D.new()
 func _nav_id(at: Vector2) -> Vector2i:return Vector2i((at*4).round())
class Visitor extends RefCounted:
 var state:="to_crowd"
 var cart_refuge:=false
 var cart_refuge_at:=Vector2.ZERO
 var cart_refuge_target:=Vector2.ZERO
 var cart_refuge_blockers: Array=[]
 var pos:=Vector2.ZERO
 var target:=Vector2.ZERO
 var path: Array=[]
 var cart_retry:=0.0
var failures:=0
func check(ok: bool,label: String) -> void:
 if not ok:failures+=1;printerr("FAIL: ",label)
func _initialize() -> void:call_deferred("run")
func run() -> void:
 root.get_node("SaveSystem").set_process(false)
 var f:=Floor.new();root.add_child(f)
 f._nav.region=Rect2i(-16,-16,48,48);f._nav.diagonal_mode=AStarGrid2D.DIAGONAL_MODE_NEVER;f._nav.update()
 var c:=Crowd.new();c.configure(f);f._cart_dispatch.configure(f)
 var pose:={"at":Vector2.ZERO,"heading":Vector2.RIGHT,"height":0.0}
 check(c.overlaps_segment(Vector2(-1,0),Vector2(2,0),pose),"crossing catches cart even with clear endpoints")
 check(not c.overlaps_segment(Vector2(-.40,.43),Vector2(-.41,.44),pose),"rounded corner permits a legal retreat")
 check(c.overlaps_segment(Vector2(.2,-1),Vector2(.2,1),pose),"side crossing catches whole body")
 var v:=Visitor.new();v.pos=Vector2(-1,0);v.target=Vector2(2,0);v.path=[Vector2(-.5,0),Vector2(1,0)]
 c.cart_poses=[pose];c.repaths_left=1
 check(c.try_detour(v),"guest finds route around a stopped cart")
 check(v.target==Vector2(2,0),"detour preserves original destination")
 var prior:=v.pos;var clear:=true
 for point in v.path+[v.target]:
  clear=clear and not c.overlaps_segment(prior,point,pose);prior=point
 check(clear,"every detour segment clears cart footprint")
 var solid:=0
 for y in range(-16,32):
  for x in range(-16,32):
   if f._nav.is_point_solid(Vector2i(x,y)):solid+=1
 check(solid==0,"temporary cart cells fully restored")
 v.pos=Vector2(-1,0);v.target=Vector2(.2,0);v.path=[];v.cart_retry=0;c.repaths_left=1
 check(c.try_detour(v) and v.cart_refuge,"occupied final destination sends a travelling guest to a refuge")
 check(v.target==Vector2(.2,0) and v.state=="to_crowd","refuge preserves admission state and final destination")
 c.cart_poses=[{"at":Vector2.ZERO,"heading":Vector2.RIGHT,"height":74.0}]
 v.pos=Vector2(-.5,0)
 check(c.visitor_clear(v,Vector2(.8,0)),"separate storey does not block guests")
 var cart:=Cart.new();f._porters=[cart];v.pos=Vector2(.9,0);f._visitors=[v]
 var step:={"at":Vector2(.25,0),"heading":Vector2.RIGHT,"turn":false,"reverse":false}
 check(not c.cart_clear(cart,step),"cart waits before moving into a guest")
 v.pos=Vector2(2,2)
 check(c.cart_clear(cart,step),"clear next edge resumes cart travel")
 v.pos=Vector2(.2,.4)
 check(not c.clear_entry(pose),"new hire cannot spawn a cart through an existing guest")
 cart.motion_step={"at":Vector2.ZERO,"heading":Vector2.DOWN,"turn":true,"reverse":false}
 c.begin_step();v.pos=Vector2(.9,.9)
 check(not c.visitor_clear(v,Vector2(.4,.4)),"visitor yields to the active turning sweep")
 v.cart_refuge_blockers=[{"p":cart,"from":Vector2(.9,.9),"to":Vector2(.4,.4)}]
 check(c.refuge_needed(v),"refuge waits for the actual obstructing turn")
 cart.motion_step={};cart.pos=Vector2(2,2);c.begin_step()
 check(not c.refuge_needed(v),"refuge releases when its obstructing sweep clears")
 f.free();print("Crowd cart failures: ",failures);quit(1 if failures else 0)
