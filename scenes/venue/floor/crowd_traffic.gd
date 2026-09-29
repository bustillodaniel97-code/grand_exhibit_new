extends RefCounted
## Immediate pedestrian/cart right of way. A started cart edge owns its sweep;
## before the next edge begins, people already in that space have priority.
const Geometry:=preload("res://scenes/venue/floor/cart_traffic_geometry.gd")
const RADIUS:=.22
const MARGIN:=.025
const HEIGHT_CLEARANCE:=73.0
var floor_node: Node
var cart_poses: Array=[]
var repaths_left:=0
var visitor_waits:=0
var cart_waits:=0
var detours:=0
var obstacle_clock:=0.0
var obstacle_signature: Array=[]
var obstacles: Array=[]
func configure(owner: Node) -> void:
 floor_node=owner;cart_poses=[];obstacles=[];obstacle_signature=[];obstacle_clock=0.0
func refresh_obstacles(dt: float) -> void:
 obstacle_clock-=dt
 if obstacle_clock>0:return
 obstacle_clock=.5
 var next: Array=[];var signature: Array=[]
 for v in floor_node._visitors+floor_node._rejected:
  # Moving guests use the immediate edge guard. Reserve only people who are
  # actually stopped; a frozen snapshot of a flowing queue closes real aisles.
  if v.node.walking and v.cart_wait<.1:continue
  var height: float=floor_node._porter_layout._height_at(v.pos)
  next.append({"at":v.pos,"radius":RADIUS,"height":height})
  signature.append([v.node.get_instance_id(),floor_node._nav_id(v.pos),roundi(height)])
 obstacles=next
 if signature!=obstacle_signature:
  obstacle_signature=signature;floor_node._cart_dispatch.revision+=1
func planning_obstacles() -> Array:return obstacles
func begin_step() -> void:
 repaths_left=1;cart_poses=[]
 for p in floor_node._porters:
  if not p.staged:continue
  if p.motion_step.is_empty():cart_poses.append({"at":p.pos,"heading":Geometry.heading(p),"height":floor_node._porter_layout._height_at(p.pos),"owner":p})
  else:
   for pose in floor_node._cart_dispatch.sweep(p,[p.motion_step]):
    pose.owner=p;cart_poses.append(pose)
func overlaps_segment(from: Vector2,to: Vector2,pose: Dictionary,radius: float=RADIUS+MARGIN) -> bool:
 # A pedestrian disc sweeps a rounded rectangle around the cart. Expanding
 # an AABB alone invents solid square corners and can trap a legal pedestrian.
 var front: Vector2=pose.heading;var right:=Vector2(front.y,-front.x)
 var a:=Vector2((from-pose.at).dot(front),(from-pose.at).dot(right))
 var b:=Vector2((to-pose.at).dot(front),(to-pose.at).dot(right))
 var low:=Vector2(Geometry.REAR,-Geometry.HALF_WIDTH)
 var high:=Vector2(Geometry.FRONT,Geometry.HALF_WIDTH)
 var first:=0.0;var last:=1.0;var intersects:=true
 for axis in 2:
  var delta:=b[axis]-a[axis]
  if absf(delta)<.000001:
   if a[axis]<low[axis] or a[axis]>high[axis]:intersects=false;break
  else:
   var enter: float=(low[axis]-a[axis])/delta;var leave: float=(high[axis]-a[axis])/delta
   if enter>leave:var swap:=enter;enter=leave;leave=swap
   first=maxf(first,enter);last=minf(last,leave)
   if first>last:intersects=false;break
 if intersects:return true
 var distance:=minf(Geometry.point_distance(from,pose.at,front),Geometry.point_distance(to,pose.at,front))
 for corner in [low,high,Vector2(low.x,high.y),Vector2(high.x,low.y)]:
  distance=minf(distance,Geometry2D.get_closest_point_to_segment(corner,a,b).distance_to(corner))
 return distance<radius

func _surface_distance(point:Vector2,pose:Dictionary)->float:
 var offset:=point-(pose.at as Vector2)
 var front:Vector2=pose.heading;var right:=Vector2(front.y,-front.x)
 var half:=(Geometry.FRONT-Geometry.REAR)*.5
 var q:=Vector2(absf(offset.dot(front)-(Geometry.FRONT+Geometry.REAR)*.5)-half,absf(offset.dot(right))-Geometry.HALF_WIDTH)
 return Vector2(maxf(q.x,0.0),maxf(q.y,0.0)).length()+minf(maxf(q.x,q.y),0.0)
