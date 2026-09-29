extends "res://scenes/venue/floor/cart_dispatch.gd"
## QA-only event-counting subclass; production behavior is copied verbatim below.
var telemetry: Dictionary={"validate_obstacle":0,"blocker_sets":{},"corridor_revision_stale":0,"corridor_older_claim":0,"alternate_cap":0,"failed_stale":0,"failed_route_current":0,"failed_intent":0,"failed_refuge":0,"admission_sweep":0,"intent_envelope_sweep":0,"planner_operations":0,"sweep_operations":0,"lease_deferrals":0,"lease_wakes":0}
func _lease_blockers(request: Dictionary,pose: Dictionary) -> Array:
 var owners: Array=[];var height: float=floor_node._porter_layout._height_at(pose.at)
 for owner in leases:
  if owner==request.p:continue
  var data: Dictionary=lease_data.get(owner,{})
  var released:=int(data.get("released",0));var offsets: Array=data.get("offsets",[0]);var start:=int(offsets[mini(released,offsets.size()-1)])
  for occupied in leases[owner].slice(start):
   if absf(height-float(occupied.height))<73.0 and Geometry.overlap(pose.at,pose.heading,occupied.at,occupied.heading,.025):owners.append(owner);break
 return owners
func _lease_region_blocked(request: Dictionary) -> bool:
 if not request.has("lease_defer"):return false
 var defer: Dictionary=request.lease_defer
 for owner in defer.owners:
  if leases.has(owner) and owner in _lease_blockers(request,defer.pose):return true
 request.erase("lease_defer");request.erase("lease_candidate");telemetry.lease_wakes+=1;return false
func _defer_for_lease(request: Dictionary) -> bool:
 if OS.get_environment("CART_LEASE_DEFER_QA")=="0":return false
 if not request.has("lease_candidate"):return false
 var candidate: Dictionary=request.lease_candidate;var owners:=_lease_blockers(request,candidate.pose)
 if owners.is_empty():request.erase("lease_candidate");return false
 request.lease_defer={"owners":owners,"pose":candidate.pose};request.tried=-1;active={};telemetry.lease_deferrals+=1;return true
func _blocker_set(request: Dictionary,pose: Dictionary) -> Array:
 var found: Array=[];var at: Vector2=pose.at;var heading: Vector2=pose.heading;var height: float=floor_node._porter_layout._height_at(at)
 for owner in leases:
  if owner==request.p:continue
  var start:=int(lease_data.get(owner,{}).get("offsets",[0])[int(lease_data.get(owner,{}).get("released",0))]) if lease_data.has(owner) else 0
  for occupied in leases[owner].slice(start):
   if absf(height-float(occupied.height))<73.0 and Geometry.overlap(at,heading,occupied.at,occupied.heading,.025):found.append("lease");break
 for other in floor_node._porters:
  if other==request.p or leases.has(other) or other.state=="awaiting_entry":continue
  var poses: Array=sweep(other,[other.motion_step]) if not other.motion_step.is_empty() else [_pose(other.pos,Geometry.heading(other))]
  for occupied in poses:
   if absf(height-float(occupied.height))<73.0 and Geometry.overlap(at,heading,occupied.at,occupied.heading,.025):found.append("cart");break
 var groups:=point_obstacle_groups()
 if not groups.is_empty():
  for point in groups[0]:
   if absf(height-float(point.height))<73.0 and Geometry.point_distance(point.at,at,heading)<float(point.radius)+.025:found.append("guest");break
 found.sort();return found
func configure(owner: Node) -> void:
 for p in holds:
  p.state=holds[p].state
 for request in requests:
  if request.p.route_job!=null:request.p.route_job.cancel();request.p.route_job=null
 floor_node=owner;requests=[];leases.clear();lease_data.clear();holds.clear();active={};eligibility.clear();schedule_ticket=0;revision+=1
func spawn_pose(p: Variant,dock: Dictionary) -> Dictionary:
 var poses: Array=[]
 for other in floor_node._porters:
  if other==p or not other.staged:continue
  poses.append(_pose(other.pos,Geometry.heading(other)))
  if not other.motion_step.is_empty():poses.append_array(sweep(other,[other.motion_step]))
 var geometry:=Snapshot.new();geometry.configure(floor_node._porter_router,poses)
 var room: Rect2=floor_node._theme.role("store").rect
 var candidates: Array=[dock]+floor_node._porter_layout.around(dock.at,dock.heading,12)
 for candidate in candidates:
  if not room.has_point(candidate.at):continue
  if geometry.fits(geometry.key(candidate.at,candidate.heading)):return candidate
 return {}

