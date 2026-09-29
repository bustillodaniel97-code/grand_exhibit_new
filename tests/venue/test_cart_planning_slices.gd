extends SceneTree
const SweepJob:=preload("res://scenes/venue/floor/cart_sweep_job.gd")
const Snapshot:=preload("res://scenes/venue/floor/cart_dispatch_geometry.gd")
const Router:=preload("res://scenes/venue/floor/porter_router.gd")
class Layout extends RefCounted:
 func _height_at(_at: Vector2)->float:return 0.0
 func fits(_at: Vector2,_heading: Vector2,_claims: bool=false)->bool:return true
class Floor extends Node:
 var _porter_layout:=Layout.new()
class Cart extends RefCounted:
 var pos:=Vector2.ZERO
 var heading:=Vector2.RIGHT
 var motion_step: Dictionary={}
 var turn_progress:=0.0
var failures:=0
func check(ok: bool,label: String)->void:
 if not ok:failures+=1;printerr("FAIL: ",label)
func _initialize()->void:
 root.get_node("SaveSystem").set_process(false)
 var floor_node:=Floor.new();root.add_child(floor_node)
 var cart:=Cart.new();var steps: Array=[]
 for i in 512:steps.append({"at":Vector2((i+1)*.25,0),"heading":Vector2.RIGHT,"turn":false,"reverse":false})
 var builder:=SweepJob.new();builder.begin(floor_node,cart,steps);builder.advance(7,0)
 check(builder.last_operations==7 and builder.status=="building","large envelope yields at its operation slice")
 while builder.status=="building":builder.advance(31,0)
 check(builder.poses.size()==2049 and builder.offsets.size()==513,"sliced envelope preserves every translation sample and offset")
 var router:=Router.new();router.configure(floor_node._porter_layout)
 var snapshot:=Snapshot.new();snapshot.begin_configure(router,[builder.poses])
 var inserted:=snapshot.advance_setup(13,0)
 check(inserted==13 and snapshot.setup_pending,"large spatial index yields at its operation slice")
 while snapshot.setup_pending:snapshot.advance_setup(29,0)
 var indexed:=0
 for bucket in snapshot.occupied.values():indexed+=(bucket as Array).size()
 check(indexed==builder.poses.size(),"sliced index retains the complete collision envelope")
 var people: Array=[{"at":Vector2(.67,0),"radius":.22,"height":0.0}]
 var point_snapshot:=Snapshot.new();point_snapshot.begin_configure(router,[],[],[people])
 check(point_snapshot.advance_setup(1,0)==1 and point_snapshot.setup_pending,
  "point obstacle insertion obeys the operation slice")
 point_snapshot.advance_setup(1,0)
 check(not point_snapshot.setup_pending,"point obstacle setup finishes after its bounded slice")
 check(not point_snapshot.fits(point_snapshot.key(Vector2.ZERO,Vector2.RIGHT)),
  "stationary person inside the cart nose blocks a planned pose")
 var upstairs:=Snapshot.new();upstairs.begin_configure(router,[],[],[[{"at":Vector2(.67,0),"radius":.22,"height":74.0}]])
 while upstairs.setup_pending:upstairs.advance_setup(1,0)
 check(upstairs.fits(upstairs.key(Vector2.ZERO,Vector2.RIGHT)),
  "point obstacles on a separate storey preserve the 73px clearance surface")
 floor_node.free();print("Cart planning slice failures: ",failures);quit(1 if failures else 0)