func _separation_slope(point:Vector2,delta:Vector2,pose:Dictionary)->float:
 var front:Vector2=pose.heading;var right:=Vector2(front.y,-front.x)
 var offset:=point-(pose.at as Vector2)
 var local:=Vector2(offset.dot(front)-(Geometry.FRONT+Geometry.REAR)*.5,offset.dot(right))
 var velocity:=Vector2(delta.dot(front),delta.dot(right))
 var q:=local.abs()-Vector2((Geometry.FRONT-Geometry.REAR)*.5,Geometry.HALF_WIDTH)
 var slope:=Vector2(signf(local.x)*velocity.x if local.x!=0.0 else absf(velocity.x),signf(local.y)*velocity.y if local.y!=0.0 else absf(velocity.y))
 var outside:=Vector2(maxf(q.x,0.0),maxf(q.y,0.0))
 if outside.length_squared()>0.0:return outside.normalized().dot(slope)
 # The maximum of active face distances gives the exact one-sided derivative
 # inside/on a convex rectangle, including equal-distance corners and centre.
 if q.x>q.y:return slope.x
 if q.y>q.x:return slope.y
 return maxf(slope.x,slope.y)
func visitor_clear(v:Variant,next:Vector2)->bool:
 var height:float=floor_node._porter_layout._height_at(v.pos)
 for pose in cart_poses:
  if absf(height-pose.height)>=HEIGHT_CLEARANCE or v.pos.distance_squared_to(pose.at)>6.25:continue
  var current:=_surface_distance(v.pos,pose)
  if current>=RADIUS+MARGIN:
   # Recovering from another cart must never waive this cart's admission guard.
   if overlaps_segment(v.pos,next,pose):return false
   continue
  var delta:Vector2=next-v.pos
  if delta.length_squared()<.00000001:return false
  # A positive initial derivative and endpoint gain forbid passing through the
  # cart to a farther exit. Signed distance to this convex box is convex along
  # a straight step, so these conditions give monotonic outward separation.
  if _separation_slope(v.pos,delta,pose)<=.0000001:return false
  if _surface_distance(next,pose)<=current+.0000001:return false
 return true
## True when a cart's next step would intersect another staged cart. Carts
## had no runtime check against each other - only visitors - so two admitted
## routes that cross (head-on passes, or a cart relocated across a moving
## route) drove straight through: the marathon sampled 145 intersecting
## pairs on three venues. This mirrors the visitor guard: the mover stops
## before overlapping, then the existing replan/refuge machinery reroutes it.
## Turning steps check their interpolated sweep, not only the destination.
func cart_conflict(p: Variant, step: Dictionary) -> bool:
 var height: float = floor_node._porter_layout._height_at(p.pos)
 for other in floor_node._porters:
  if other == p or not other.staged:continue
  if absf(height - floor_node._porter_layout._height_at(other.pos)) >= HEIGHT_CLEARANCE:continue
  var other_heading: Vector2 = Geometry.heading(other)
  if Geometry.overlap(p.pos, Geometry.heading(p), other.pos, other_heading):
   # Already intersecting (a legacy pose, or the frame this guard first
   # ships). A blanket skip let a step deepen or traverse the intersection;
   # comparing overlap depth alone cannot catch traversal because the SAT
   # depth saturates on the narrow axis. Center distance can: driving
   # through means first CLOSING on the other cart, whether the step ends
   # on the far side or not. Allow only steps whose swept centres never
   # approach: tangent and turn-in-place moves stay legal, a cart can
   # always pull away, and neither can drive through.
   var start_distance: float = p.pos.distance_to(other.pos)
   for pose in floor_node._cart_dispatch.sweep(p, [step]):
    if pose.at.distance_to(other.pos) < start_distance - .000001:return true
   return false
  for pose in floor_node._cart_dispatch.sweep(p, [step]):
   if Geometry.overlap(pose.at, pose.heading, other.pos, other_heading):return true
 return false

func cart_clear(p: Variant,step: Dictionary) -> bool:
 var nearby: Array=[]
 var height: float=floor_node._porter_layout._height_at(p.pos)
 for v in floor_node._visitors+floor_node._rejected:
  if p.pos.distance_squared_to(v.pos)>6.25 or absf(height-floor_node._porter_layout._height_at(v.pos))>=HEIGHT_CLEARANCE:continue
  nearby.append(v)
 if nearby.is_empty():return true
 var swept: Array=floor_node._cart_dispatch.sweep(p,[step])
 for v in nearby:
  for pose in swept:
   if Geometry.point_distance(v.pos,pose.at,pose.heading)<RADIUS+MARGIN:
    cart_waits+=1;return false
 return true