func _find(p: Variant) -> Dictionary:
 for request in requests:
  if request.p==p:return request
 return {}
func claims_collection(p: Variant) -> bool:
 return p.state in ["to_window","collect"] or (holds.has(p) and holds[p].state in ["to_window","collect"])

func remove(p: Variant,departure: bool=false) -> void:
 var existing:=_find(p)
 if not existing.is_empty():requests.erase(existing)
 if not active.is_empty() and active.p==p:active={}
 if p.route_job!=null:p.route_job.cancel();p.route_job=null
 if leases.has(p):leases.erase(p);lease_data.erase(p);revision+=1
 elif departure:revision+=1
 if holds.has(p) and p.state=="yielding":p.state=holds[p].state
 holds.erase(p)
func enqueue(p: Variant,age: int=-1) -> void:
 remove(p);sequence+=1
 p.route_steps=[];p.route_cursor=0
 requests.append({"p":p,"sequence":sequence if age<0 else age,"schedule_ticket":_next_ticket(),"tried":-1,"phase":"route","intent":[],"refuge_for":null,"skip":[]})
func _next_ticket() -> int:
 schedule_ticket+=1;return schedule_ticket
func replan_blocked(p: Variant) -> bool:
 if not leases.has(p) or not p.motion_step.is_empty():return false
 var age:=int(lease_data.get(p,{}).get("sequence",sequence+1))
 leases.erase(p);lease_data.erase(p);p.route_steps=[];p.route_cursor=0;p.route_job=null;revision+=1
 if holds.has(p):
  var hold: Dictionary=holds[p];var winner: Dictionary=_find(hold.winner)
  if not winner.is_empty() and winner.has("envelope_index"):
   requests.append({"p":p,"sequence":age,"schedule_ticket":_next_ticket(),"tried":-1,"phase":"refuge_wait","intent":[],"refuge_for":hold.winner,"skip":[],"saved_age":hold.age,"saved_state":hold.state,"saved_dock":hold.get("dock",p.dock),"saved_target":hold.get("target",p.target),"saved_window":hold.get("window",p.window),"avoid_index":winner.envelope_index})
   return true
  p.state=hold.state;p.dock=hold.get("dock",p.dock);p.target=hold.get("target",p.target);p.window=int(hold.get("window",p.window));holds.erase(p)
 enqueue(p,age);return true
func _pose(at: Vector2,heading: Vector2) -> Dictionary:
 return {"at":at,"heading":heading,"height":floor_node._porter_layout._height_at(at)}
func sweep(p: Variant,steps: Array) -> Array:
 var out: Array=[_pose(p.pos,Geometry.heading(p))]
 var at: Vector2=p.pos;var heading:=Geometry.heading(p)
 for step in steps:
  if step.turn:
   var angle:=heading.angle_to(step.heading)
   for i in range(1,33):out.append(_pose(at,heading.rotated(angle*i/32.0)))
  else:
   for i in range(1,5):out.append(_pose(at.lerp(step.at,i/4.0),heading))
  at=step.at;heading=step.heading
 return out
func occupancy(p: Variant) -> Array:
 var out: Array=[]
 for other in floor_node._porters:
  if other==p or other.state=="awaiting_entry":continue
  if leases.has(other):out.append_array(leases[other])
  elif not other.motion_step.is_empty():out.append_array(sweep(other,[other.motion_step]))
  else:out.append(_pose(other.pos,Geometry.heading(other)))
 return out
func occupancy_groups(p: Variant) -> Array:
 var groups: Array=[]
 for other in floor_node._porters:
  if other==p or other.state=="awaiting_entry":continue
  if leases.has(other):
   var start:=int(lease_data[other].offsets[lease_data[other].released]) if lease_data.has(other) else 0
   groups.append({"poses":leases[other],"start":start})
  elif not other.motion_step.is_empty():groups.append(sweep(other,[other.motion_step]))
  else:groups.append([_pose(other.pos,Geometry.heading(other))])
 return groups
