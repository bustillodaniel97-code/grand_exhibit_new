extends SceneTree
const Dispatch:=preload("res://tools/cart_dispatch_telemetry.gd")
class Layout extends RefCounted:
 func _height_at(_at: Vector2)->float:return 0.0
class Crowd extends RefCounted:
 var points: Array=[]
 func planning_obstacles()->Array:return points
class Porter extends RefCounted:
 var motion_step: Dictionary={};var state:="to_window";var pos:=Vector2.ZERO;var heading:=Vector2.RIGHT
 var route_job: RefCounted=null;var route_steps:Array=[];var route_cursor:=0
class Floor extends Node:
 var _porters:Array=[];var _porter_layout:=Layout.new();var _crowd_traffic:=Crowd.new();var _porter_router: RefCounted
func pose(at:Vector2)->Dictionary:return {"at":at,"heading":Vector2.RIGHT,"height":0.0}
func check(ok:bool,label:String,fail:Array)->void:
 if not ok:fail.append(label);push_error(label)
func _initialize()->void:
 var fail:Array=[];var floor:=Floor.new();var d:=Dispatch.new();d.floor_node=floor
 var waiter:=Porter.new();var owner:=Porter.new();floor._porters=[waiter,owner]
 d.requests=[{"p":waiter,"sequence":7,"schedule_ticket":1,"tried":-1,"phase":"route","intent":[1],"refuge_for":null,"skip":[],"lease_candidate":{"pose":pose(Vector2.ZERO)}}]
 d.leases[owner]=[pose(Vector2.ZERO),pose(Vector2(4,0))];d.lease_data[owner]={"offsets":[0,1],"released":0,"sequence":2}
 var request:Dictionary=d.requests[0]
 check(d._defer_for_lease(request),"lease blocker defers",fail);check(int(request.sequence)==7,"age preserved",fail)
 d.revision+=5;check(d._lease_region_blocked(request),"unrelated revision does not wake",fail);check(d._next_request().is_empty(),"blocked request not selected",fail)
 d.lease_data[owner].released=1
 check(not d._lease_region_blocked(request),"relevant prefix release wakes",fail);check(d._next_request()==request,"woken request retries",fail)
 floor._crowd_traffic.points=[{"at":Vector2.ZERO,"radius":.22,"height":0.0}]
 check(d._has_nonlease_blocker(request,pose(Vector2.ZERO)),"new guest classified",fail)
 d.lease_data[owner].released=0
 check(not d._lease_blockers(request,pose(Vector2.ZERO)).is_empty() and d._has_nonlease_blocker(request,pose(Vector2.ZERO)),"mixed blockers classified",fail)
 d.leases.erase(owner);d.lease_data.erase(owner);owner.pos=Vector2.ZERO
 floor._crowd_traffic.points=[];check(d._has_nonlease_blocker(request,pose(Vector2.ZERO)),"stationary cart classified",fail)
 print("Cart lease deferral failures: ",fail.size());quit(fail.size())