func clear_entry(dock: Dictionary) -> bool:
 var height: float=floor_node._porter_layout._height_at(dock.at)
 for v in floor_node._visitors+floor_node._rejected:
  if absf(height-floor_node._porter_layout._height_at(v.pos))>=HEIGHT_CLEARANCE:continue
  if Geometry.point_distance(v.pos,dock.at,dock.heading)<RADIUS+MARGIN:return false
 return true
func standing_clear(at: Vector2) -> bool:
 var height: float=floor_node._porter_layout._height_at(at)
 for p in floor_node._porters:
  if not p.staged or absf(height-floor_node._porter_layout._height_at(p.pos))>=HEIGHT_CLEARANCE:continue
  if Geometry.point_distance(at,p.pos,Geometry.heading(p))<RADIUS+.13:return false
 return true
func refuge_needed(v: Variant) -> bool:
 for blocker in v.cart_refuge_blockers:
  for pose in cart_poses:
   if pose.get("owner")==blocker.p and overlaps_segment(blocker.from,blocker.to,pose):return true
 return false
func _initial_anchor_clear(from:Vector2,nav:AStarGrid2D,id:Vector2i)->bool:
 var start:Vector2i=floor_node._nav_id(from)
 if start.x==id.x or start.y==id.y:return true
 # Initial detour anchors are neighboring quarter-grid cells. A diagonal
 # jump must obey the same no-corner-cutting rule as the ensuing A* route.
 for side in [Vector2i(start.x,id.y),Vector2i(id.x,start.y)]:
  if not nav.region.has_point(side) or nav.is_point_solid(side):return false
 return true
func _path_from_actual_position(v: Variant,nav: AStarGrid2D,target: Vector2i) -> Array:
 var start: Vector2i=floor_node._nav_id(v.pos)
 var starts: Array=[]
 for y in range(start.y-1,start.y+2):
  for x in range(start.x-1,start.x+2):
   var id:=Vector2i(x,y);var at:=Vector2(id)*.25
   if not nav.region.has_point(id) or nav.is_point_solid(id) or not _initial_anchor_clear(v.pos,nav,id) or not visitor_clear(v,at):continue
   starts.append({"id":id,"distance":at.distance_squared_to(v.pos)})
 starts.sort_custom(func(a: Dictionary,b: Dictionary)->bool:return a.distance<b.distance)
 for candidate in starts:
  var ids: Array[Vector2i]=nav.get_id_path(candidate.id,target)
  if ids.is_empty():continue
  var route: Array=[]
  for id in ids:
   var at:=Vector2(id)*.25
   if route.is_empty() and at.distance_to(v.pos)<.00001:continue
   route.append(at)
  if not route.is_empty():return route
 return []

