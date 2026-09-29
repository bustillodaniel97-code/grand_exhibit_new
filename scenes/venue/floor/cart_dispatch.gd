extends RefCounted
## Route admission happens while carts are still in safe poses. Committed routes
## reserve their complete physical sweep; independent routes can run together.
## A blocked request can first move a stationary blocker to a reachable refuge.
const Geometry:=preload("res://scenes/venue/floor/cart_traffic_geometry.gd")
const Snapshot:=preload("res://scenes/venue/floor/cart_dispatch_geometry.gd")
const Job:=preload("res://scenes/venue/floor/porter_route_job.gd")
const SweepJob:=preload("res://scenes/venue/floor/cart_sweep_job.gd")
var floor_node: Node
var requests: Array=[]
var leases: Dictionary={}
var lease_data: Dictionary={}
var holds: Dictionary={}
var revision:=0
# Physical cart/reservation changes invalidate corridor comparisons; visitor
# snapshots keep their independent broad revision for route validation/retries.
var reservation_revision:=0
var claim_generation:=0
var sequence:=0
var schedule_ticket:=0
var active: Dictionary={}
var grants:=0
var relocations:=0
var peak_concurrent:=0
var last_usec:=0
## Last gated request re-armed by the silence breaker below, so re-arms
## round-robin instead of spinning on one request.
var _silence_probe: Dictionary = {}
## Round-robin cursor for fair time-slicing (ticket of the request served
## last). A single cold search used to hold `active` for tens of sim-seconds
## while the other couriers idled at spawn; a busy request now yields at the
## next dispatch call when another eligible request is still waiting its turn.
## Within a call the active request keeps every quantum (stickiness), which is
## also what the refuge-eligibility unit test observes.
var _slice_last_ticket: int = -1

const BUDGET_HEADROOM_USEC:=350
var eligibility: Dictionary={}
func configure(owner: Node) -> void:
 for p in holds:
  p.state=holds[p].state
 for request in requests:
  if request.p.route_job!=null:request.p.route_job.cancel();request.p.route_job=null
 floor_node=owner;requests=[];leases.clear();lease_data.clear();holds.clear();active={};eligibility.clear();schedule_ticket=0;_slice_last_ticket=-1;_silence_probe={};revision+=1;reservation_revision+=1
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
 if leases.has(p):leases.erase(p);lease_data.erase(p);revision+=1;reservation_revision+=1
 elif departure:revision+=1;reservation_revision+=1
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
 leases.erase(p);lease_data.erase(p);p.route_steps=[];p.route_cursor=0;p.route_job=null;revision+=1;reservation_revision+=1
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
   revision+=1;reservation_revision+=1
 for p in leases.keys():
  if not p.motion_step.is_empty() or p.route_cursor<p.route_steps.size():continue
  leases.erase(p);lease_data.erase(p);revision+=1;reservation_revision+=1
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
 revision+=1;reservation_revision+=1;grants+=1;peak_concurrent=maxi(peak_concurrent,leases.size())
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
  # A colleague mid-search is about to move on its own: yanking it into
  # refuge discards a cold search worth tens of sim-seconds of budget and
  # restarts the starvation the rotation just fixed. Route around (or wait
  # for) searchers instead; their completion bumps the revision we retry on.
  if not other.motion_step.is_empty() or other.state=="deposit" or other.route_job!=null:continue
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
 var builder: RefCounted=request.sweep_job
 request.envelope=builder.poses;request.envelope_index=builder.index;request.envelope_offsets=builder.offsets
 claim_generation+=1;request.claim_generation=claim_generation
 request.erase("sweep_job");_begin_validation_snapshot(request)

func _validate_pose(request: Dictionary) -> void:
 var geometry: RefCounted=request.geometry
 var pose: Dictionary=request.envelope[request.check_cursor]
 if not geometry.clear_index(geometry.occupied,pose.at,pose.heading):
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
# Eligibility can change when a broad visitor revision revives a failed claim.
# Check identity/order and immutable envelope generation, not every pose again.
func _claim_signature(claims:Array)->Array:
 var signature:Array=[]
 for claim in claims:
  signature.append([claim.p.get_instance_id(),int(claim.sequence),int(claim.get("schedule_ticket",0)),int(claim.get("claim_generation",0))])
 return signature
# corridor_revision is retained in traces; restart depends on physical cart
# changes OR the actual eligible claim signature. This phase reads no guests.
func _begin_corridor_check(request: Dictionary,steps: Array,envelope: Array,index: Dictionary,offsets: Array) -> void:
 request.phase="corridor";request.admission_steps=steps.duplicate();request.admission_envelope=envelope;request.admission_index=index;request.admission_offsets=offsets
 request.corridor_claims=_eligible_older_claims(request);request.corridor_claim_signature=_claim_signature(request.corridor_claims);request.corridor_claim=0;request.corridor_pose=0;request.corridor_revision=revision;request.corridor_reservation_revision=reservation_revision;active=request