func point_obstacle_groups() -> Array:
 for property in floor_node.get_property_list():
  if str(property.name)!="_crowd_traffic":continue
  var crowd: Variant=floor_node.get("_crowd_traffic")
  if crowd!=null and crowd.has_method("planning_obstacles"):return [crowd.planning_obstacles()]
  break
 return []
func _geometry(p: Variant,avoid: Array=[]) -> RefCounted:
 var geometry:=Snapshot.new();geometry.configure(floor_node._porter_router,occupancy(p),avoid);geometry.origin=p.pos
 return geometry
func _start(request: Dictionary,phase: String,geometry: RefCounted) -> void:
 var p: Variant=request.p
 request.phase=phase;request.snapshot_revision=revision;active=request
 p.route_job=Job.new()
 p.route_job.begin(geometry,p.pos,p.heading,p.pos if phase=="refuge" else p.dock.at,p.heading if phase=="refuge" else p.dock.heading,phase=="refuge")
func _release_finished() -> void:
 # Release traversed space while the cart continues down its route. Keep the
 # complete current edge (including its starting pose) until it has finished.
 for p in leases.keys():
  if not lease_data.has(p):continue
  var data: Dictionary=lease_data[p]
  if p.route_cursor>=int(data.released)+4 and p.route_cursor<data.offsets.size():
   data.released=p.route_cursor
   revision+=1
 for p in leases.keys():
  if not p.motion_step.is_empty() or p.route_cursor<p.route_steps.size():continue
  leases.erase(p);lease_data.erase(p);revision+=1
  if holds.has(p):
   var hold: Dictionary=holds[p]
   hold.arrived=true
   p.route_steps=[];p.route_cursor=0;p.node.walking=false
 for p in holds.keys():
  var hold: Dictionary=holds[p]
  if not hold.arrived:continue
  var winner: Variant=hold.winner
  # Once the winner is admitted, its remaining sweep is authoritative. The
  # resumed cart may plan immediately but cannot enter that reserved space.
  if not leases.has(winner) and not _find(winner).is_empty():continue
  _resume_hold(p,hold)
func _resume_hold(p: Variant,hold: Dictionary) -> void:
 holds.erase(p)
 if hold.state in ["idle","collect"]:
  p.state="idle";p.window=-1;p.dispatch_standby=true
  p.dock={"at":p.pos,"heading":p.heading};p.target=p.pos
 else:
  p.state=hold.state;p.dock=hold.get("dock",p.dock);p.target=hold.get("target",p.target);p.window=int(hold.get("window",p.window))
  enqueue(p,int(hold.age))
func _release_winner_holds(winner: Variant) -> void:
 for held in holds.keys():
  var hold: Dictionary=holds[held]
  if hold.winner==winner and hold.arrived:_resume_hold(held,hold)
func _admit(request: Dictionary,steps: Array) -> void:
 var p: Variant=request.p
 p.route_steps=steps.duplicate();p.route_cursor=0;p.route_job=null
 var admitted_envelope: Array
 if request.has("admission_envelope"):admitted_envelope=request.admission_envelope
 elif request.phase=="validate":admitted_envelope=request.envelope
 else:admitted_envelope=sweep(p,steps)
 leases[p]=admitted_envelope
 var offsets: Array=request.get("admission_offsets",request.get("envelope_offsets",[]) if request.phase=="validate" else [])
 if offsets.is_empty():
  offsets=[0];var cursor:=0
  for step in steps:
   cursor+=32 if step.turn else 4;offsets.append(cursor)
 lease_data[p]={"poses":leases[p],"offsets":offsets,"released":0,"sequence":int(request.sequence)}
 requests.erase(request);active={}
 revision+=1;grants+=1;peak_concurrent=maxi(peak_concurrent,leases.size())
 if request.refuge_for!=null:
  holds[p]={"winner":request.refuge_for,"state":request.saved_state,"arrived":false,"age":int(request.get("saved_age",request.sequence)),"dock":request.get("saved_dock",p.dock),"target":request.get("saved_target",p.target),"window":int(request.get("saved_window",p.window))}
  p.state="yielding";relocations+=1
