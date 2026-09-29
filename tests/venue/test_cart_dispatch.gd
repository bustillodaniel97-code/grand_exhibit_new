extends SceneTree
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
func check(ok: bool,label: String) -> void:
 if not ok:failures+=1;printerr("FAIL: ",label)
func cart(at: Vector2,to: Vector2,heading: Vector2) -> RefCounted:
 var p:=Cart.new();p.pos=at;p.heading=heading;p.target=to;p.dock={"at":to,"heading":heading};return p
func _initialize() -> void:call_deferred("run")
func run() -> void:
 root.get_node("SaveSystem").set_process(false)
 var f:=Floor.new();root.add_child(f);f._porter_router.configure(f._porter_layout)
 var dispatch:=Dispatch.new();dispatch.configure(f)
 var a:=cart(Vector2(1,2),Vector2(7,2),Vector2.RIGHT)
 var b:=cart(Vector2(1,6),Vector2(7,6),Vector2.RIGHT)
 f._porters=[a,b];dispatch.enqueue(a);dispatch.enqueue(b)
 for i in 300:
  dispatch.advance(256,0)
  if dispatch.leases.size()==2:break
 check(dispatch.leases.size()==2,"separate corridors admit two simultaneous routes")
 check(a.pos==Vector2(1,2) and b.pos==Vector2(1,6),"planning never teleports actors")
 var disjoint:=true
 if dispatch.leases.size()==2:
  var occupied:=Snapshot.new();occupied.configure(f._porter_router,dispatch.leases[a])
  for pose in dispatch.leases[b]:disjoint=disjoint and occupied.clear_index(occupied.occupied,pose.at,pose.heading)
 check(disjoint,"parallel admissions reserve disjoint complete cart sweeps")
 var admitted_age:=int(dispatch.lease_data[a].sequence)
 check(dispatch.replan_blocked(a) and dispatch._find(a).sequence==admitted_age,
  "a stopped blocked edge releases its lease and preserves queue age")
 # If the winning request disappeared while a yielding cart was moving, a
 # blocked replan must restore the real work dock before it queues again.
 dispatch.configure(f)
 var original_dock:={"at":Vector2(7,6),"heading":Vector2.RIGHT}
 b.dock={"at":Vector2(2,6),"heading":Vector2.LEFT};b.target=b.dock.at;b.window=-1;b.state="yielding"
 dispatch.holds[b]={"winner":a,"state":"to_vault","arrived":false,"age":17,"dock":original_dock,"target":original_dock.at,"window":3}
 dispatch.leases[b]=[dispatch._pose(b.pos,b.heading)]
 dispatch.lease_data[b]={"poses":dispatch.leases[b],"offsets":[0],"released":0,"sequence":17}
 check(dispatch.replan_blocked(b),"a stopped yielding cart can request a replacement route")
 check(b.state=="to_vault" and b.dock==original_dock and b.target==original_dock.at and b.window==3,
  "a vanished winner restores the yielding cart's original work destination")
 check(not dispatch.holds.has(b) and int(dispatch._find(b).sequence)==17,
  "yield fallback clears its hold and preserves its admitted age")
 # When the winner still owns a future envelope, the replacement refuge request
 # must remain schedulable even though the yielding relationship stays active.
 dispatch.configure(f);b.state="yielding";b.motion_step={}
 var winner_request:={"p":a,"sequence":30,"tried":-1,"phase":"validate","intent":[],"refuge_for":null,"skip":[],"envelope_index":{}}
 dispatch.requests.append(winner_request)
 dispatch.holds[b]={"winner":a,"state":"to_vault","arrived":false,"age":17,"dock":original_dock,"target":original_dock.at,"window":3}
 dispatch.leases[b]=[dispatch._pose(b.pos,b.heading)]
 dispatch.lease_data[b]={"poses":dispatch.leases[b],"offsets":[0],"released":0,"sequence":17}
 check(dispatch.replan_blocked(b),"a yielding cart can replan while its winner remains queued")
 dispatch.advance(8,0)
 check((not dispatch.active.is_empty() and dispatch.active.p==b) or dispatch.leases.has(b),
  "a held cart's refuge replan is eligible for dispatcher work")
 # Opposing routes through a single-cart corridor have room to pull aside only
 # at the two ends. The waiting cart must leave the winner's route first.
 dispatch.configure(f);f._porter_layout.narrow=true;f._porter_router.configure(f._porter_layout)
 a=cart(Vector2(1,2.5),Vector2(7,2.5),Vector2.RIGHT)
 b=cart(Vector2(7,2.5),Vector2(1,2.5),Vector2.LEFT)
 f._porters=[a,b];dispatch.enqueue(a);dispatch.enqueue(b)
 var completed: Dictionary={};var overlaps:=0;var hold_seen:=false
 var unloading: Dictionary={}
 for tick in 12000:
  for p in unloading.keys():
   unloading[p]-=1
   if unloading[p]==0:p.state="idle";unloading.erase(p)
  dispatch.advance(512,0)
  if not dispatch.holds.is_empty():hold_seen=true
  for p in f._porters:
   if dispatch.leases.has(p) and p.route_cursor<p.route_steps.size():
    var step: Dictionary=p.route_steps[p.route_cursor]
    # Check every intermediate corner/translation against the other cart.
    var swept:=dispatch.sweep(p,[step])
    for other in f._porters:
     if other==p:continue
     for pose in swept:
      if Geometry.overlap(pose.at,pose.heading,other.pos,other.heading):overlaps+=1
    p.pos=step.at;p.heading=step.heading;p.route_cursor+=1
   if not completed.has(p) and p.state!="yielding" and p.pos==p.target and p.heading==p.dock.heading:
    completed[p]=true;p.state="deposit";unloading[p]=5
  if completed.size()==2:break
 check(hold_seen and dispatch.relocations>0,"a blocking cart is routed to a real reachable holding pose")
 check(overlaps==0,"opposing passage traffic clears all swept cart poses")
 if completed.size()!=2:
  for p in f._porters:printerr("UNIT_CART ",p.state," ",p.pos," target=",p.target," cursor=",p.route_cursor,"/",p.route_steps.size()," held=",dispatch.holds.has(p)," job=",p.route_job.status if p.route_job!=null else "none")
  for request in dispatch.requests:printerr("UNIT_REQUEST ",request.phase," tried=",request.tried," revision=",dispatch.revision," intent=",request.intent.size()," skips=",request.skip.size())
 check(completed.size()==2,"both loaded carts eventually complete after yielding")
 check(a.carried==3 and b.carried==3,"yielding never discards cargo")
 # A staffing refresh must restore the work state before rebuilding routes.
 dispatch.holds[b]={"winner":a,"state":"to_vault","arrived":false};b.state="yielding"
 dispatch.configure(f)
 check(b.state=="to_vault" and b.carried==3,"reconfiguration restores an interrupted loaded delivery")
 # An unfinished turn still owns its sweep when previous leases are discarded.
 b.pos=Vector2(4,4);b.heading=Vector2.RIGHT;b.motion_step={"at":b.pos,"heading":Vector2.DOWN,"turn":true,"reverse":false}
 var pending:=dispatch.occupancy(a)
 check(pending.size()==33,"unfinished motion is reserved even before a replacement route exists")
 var ramp:=Snapshot.new();ramp.configure(f._porter_router,[{"at":Vector2(3.25,4),"heading":Vector2.RIGHT,"height":5.0}])
 check(not ramp.clear_index(ramp.occupied,Vector2(3,4),Vector2.RIGHT),"nearby cart on a sloped surface is not ignored for a few pixels of height")
 var upstairs:=Snapshot.new();upstairs.configure(f._porter_router,[{"at":Vector2(3.25,4),"heading":Vector2.RIGHT,"height":74.0}])
 check(upstairs.clear_index(upstairs.occupied,Vector2(3,4),Vector2.RIGHT),"a genuinely separate storey does not block the ground route")
 var revision_before:=dispatch.revision
 dispatch.enqueue(a);dispatch.advance(8,0);dispatch.remove(a,true)
 check(dispatch._find(a).is_empty() and not dispatch.leases.has(a) and a.route_job==null,"removing staff releases pending work and reservations")
 check(dispatch.revision>revision_before,"removing even an unleased blocker wakes deferred routes")
 # A stale oldest failure remains eligible, but takes its next turn after
 # younger work that has not yet consumed an attempt.
 dispatch.configure(f);a.motion_step={};b.motion_step={}
 var impossible:={"p":a,"sequence":4,"schedule_ticket":dispatch._next_ticket(),"tried":-1,"phase":"route"}
 var solvable:={"p":b,"sequence":9,"schedule_ticket":dispatch._next_ticket(),"tried":-1,"phase":"route"}
 dispatch.requests=[impossible,solvable];dispatch._defer_stale_retry(impossible)
 check(dispatch._next_request()==solvable,
  "a repeatedly stale oldest route yields one scheduling turn to younger work")
 dispatch.requests=[impossible]
 check(dispatch._next_request()==impossible,
  "a lone stale route retries without requiring another occupancy revision")
 var repeated_newer: Array=[]
 for i in 20:
  repeated_newer.append({"p":b,"sequence":20+i,"schedule_ticket":dispatch._next_ticket(),"tried":-1,"phase":"route"})
 dispatch.requests=[impossible]+repeated_newer
 check(dispatch._next_request()==impossible,
  "repeated newer delivery requests cannot overtake an older eligible retry")
 # A winner failure releases every arrived courtesy hold and restores real work,
 # while an in-flight refuge keeps its sweep until it physically arrives.
 dispatch.configure(f);a.state="to_vault";a.dock=original_dock;a.target=original_dock.at;a.window=3
 b.state="yielding";b.motion_step={"at":Vector2(6.75,6),"heading":Vector2.LEFT,"turn":false,"reverse":false}
 dispatch.holds[b]={"winner":a,"state":"to_vault","arrived":false,"age":22,"dock":original_dock,"target":original_dock.at,"window":3}
 dispatch._release_winner_holds(a)
 check(dispatch.holds.has(b) and b.motion_step.at==Vector2(6.75,6),
  "winner failure preserves an in-flight refuge and its unfinished sweep")
 b.motion_step={};dispatch.holds[b].arrived=true;dispatch._release_winner_holds(a)
 check(not dispatch.holds.has(b) and b.state=="to_vault" and b.dock==original_dock and int(dispatch._find(b).sequence)==22,
  "an arrived loaded hold resumes its original dock with cargo age intact")
 var idle_hold:={"winner":a,"state":"collect","arrived":true,"age":23,"dock":original_dock,"target":original_dock.at,"window":2}
 dispatch.holds[b]=idle_hold;b.state="yielding";dispatch._release_winner_holds(a)
 check(b.state=="idle" and b.window==-1 and b.dispatch_standby and not dispatch.holds.has(b),
  "an arrived collection hold returns to safe standby without false cargo completion")
 var stale_refuge:={"p":b,"sequence":24,"schedule_ticket":dispatch._next_ticket(),"tried":-1,"phase":"refuge","intent":[],"skip":[],"snapshot_revision":dispatch.revision-1}
 dispatch.requests=[stale_refuge];dispatch.holds[b]={"winner":a,"state":"to_vault","arrived":false,"age":24}
 dispatch._defer_stale_retry(stale_refuge)
 check(stale_refuge.phase=="refuge_wait" and dispatch._next_request()==stale_refuge,
  "a stale refuge failure remains schedulable while its yielding hold is active")
 stale_refuge.skip=[a];stale_refuge.snapshot_revision=dispatch.revision-1;dispatch._check_intent(stale_refuge)
 check(stale_refuge.skip.is_empty(),"a material occupancy revision reconsiders previously failed blockers")
 # Pending corridor fairness orders only physically conflicting admissions.
 var old_index:=Snapshot.new();old_index.configure(f._porter_router,[{"at":Vector2(3,3),"heading":Vector2.RIGHT,"height":0.0}])
 var same_index:=Snapshot.new();same_index.configure(f._porter_router,[{"at":Vector2(3.25,3),"heading":Vector2.RIGHT,"height":0.0}])
 var apart_index:=Snapshot.new();apart_index.configure(f._porter_router,[{"at":Vector2(3,6),"heading":Vector2.RIGHT,"height":0.0}])
 var oldest:={"p":a,"sequence":40,"tried":-1,"phase":"route","refuge_for":null,"envelope":[{"at":Vector2(3,3),"heading":Vector2.RIGHT,"height":0.0}],"envelope_index":old_index.occupied}
 var newer:={"p":b,"sequence":41,"tried":-1,"phase":"validate","refuge_for":null,"envelope":[{"at":Vector2(3.25,3),"heading":Vector2.RIGHT,"height":0.0}],"envelope_index":same_index.occupied}
 dispatch.requests=[oldest,newer];dispatch.leases[a]=oldest.envelope
 check(dispatch._older_corridor_claim(newer),"newer work cannot jump an older overlapping corridor claim")
 newer.envelope=[{"at":Vector2(3,6),"heading":Vector2.RIGHT,"height":0.0}];newer.envelope_index=apart_index.occupied
 check(not dispatch._older_corridor_claim(newer),"an independent aisle remains concurrently admissible")
 newer.envelope=[{"at":Vector2(3.25,3),"heading":Vector2.RIGHT,"height":0.0}];newer.envelope_index=same_index.occupied;newer.refuge_for=a
 check(not dispatch._older_corridor_claim(newer),"courtesy refuge work can bypass the winner it must unblock")
 newer.refuge_for=null;oldest.tried=dispatch.revision;dispatch.leases.clear()
 check(not dispatch._older_corridor_claim(newer),"a definitively failed old intent cannot freeze all later traffic")
 oldest.tried=-1
 var newest:=newer.duplicate();newest.sequence=99
 dispatch.requests=[oldest,newest]
 check(dispatch._older_corridor_claim(newest),"repeated new arrivals retain the oldest conflicting corridor order")
 # Exercise the actual admission phase, including a dynamic route whose step
 # order differs from its original static intent.
 dispatch.configure(f);a.pos=Vector2(3,3);a.heading=Vector2.RIGHT;a.motion_step={};a.route_steps=[]
 var turn_steps: Array=[{"at":Vector2(3,3),"heading":Vector2.DOWN,"turn":true,"reverse":false}]
 var wrong_static_offsets: Array=[0,4]
 var dynamic_request:={"p":a,"sequence":50,"phase":"route","refuge_for":null,"intent":[],"envelope":oldest.envelope,"envelope_offsets":wrong_static_offsets,"tried":-1}
 dispatch.requests=[dynamic_request];dispatch._admit(dynamic_request,turn_steps)
 check(dispatch.lease_data[a].offsets==[0,32],"dynamic admission rebuilds offsets from its actual turn steps")
 dispatch.configure(f);dispatch.requests=[oldest,newer];newer.refuge_for=null
 dispatch._begin_corridor_check(newer,[],newer.envelope,newer.envelope_index,[0])
 while not dispatch.active.is_empty():dispatch._advance_corridor_check(newer,1)
 check(not dispatch.leases.has(b) and newer.tried==dispatch.revision,
  "actual admission defers a younger conflicting dynamic sweep")
 dispatch.configure(f);dispatch.requests=[oldest,newer]
 newer.envelope=[{"at":Vector2(3,6),"heading":Vector2.RIGHT,"height":0.0}];newer.envelope_index=apart_index.occupied
 dispatch._begin_corridor_check(newer,[],newer.envelope,newer.envelope_index,[0])
 while not dispatch.active.is_empty():dispatch._advance_corridor_check(newer,1)
 check(dispatch.leases.has(b),"actual admission accepts a younger disjoint sweep")
 dispatch.configure(f);b.state="yielding";b.motion_step={}
 var changed_refuge:={"p":b,"sequence":60,"schedule_ticket":dispatch._next_ticket(),"tried":-1,"phase":"corridor","refuge_for":a,"corridor_revision":dispatch.revision-1,"corridor_claims":[],"corridor_claim":0,"corridor_pose":0,"admission_steps":[],"admission_envelope":[],"admission_index":{},"admission_offsets":[0],"avoid_index":{}}
 dispatch.requests=[changed_refuge]
 dispatch._begin_corridor_check(changed_refuge,[],[],{},[0])
 dispatch.remove(a,true) # Actual cart occupancy revision after check initialization.
 dispatch.holds[b]={"winner":a,"state":"to_vault","arrived":false,"age":60,"dock":original_dock,"target":original_dock.at,"window":3}
 dispatch._advance_corridor_check(changed_refuge,1)
 check(changed_refuge.phase=="refuge_wait" and dispatch._next_request()==changed_refuge,
  "a revision during actual refuge admission returns the held helper to eligible refuge work")
 # Unrelated crowd revisions can make every failed winner result stale. Arrived
 # courtesy holds must still resume; unfinished refuge sweeps remain protected.
 dispatch.configure(f);a.state="to_vault";b.state="yielding";b.motion_step={}
 var moving:=cart(Vector2(6,6),Vector2(7,6),Vector2.RIGHT);moving.state="yielding";moving.motion_step={"at":Vector2(6.25,6),"heading":Vector2.RIGHT,"turn":false,"reverse":false};f._porters=[a,b,moving]
 dispatch.holds[b]={"winner":a,"state":"to_vault","arrived":true,"age":70,"dock":original_dock,"target":original_dock.at,"window":3}
 dispatch.holds[moving]={"winner":a,"state":"to_vault","arrived":false,"age":71,"dock":original_dock,"target":original_dock.at,"window":4}
 var stale_winner:={"p":a,"sequence":69,"schedule_ticket":dispatch._next_ticket(),"tried":-1,"phase":"route","snapshot_revision":dispatch.revision-1}
 for changed_revision in 3:
  dispatch.revision+=1;dispatch._handle_stale_failure(stale_winner)
 check(not dispatch.holds.has(b) and b.state=="to_vault" and int(dispatch._find(b).sequence)==70,
  "repeated stale winner failures resume an arrived hold with original work age")
 check(dispatch.holds.has(moving) and moving.motion_step.at==Vector2(6.25,6),
  "stale winner failure preserves an in-flight refuge sweep")
 # An admitted long winner no longer needs an arrived cart to remain idle: its
 # remaining lease is sufficient to reject any conflicting resumed route.
 dispatch.configure(f);f._porters=[a,b];a.motion_step={"at":Vector2(4.25,4),"heading":Vector2.RIGHT,"turn":false,"reverse":false};a.route_steps=[a.motion_step,{"at":Vector2(5,4),"heading":Vector2.RIGHT,"turn":false,"reverse":false}];a.route_cursor=0
 var winner_poses: Array=[{"at":Vector2(4,4),"heading":Vector2.RIGHT,"height":0.0},{"at":Vector2(4.25,4),"heading":Vector2.RIGHT,"height":0.0},{"at":Vector2(5,4),"heading":Vector2.RIGHT,"height":0.0}]
 dispatch.leases[a]=winner_poses;dispatch.lease_data[a]={"poses":winner_poses,"offsets":[0,1,2],"released":0,"sequence":80}
 b.state="yielding";b.motion_step={};b.carried=3
 dispatch.holds[b]={"winner":a,"state":"to_vault","arrived":true,"age":79,"dock":original_dock,"target":original_dock.at,"window":3}
 dispatch._release_finished()
 check(not dispatch.holds.has(b) and dispatch._find(b).sequence==79 and dispatch.leases.has(a),
  "an arrived hold resumes before its admitted long winner finishes")
 check(b.carried==3 and dispatch.leases[a]==winner_poses,"early resume preserves cargo and the winner's complete remaining lease")
 var remaining:=Snapshot.new();remaining.configure(f._porter_router,winner_poses)
 check(not remaining.clear_index(remaining.occupied,Vector2(4.25,4),Vector2.RIGHT),
  "the active winner lease still blocks a conflicting resumed cart pose")
 check(remaining.clear_index(remaining.occupied,Vector2(4,6),Vector2.RIGHT),
  "the resumed cart may use a disjoint aisle while the winner remains active")
 f.free();print("Cart dispatch failures: ",failures);quit(1 if failures else 0)