func _finish_corridor_check(request: Dictionary,blocked: bool) -> void:
 if blocked:
  request.phase="refuge_wait" if request.refuge_for!=null else "route"
  request.tried=-1 if request.refuge_for!=null else revision;active={}
  request.erase("admission_steps");request.erase("admission_envelope");request.erase("admission_index");request.erase("admission_offsets")
 else:_admit(request,request.admission_steps)
func _advance_corridor_check(request: Dictionary,max_operations: int) -> int:
 if int(request.corridor_reservation_revision)!=reservation_revision or request.corridor_claim_signature!=_claim_signature(_eligible_older_claims(request)):_finish_corridor_check(request,true);return 1
 var operations:=0
 while operations<max_operations:
  if request.corridor_claim>=request.corridor_claims.size():_finish_corridor_check(request,false);break
  var older: Dictionary=request.corridor_claims[request.corridor_claim]
  if request.corridor_pose>=request.admission_envelope.size():request.corridor_claim+=1;request.corridor_pose=0;continue
  var geometry:=Snapshot.new();geometry.use_indexes(floor_node._porter_router,older.envelope_index)
  var pose: Dictionary=request.admission_envelope[request.corridor_pose];request.corridor_pose+=1;operations+=1
  if not geometry.clear_index(geometry.occupied,pose.at,pose.heading):_finish_corridor_check(request,true);break
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
func _rotation_candidates() -> Array:
 var out: Array = requests.duplicate()
 # A refuge helper is served via `active` without living in `requests`;
 # rotation must still reach it every round.
 if not active.is_empty() and not out.has(active):
  out.append(active)
 return out

## True while a request still needs its planning begun. Mid-pipeline requests
## carry a route job, sweep job or snapshot geometry and must resume - never
## restart - when their slice comes around. refuge_wait never carries geometry
## (the snapshot is built at begin time), so it always begins. Corridor-
## blocked route requests keep a stale validation snapshot but no job; they
## gate on tried like other pre-begin work and re-check from their intent.
func _needs_begin(request: Dictionary) -> bool:
 if request.phase != "route" and request.phase != "refuge_wait":
  return false
 if request.p.route_job != null or request.has("sweep_job"):
  return false
 return true

## Oldest tried-gated pre-begin request (failed/blocked, waiting a world
## change), excluding one already probed, for the silence breaker below.
func _oldest_gated() -> Dictionary:
 var out: Dictionary = {}
 for request in requests:
  if not _needs_begin(request) or int(request.get("tried", -1)) != revision:
   continue
  if holds.has(request.p) and request.get("refuge_for") == null and request.phase != "refuge_wait":
   continue
  if not request.p.motion_step.is_empty():
   continue
  if request == _silence_probe:
   continue
  if out.is_empty() or int(request.get("sequence", 0)) < int(out.get("sequence", 0)):
   out = request
 return out

func _next_request() -> Dictionary:
 var next: Dictionary={}
 for request in _rotation_candidates():
  # Retry gating applies to pre-begin requests (failed or blocked attempts
  # wait for a world change). In-progress pipeline work resumes regardless:
  # it was already admitted to the current revision, and the old
  # stick-with-active loop served it without re-picking.
  if _needs_begin(request) and int(request.get("tried", -1)) == revision:continue
  # A held porter's main request stays suspended, but its refuge helper must
  # keep its slices: the helper is the only thing that moves the blocker, and
  # filtering it out starves the hold it was created to resolve. (Single-active
  # scheduling never noticed because it served `active` without re-picking.)
  if holds.has(request.p) and request.get("refuge_for") == null and request.phase!="refuge_wait":continue
  if not request.p.motion_step.is_empty():continue
  var dependency: int=0 if request.phase=="refuge_wait" else 1
  var next_dependency: int=0 if not next.is_empty() and next.phase=="refuge_wait" else 1
  if next.is_empty() or dependency<next_dependency or (dependency==next_dependency and _ticket_after(int(request.get("schedule_ticket",0)),int(next.get("schedule_ticket",0)))):next=request
 return next

## True when ticket a comes after ticket b in rotation order: the smallest
## ticket above the cursor wins, wrapping to the smallest overall. This is
## what rotates slices across couriers. Refuge urgency stays outer (a waiting
## refuge preempts regardless of cursor position).
func _ticket_after(a: int, b: int) -> bool:
 var a_after: bool = a > _slice_last_ticket
 var b_after: bool = b > _slice_last_ticket
 if a_after != b_after:
  return a_after
 return a < b