func _try_relocation(request: Dictionary) -> bool:
 if request.intent.is_empty():return false
 var p: Variant=request.p
 var future: Array=request.get("envelope",[])
 if future.is_empty():future=sweep(p,request.intent)
 var path:=Snapshot.new()
 if request.has("envelope_index"):path.use_indexes(floor_node._porter_router,{},request.envelope_index)
 else:path.configure(floor_node._porter_router,[],future)
 for other in floor_node._porters:
  if other==p or other.state=="awaiting_entry" or leases.has(other) or holds.has(other) or other in request.skip:continue
  if not other.motion_step.is_empty() or other.state=="deposit":continue
  if path.clear_index(path.avoid_end,other.pos,Geometry.heading(other),.06):continue
  var existing:=_find(other)
  if not existing.is_empty():requests.erase(existing)
  var helper:={"p":other,"sequence":request.sequence,"schedule_ticket":_next_ticket(),"tried":-1,"phase":"refuge","intent":[],"refuge_for":p,"skip":[],"saved_age":int(existing.get("sequence",sequence+1)),"saved_state":other.state,"saved_dock":other.dock,"saved_target":other.target,"saved_window":other.window}
  requests.push_front(helper)
  holds[other]={"winner":p,"state":other.state,"arrived":false,"age":helper.saved_age,"dock":other.dock,"target":other.target,"window":other.window}
  other.state="yielding"
  helper.phase="snapshot_refuge";helper.geometry=Snapshot.new()
  helper.geometry.begin_configure(floor_node._porter_router,occupancy_groups(other),[],point_obstacle_groups())
  helper.avoid_index=request.get("envelope_index",path.avoid_end);active=helper
  return true
 return false
func _check_intent(request: Dictionary) -> void:
 if request.has("snapshot_revision") and int(request.snapshot_revision)!=revision:request.skip=[]
 request.tried=revision;request.snapshot_revision=revision
 if not request.has("envelope"):
  request.phase="envelope";request.sweep_job=SweepJob.new();request.sweep_job.begin(floor_node,request.p,request.intent);active=request;return
 _begin_validation_snapshot(request)
func _begin_validation_snapshot(request: Dictionary) -> void:
 request.phase="snapshot_validate";request.geometry=Snapshot.new()
 request.geometry.begin_configure(floor_node._porter_router,occupancy_groups(request.p),[],point_obstacle_groups());active=request
func _begin_refuge_snapshot(request: Dictionary) -> void:
 request.phase="snapshot_refuge";request.geometry=Snapshot.new()
 request.geometry.begin_configure(floor_node._porter_router,occupancy_groups(request.p),[],point_obstacle_groups());active=request
func _finish_envelope(request: Dictionary) -> void:
 telemetry.intent_envelope_sweep+=1
 var builder: RefCounted=request.sweep_job
 request.envelope=builder.poses;request.envelope_index=builder.index;request.envelope_offsets=builder.offsets
 request.erase("sweep_job");_begin_validation_snapshot(request)

func _validate_pose(request: Dictionary) -> void:
 var geometry: RefCounted=request.geometry
 var pose: Dictionary=request.envelope[request.check_cursor]
 if not geometry.clear_index(geometry.occupied,pose.at,pose.heading):
  telemetry.validate_obstacle+=1
  var label:="+".join(_blocker_set(request,pose));if label.is_empty():label="static_or_unknown"
  telemetry.blocker_sets[label]=int(telemetry.blocker_sets.get(label,0))+1
  if label=="lease":request.lease_candidate={"pose":pose}
  else:request.erase("lease_candidate")
  active={}
  if not _try_relocation(request):
   request.alternate=not leases.is_empty();_start(request,"route",geometry)
  return
 request.check_cursor+=1
 if request.check_cursor>=request.envelope.size():
  _begin_corridor_check(request,request.intent,request.envelope,request.envelope_index,request.envelope_offsets)
func _eligible_older_claims(request: Dictionary) -> Array:
 var claims: Array=[]
 if request.refuge_for!=null:return claims
 for older in requests:
  if older==request or older.refuge_for!=null or int(older.sequence)>=int(request.sequence):continue
  if not older.has("envelope") or not older.has("envelope_index"):continue
  if int(older.tried)==revision and leases.is_empty():continue
  claims.append(older)
 return claims
