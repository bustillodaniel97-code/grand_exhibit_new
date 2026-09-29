extends SceneTree
const Dispatch:=preload("res://scenes/venue/floor/cart_dispatch.gd")
const Crowd:=preload("res://scenes/venue/floor/crowd_traffic.gd")
class Layout extends RefCounted:
 func _height_at(_at:Vector2)->float:return 0.0
class Router extends RefCounted:
 var layout:=Layout.new()
class Guest extends RefCounted:
 var pos:=Vector2(20,20)
 var cart_wait:=0.0
 var node:Node2D
class Cart extends RefCounted:
 var pos:=Vector2.ZERO
 var heading:=Vector2.RIGHT
 var motion_step:Dictionary={}
 var turn_progress:=0.0
 var route_steps:Array=[]
 var route_cursor:=0
 var route_job:Variant=null
class Actor extends Node2D:
 var walking:=false
class Floor extends Node:
 var _porters:Array=[]
 var _visitors:Array=[]
 var _rejected:Array=[]
 var _cart_dispatch:RefCounted
 var _porter_layout:=Layout.new()
 var _porter_router:=Router.new()
 func _nav_id(at:Vector2)->Vector2i:return Vector2i((at*4).round())
var checks:=0
var failures:=0
func check(ok:bool,label:String)->void:
 checks+=1
 if not ok:failures+=1;printerr("FAIL: ",label)
func _initialize()->void:call_deferred("run")
func run()->void:
 root.get_node("SaveSystem").set_process(false)
 var f:=Floor.new();root.add_child(f);var crowd:=Crowd.new();crowd.configure(f)
 var guest:=Guest.new();guest.node=Actor.new();f.add_child(guest.node);f._visitors=[guest]
 for scenario in ["visitor_churn","cart_change","older_overlap","claim_created","claim_removed","claim_reordered","claim_geometry","claim_expires","claim_revives"]:
  var d:=Dispatch.new();d.configure(f);f._cart_dispatch=d
  var p:=Cart.new();var old:=Cart.new();old.pos=Vector2(10,10);f._porters=[p,old]
  var pose:={"at":Vector2.ZERO,"heading":Vector2.RIGHT,"height":0.0};var envelope:Array=[]
  for ignored in 96:envelope.append(pose)
  var old_at:=Vector2.ZERO if scenario=="older_overlap" else Vector2(10,10)
  var old_pose:={"at":old_at,"heading":Vector2.RIGHT,"height":0.0};var cell:=Vector2i(old_at)
  var older:={"p":old,"sequence":1,"refuge_for":null,"tried":-1,"envelope":[old_pose],"envelope_index":{cell:[old_pose]}}
  var request:={"p":p,"sequence":2,"refuge_for":null,"tried":-1,"phase":"validate"};d.requests=[older,request]
  if scenario=="claim_revives":older.tried=d.revision
  d._begin_corridor_check(request,[],envelope,{},[0])
  var started:int=d.revision
  for tick in 100:
   if d.active.is_empty():break
   guest.pos.x+=.25;crowd.refresh_obstacles(.6)
   if tick==2:
    match scenario:
     "cart_change":d.remove(old,true)
     "claim_created":
      var additional:Dictionary=older.duplicate();additional.p=Cart.new();additional.sequence=0;d.requests.push_front(additional)
     "claim_removed":d.requests.erase(older)
     "claim_reordered":older.schedule_ticket=999
     "claim_geometry":older.claim_generation=99;older.envelope_index={Vector2i.ZERO:[pose]}
     "claim_expires":older.tried=d.revision
   d._advance_corridor_check(request,1)
  if scenario=="visitor_churn":
   check(d.revision>started+90,"actual visitor refresh changes broad revision repeatedly")
   check(d.leases.has(p),"clear corridor completes despite visitor-only snapshot churn")
   guest.pos=Vector2(.9,0)
   check(not crowd.cart_clear(p,{"at":Vector2(.25,0),"heading":Vector2.RIGHT,"turn":false,"reverse":false}),"new visitor still blocks actual cart edge after admission")
  else:check(not d.leases.has(p),scenario+" still rejects admission")
 f.free();print("CART_CORRIDOR_DEPENDENCIES checks=",checks," failures=",failures);quit(1 if failures else 0)