func advance(max_operations: int,time_budget_usec: int) -> void:
 var began:=Time.get_ticks_usec();var operations:=0
 _release_finished()
 for p in floor_node._porters:
  var available: bool=p.state!="deposit"
  if eligibility.has(p) and eligibility[p]!=available:revision+=1;reservation_revision+=1
  eligibility[p]=available
 # Fair share across calls: a busy request yields here when another eligible
 # request is still waiting its turn, so one cold search cannot hold planning
 # for tens of sim-seconds while the other couriers idle. The cursor records
 # the parked ticket so the next pick rotates forward; parked work resumes
 # with its state intact when picked. Within a call the active request keeps
 # every quantum (stickiness), which is also what the refuge-eligibility unit
 # test observes.
 if not active.is_empty():
  var incumbent: Dictionary = active
  active = {}
  var other: Dictionary = _next_request()
  if other.is_empty() or other == incumbent:
   active = incumbent
  else:
   _slice_last_ticket = int(incumbent.get("schedule_ticket", _slice_last_ticket))
 while operations<max_operations and (time_budget_usec<=0 or Time.get_ticks_usec()-began<time_budget_usec):
  if active.is_empty():
   var next: Dictionary = _next_request()
   if next.is_empty():
    # Silence breaker: every pending request is tried-gated and nothing moves,
    # so no revision bump will ever re-arm them. Re-arm the oldest gated
    # request (round-robin) instead of stalling quietly until process end.
    # The re-armed request retries its validation or route; any movement or
    # admission it triggers bumps the revision that unblocks the rest.
    next = _oldest_gated()
    if next.is_empty():break
    next.tried = -1
    _silence_probe = next
   active = next
   _slice_last_ticket = int(next.get("schedule_ticket", _slice_last_ticket))
   if next.phase=="refuge_wait" and not next.has("geometry"):_begin_refuge_snapshot(next)
   elif next.phase=="route" and next.p.route_job==null and not next.has("sweep_job"):
    if next.intent.is_empty():_start(next,"intent",floor_node._porter_router)
    else:
     _check_intent(next);operations+=1
     if active.is_empty():continue
   elif (next.phase=="validate" or next.phase=="intent") and next.p.route_job==null and not next.has("sweep_job") and not next.has("geometry"):
    # Degenerate planning state with no live objects (e.g. synthetic unit-test
    # requests): restart from the intent exactly as the old pick block did via
    # its intent rule, instead of resuming a phase that has nothing to resume.
    if next.intent.is_empty():_start(next,"intent",floor_node._porter_router)
    else:
     _check_intent(next);operations+=1
     if active.is_empty():continue
  var request: Dictionary=active;var p: Variant=request.p
  if request.phase=="envelope":
   var builder: RefCounted=request.sweep_job
   builder.advance(mini(32,max_operations-operations),_slice_budget(began,time_budget_usec))
   operations+=maxi(1,builder.last_operations)
   if builder.status=="ready":_finish_envelope(request)
   continue
  if request.phase=="admit_envelope":
   var admission_builder: RefCounted=request.sweep_job
   admission_builder.advance(mini(32,max_operations-operations),_slice_budget(began,time_budget_usec))
   operations+=maxi(1,admission_builder.last_operations)
   if admission_builder.status=="ready":
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
  operations+=maxi(1,job.last_operations)
  if job.pending():
   if request.phase=="route" and bool(request.get("alternate",false)) and job.expanded>=384:
    # A bounded alternate-path attempt lets a wide aisle use parallel lanes.
    # Failure here means wait for reserved space, not "no physical route".
    job.cancel();p.route_job=null;request.tried=request.snapshot_revision;active={}
   continue
  p.route_job=null;active={}
  if job.status!="ready" and int(request.snapshot_revision)!=revision:
   _handle_stale_failure(request);continue
  if job.status=="ready":
   if request.phase=="intent":
    request.intent=job.result.duplicate()
    _check_intent(request)
   else:
    request.phase="admit_envelope";request.admission_steps=job.result.duplicate();request.sweep_job=SweepJob.new();request.sweep_job.begin(floor_node,p,request.admission_steps);active=request
  elif request.phase=="route":
   request.tried=revision
   # Courtesy holds cannot generate the revision this failed winner is now
   # waiting for. Resume their real work so movement can change the snapshot.
   _release_winner_holds(p)
   # A running cart owns a clear route and will release it. Do not ask it to
   # reverse inside the passage or waste repeated whole-map failed searches.
   if leases.is_empty() and request.intent.is_empty():_start(request,"intent",floor_node._porter_router)
  elif request.phase=="refuge":
   var winner: Dictionary=_find(request.refuge_for)
   requests.erase(request);enqueue(p,int(request.get("saved_age",request.sequence)))
   if not winner.is_empty():
    winner.skip.append(p);winner.tried=revision;_try_relocation(winner)
  else:request.tried=revision
 last_usec=Time.get_ticks_usec()-began