func _begin_corridor_check(request: Dictionary,steps: Array,envelope: Array,index: Dictionary,offsets: Array) -> void:
 request.phase="corridor";request.admission_steps=steps.duplicate();request.admission_envelope=envelope;request.admission_index=index;request.admission_offsets=offsets
 request.corridor_claims=_eligible_older_claims(request);request.corridor_claim=0;request.corridor_pose=0;request.corridor_revision=revision;active=request
func _finish_corridor_check(request: Dictionary,blocked: bool) -> void:
 if blocked:
  request.phase="refuge_wait" if request.refuge_for!=null else "route"
  request.tried=-1 if request.refuge_for!=null else revision;active={}
  request.erase("admission_steps");request.erase("admission_envelope");request.erase("admission_index");request.erase("admission_offsets")
 else:_admit(request,request.admission_steps)
func _advance_corridor_check(request: Dictionary,max_operations: int) -> int:
 if int(request.corridor_revision)!=revision:telemetry.corridor_revision_stale+=1;_finish_corridor_check(request,true);return 1
 var operations:=0
 while operations<max_operations:
  if request.corridor_claim>=request.corridor_claims.size():_finish_corridor_check(request,false);break
  var older: Dictionary=request.corridor_claims[request.corridor_claim]
  if request.corridor_pose>=request.admission_envelope.size():request.corridor_claim+=1;request.corridor_pose=0;continue
  var geometry:=Snapshot.new();geometry.use_indexes(floor_node._porter_router,older.envelope_index)
  var pose: Dictionary=request.admission_envelope[request.corridor_pose];request.corridor_pose+=1;operations+=1
  if not geometry.clear_index(geometry.occupied,pose.at,pose.heading):telemetry.corridor_older_claim+=1;_finish_corridor_check(request,true);break
 return operations
func _envelopes_overlap(a: Dictionary,b: Dictionary) -> bool:
 var first: Dictionary=a;var second: Dictionary=b
 if a.envelope.size()>b.envelope.size():first=b;second=a
 var geometry:=Snapshot.new();geometry.use_indexes(floor_node._porter_router,second.envelope_index)
 for pose in first.envelope:
  if not geometry.clear_index(geometry.occupied,pose.at,pose.heading):return true
 return false
func _older_corridor_claim(request: Dictionary) -> bool:
 if request.refuge_for!=null:return false
 for older in requests:
  if older==request or older.refuge_for!=null or int(older.sequence)>=int(request.sequence):continue
  if not older.has("envelope") or not older.has("envelope_index"):continue
  # A current-revision failure with no moving owner has exhausted its useful
  # claim. It will be reconsidered after the next material revision.
  if int(older.tried)==revision and leases.is_empty():continue
  if _envelopes_overlap(older,request):return true
 return false
func _slice_budget(began: int,total: int) -> int:
 if total<=0:return 0
 return maxi(1,total-int(Time.get_ticks_usec()-began)-BUDGET_HEADROOM_USEC)
func _defer_stale_retry(request: Dictionary) -> void:
 if request.phase=="refuge":request.phase="refuge_wait"
 request.schedule_ticket=_next_ticket();request.tried=-1
func _handle_stale_failure(request: Dictionary) -> void:
 if request.phase=="route":_release_winner_holds(request.p)
 _defer_stale_retry(request)
func _next_request() -> Dictionary:
 var next: Dictionary={}
 for request in requests:
  if _lease_region_blocked(request):continue
  if request.tried==revision or (holds.has(request.p) and request.phase!="refuge_wait"):continue
  if not request.p.motion_step.is_empty():continue
  var dependency: int=0 if request.phase=="refuge_wait" else 1
  var next_dependency: int=0 if not next.is_empty() and next.phase=="refuge_wait" else 1
  if next.is_empty() or dependency<next_dependency or (dependency==next_dependency and (int(request.get("schedule_ticket",0))<int(next.get("schedule_ticket",0)) or (int(request.get("schedule_ticket",0))==int(next.get("schedule_ticket",0)) and int(request.sequence)<int(next.sequence)))):next=request
 return next