func _refuge_path(v: Variant,nav: AStarGrid2D) -> Array:
 if v.state in ["queue","rest","rise"] or v.cart_refuge:return []
 var future: Dictionary={}
 for group in floor_node._cart_dispatch.leases.values()+floor_node._cart_dispatch.requests.map(func(request: Dictionary)->Array:return request.get("envelope",[])):
  for pose in group:
   var cell:=Vector2i(floori(pose.at.x),floori(pose.at.y))
   if not future.has(cell):future[cell]=[]
   future[cell].append(pose)
 var start: Vector2i=floor_node._nav_id(v.pos)
 var frontier: Array[Vector2i]=[];var parents: Dictionary={}
 for y in range(start.y-1,start.y+2):
  for x in range(start.x-1,start.x+2):
   var id:=Vector2i(x,y);var at:=Vector2(id)*.25
   if nav.region.has_point(id) and not nav.is_point_solid(id) and _initial_anchor_clear(v.pos,nav,id) and visitor_clear(v,at):
    frontier.append(id);parents[id]=id
 var cursor:=0;var nearby_cache: Dictionary={}
 # Local flood visits at most the 25x25 neighborhood once. Do not run dozens
 # of full-museum searches to discover that a nearby standing place is sealed.
 while cursor<frontier.size():
  var id:=frontier[cursor];cursor+=1
  var at:=Vector2(id)*.25;var distance:=at.distance_squared_to(v.pos)
  if distance>=.75*.75:
   var cell:=Vector2i(floori(at.x),floori(at.y))
   if not nearby_cache.has(cell):
    var poses: Array=[]
    for y in range(-2,3):
     for x in range(-2,3):poses.append_array(future.get(cell+Vector2i(x,y),[]))
    nearby_cache[cell]=poses
   var clear:=true;var height: float=floor_node._porter_layout._height_at(at)
   for pose in nearby_cache[cell]:
    if absf(height-float(pose.height))<HEIGHT_CLEARANCE and Geometry.point_distance(at,pose.at,pose.heading)<.50:clear=false;break
   if clear:
    for other in floor_node._visitors+floor_node._rejected:
     if other!=v and at.distance_to(other.pos)<.64:clear=false;break
   if clear:
    var result: Array=[];var current:=id
    while true:
     result.push_front(Vector2(current)*.25)
     if parents[current]==current:break
     current=parents[current]
    if not result.is_empty() and (result.front() as Vector2).distance_to(v.pos)<.00001:result.pop_front()
    v.cart_refuge=true;v.cart_refuge_at=at;v.cart_refuge_target=v.target
    v.cart_refuge_blockers=[]
    var next: Vector2=v.path[0] if not v.path.is_empty() else v.target
    next=v.pos+v.pos.direction_to(next)*minf(.15,v.pos.distance_to(next))
    var owners: Array=[]
    for pose in cart_poses:
     if not pose.has("owner") or pose.owner in owners or absf(floor_node._porter_layout._height_at(v.pos)-float(pose.height))>=HEIGHT_CLEARANCE:continue
     if overlaps_segment(v.pos,next,pose):
      owners.append(pose.owner);v.cart_refuge_blockers.append({"p":pose.owner,"from":v.pos,"to":next})
    return result
  for direction in [Vector2i.UP,Vector2i.DOWN,Vector2i.LEFT,Vector2i.RIGHT]:
   var next: Vector2i=id+direction
   if parents.has(next) or not nav.region.has_point(next) or nav.is_point_solid(next):continue
   if abs(next.x-start.x)>12 or abs(next.y-start.y)>12 or (Vector2(next)*.25).distance_squared_to(v.pos)>9:continue
   parents[next]=id;frontier.append(next)
 return []

func try_detour(v: Variant) -> bool:
 if repaths_left<=0 or v.cart_retry>0 or cart_poses.is_empty():return false
 repaths_left-=1;v.cart_retry=.75
 var nav: AStarGrid2D=floor_node._nav
 var changed: Array[Vector2i]=[]
 if floor_node.has_method("_mask_admission_actions"):
  var own_lane: int=v.window if v.state in ["to_queue","queue"] else -1
  changed=floor_node._mask_admission_actions(own_lane,v)
 var height: float=floor_node._porter_layout._height_at(v.pos)
 for pose in cart_poses:
  if absf(height-pose.height)>=HEIGHT_CLEARANCE:continue
  var first: Vector2i=floor_node._nav_id(pose.at-Vector2(1.25,1.25))
  var last: Vector2i=floor_node._nav_id(pose.at+Vector2(1.25,1.25))
  for y in range(first.y,last.y+1):
   for x in range(first.x,last.x+1):
    var cell:=Vector2i(x,y)
    if not nav.region.has_point(cell) or nav.is_point_solid(cell):continue
    if Geometry.point_distance(Vector2(cell)*.25,pose.at,pose.heading)<RADIUS+.13:
     nav.set_point_solid(cell,true);changed.append(cell)
 var candidates: Array=v.path.duplicate();candidates.append(v.target)
 var target:=Vector2.ZERO;var join:=-1
 # Rejoin the authored route beyond the obstruction. Keep its later landmarks,
 # queue destination, admission phase and seating approach intact.
 for i in candidates.size():
  var point: Vector2=candidates[i]
  var id: Vector2i=floor_node._nav_id(point)
  if point.distance_squared_to(v.pos)<4.0 and i<candidates.size()-1:continue
  if nav.region.has_point(id) and not nav.is_point_solid(id):target=point;join=i;break
 var route: Array=[]
 if join>=0:route=_path_from_actual_position(v,nav,floor_node._nav_id(target))
 if route.is_empty():
  route=_refuge_path(v,nav)
  if not route.is_empty():
   route.append_array(candidates.slice(maxi(join,0)));join=candidates.size()-1;target=v.target
 for cell in changed:nav.set_point_solid(cell,false)
 if route.is_empty():return false
 if not (route.back() as Vector2).is_equal_approx(target):route.append(target)
 route.append_array(candidates.slice(join+1))
 # The target remains owned by the FSM; only intermediate waypoints change.
 if not route.is_empty() and (route.back() as Vector2).is_equal_approx(v.target):route.pop_back()
 v.path=route;detours+=1;return true