func advance(max_operations: int,time_budget_usec: int) -> void:
 var began:=Time.get_ticks_usec();var operations:=0
 _release_finished()
 for p in floor_node._porters:
  var available: bool=p.state!="deposit"
  if eligibility.has(p) and eligibility[p]!=available:revision+=1
  eligibility[p]=available
 while operations<max_operations and (time_budget_usec<=0 or Time.get_ticks_usec()-began<time_budget_usec):
  if active.is_empty():
   var next: Dictionary=_next_request()
   if next.is_empty():break
   if next.phase=="refuge_wait":_begin_refuge_snapshot(next)
   elif next.intent.is_empty():_start(next,"intent",floor_node._porter_router)
   else:
    _check_intent(next);operations+=1
    if active.is_empty():continue
  var request: Dictionary=active;var p: Variant=request.p
  if request.phase=="envelope":
   var builder: RefCounted=request.sweep_job
   builder.advance(mini(32,max_operations-operations),_slice_budget(began,time_budget_usec))
   telemetry.sweep_operations+=builder.last_operations
   operations+=maxi(1,builder.last_operations)
   if builder.status=="ready":_finish_envelope(request)
   continue
  if request.phase=="admit_envelope":
   var admission_builder: RefCounted=request.sweep_job
   admission_builder.advance(mini(32,max_operations-operations),_slice_budget(began,time_budget_usec))
   telemetry.sweep_operations+=admission_builder.last_operations
   operations+=maxi(1,admission_builder.last_operations)
   if admission_builder.status=="ready":
    telemetry.admission_sweep+=1
    request.erase("sweep_job");_begin_corridor_check(request,request.admission_steps,admission_builder.poses,admission_builder.index,admission_builder.offsets)
   continue
  if request.phase=="corridor":
   operations+=maxi(1,_advance_corridor_check(request,mini(32,max_operations-operations)))
   continue
  if request.phase=="snapshot_validate":
   operations+=maxi(1,request.geometry.advance_setup(mini(32,max_operations-operations),_slice_budget(began,time_budget_usec)))
   if not request.geometry.setup_pending:request.phase="validate";request.check_cursor=0
   continue
  if request.phase=="snapshot_refuge":
   operations+=maxi(1,request.geometry.advance_setup(mini(32,max_operations-operations),_slice_budget(began,time_budget_usec)))
   if not request.geometry.setup_pending:
    request.geometry.avoid_end=request.avoid_index
    _start(request,"refuge",request.geometry)
   continue
  if request.phase=="validate":
   _validate_pose(request);operations+=1;continue
  var job: RefCounted=p.route_job
  job.advance(8,_slice_budget(began,time_budget_usec))
  telemetry.planner_operations+=job.last_operations
  operations+=maxi(1,job.last_operations)
  if job.pending():
   if request.phase=="route" and bool(request.get("alternate",false)) and job.expanded>=384:
    telemetry.alternate_cap+=1
    # A bounded alternate-path attempt lets a wide aisle use parallel lanes.
    # Failure here means wait for reserved space, not "no physical route".
    job.cancel();p.route_job=null
    if not _defer_for_lease(request):request.tried=request.snapshot_revision;active={}
   continue
  p.route_job=null;active={}
  if job.status!="ready" and int(request.snapshot_revision)!=revision:
   telemetry.failed_stale+=1
   _handle_stale_failure(request);continue
  if job.status=="ready":
   if request.phase=="intent":
    request.intent=job.result.duplicate()
    _check_intent(request)
   else:
    request.phase="admit_envelope";request.admission_steps=job.result.duplicate();request.sweep_job=SweepJob.new();request.sweep_job.begin(floor_node,p,request.admission_steps);active=request
  elif request.phase=="route":
   telemetry.failed_route_current+=1
   if _defer_for_lease(request):continue
   request.tried=revision
   # Courtesy holds cannot generate the revision this failed winner is now
   # waiting for. Resume their real work so movement can change the snapshot.
   _release_winner_holds(p)
   # A running cart owns a clear route and will release it. Do not ask it to
   # reverse inside the passage or waste repeated whole-map failed searches.
   if leases.is_empty() and request.intent.is_empty():_start(request,"intent",floor_node._porter_router)
  elif request.phase=="refuge":
   telemetry.failed_refuge+=1
   var winner: Dictionary=_find(request.refuge_for)
   requests.erase(request);enqueue(p,int(request.get("saved_age",request.sequence)))
   if not winner.is_empty():
    winner.skip.append(p);winner.tried=revision;_try_relocation(winner)
  else:telemetry.failed_intent+=1;request.tried=revision
 last_usec=Time.get_ticks_usec()-began
