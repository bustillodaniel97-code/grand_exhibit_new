extends RefCounted
## Immutable occupancy/route reservation snapshot for one bounded planner job.
const Geometry:=preload("res://scenes/venue/floor/cart_traffic_geometry.gd")
const DIRECTIONS: Array=[Vector2.DOWN,Vector2.RIGHT,Vector2.UP,Vector2.LEFT]
const STEP:=.25
const LEVEL_CLEARANCE:=73.0 # Ignore only genuinely separated storeys, never neighboring ramp poses.
var source: RefCounted
var generation: int:
 get:return source.generation
var occupied: Dictionary={}
var avoid_end: Dictionary={}
var point_occupied: Dictionary={}
var origin:=Vector2.ZERO
var fit_cache: Dictionary={}
var move_cache: Dictionary={}
var turn_cache: Dictionary={}
var _near_cache: Dictionary={}
var _setup_groups: Array=[]
var _setup_avoid_groups: Array=[]
var _setup_point_groups: Array=[]
var _setup_group:=0
var _setup_pose:=0
var _setup_avoid:=false
var _setup_points:=false
var setup_pending:=false
func configure(base: RefCounted,poses: Array,end_exclusion: Array=[]) -> void:
 begin_configure(base,[poses],[end_exclusion])
 while setup_pending:advance_setup(4096,0)
func begin_configure(base: RefCounted,pose_groups: Array,end_groups: Array=[],point_groups: Array=[]) -> void:
 source=base;occupied={};avoid_end={};point_occupied={};fit_cache={};move_cache={};turn_cache={};_near_cache={}
 _setup_groups=pose_groups;_setup_avoid_groups=end_groups;_setup_point_groups=point_groups
 _setup_group=0;_setup_pose=0;_setup_avoid=false;_setup_points=false;setup_pending=true
func use_indexes(base: RefCounted,occupied_index: Dictionary,avoid_index: Dictionary={}) -> void:
 source=base;occupied=occupied_index;avoid_end=avoid_index;point_occupied={}
 fit_cache={};move_cache={};turn_cache={};_near_cache={};setup_pending=false
func advance_setup(max_operations: int,time_budget_usec: int) -> int:
 var operations:=0;var began:=Time.get_ticks_usec()
 while setup_pending and operations<maxi(0,max_operations):
  if time_budget_usec>0 and Time.get_ticks_usec()-began>=time_budget_usec:break
  var groups: Array=_setup_point_groups if _setup_points else (_setup_avoid_groups if _setup_avoid else _setup_groups)
  if _setup_group>=groups.size():
   if not _setup_avoid:_setup_avoid=true;_setup_group=0;_setup_pose=0;continue
   if not _setup_points:_setup_points=true;_setup_group=0;_setup_pose=0;continue
   setup_pending=false;break
  var raw_group: Variant=groups[_setup_group]
  var group: Array=raw_group.poses if raw_group is Dictionary else raw_group
  var start: int=int(raw_group.get("start",0)) if raw_group is Dictionary else 0
  if start+_setup_pose>=group.size():_setup_group+=1;_setup_pose=0;continue
  _insert(point_occupied if _setup_points else (avoid_end if _setup_avoid else occupied),group[start+_setup_pose]);_setup_pose+=1;operations+=1
 return operations
func _insert(index: Dictionary,pose: Dictionary) -> void:
 var cell:=Vector2i(floori(pose.at.x),floori(pose.at.y))
 if not index.has(cell):index[cell]=[]
 index[cell].append(pose)
func key(at: Vector2,heading: Vector2) -> Vector3i:return source.key(at,heading)
func position(state: Vector3i) -> Vector2:return source.position(state)
func estimate(state: Vector3i,goal: Vector3i) -> float:
 var turns:=mini(posmod(state.z-goal.z,4),posmod(goal.z-state.z,4))
 return (abs(state.x-goal.x)+abs(state.y-goal.y))*STEP+turns*.38
func clear_index(index: Dictionary,at: Vector2,heading: Vector2,padding: float=.025) -> bool:
 return clear_poses(_near(index,at),at,heading,padding) and clear_points(_near(point_occupied,at),at,heading,padding)
func _near(index: Dictionary,at: Vector2) -> Array:
 var cell:=Vector2i(floori(at.x),floori(at.y));var result: Array=[]
 for y in range(-2,3):
  for x in range(-2,3):
   result.append_array(index.get(cell+Vector2i(x,y),[]))
 return result
func _near_occupied(at: Vector2) -> Array:
 var cell:=Vector2i(floori(at.x),floori(at.y))
 if not _near_cache.has(cell):_near_cache[cell]=_near(occupied,at)
 return _near_cache[cell]
func clear_poses(poses: Array,at: Vector2,heading: Vector2,padding: float=.025) -> bool:
 var height: float=source.layout._height_at(at)
 for pose in poses:
  if absf(height-pose.height)>=LEVEL_CLEARANCE:continue
  if Geometry.overlap(at,heading,pose.at,pose.heading,padding):return false
 return true
func clear_points(points: Array,at: Vector2,heading: Vector2,padding: float=.025) -> bool:
 var height: float=source.layout._height_at(at)
 for point in points:
  if absf(height-float(point.height))>=LEVEL_CLEARANCE:continue
  if Geometry.point_distance(point.at,at,heading)<float(point.radius)+padding:return false
 return true
func is_refuge(state: Vector3i) -> bool:
 if position(state).distance_squared_to(origin)<.25:return false
 var at := position(state)
 var heading: Vector2 = DIRECTIONS[state.z]
 # A refuge must clear the winner's path AND the colleagues parked around
 # it. The old check ignored other carts, so a relocated porter could be
 # admitted into a pose overlapping a parked colleague - and once two carts
 # rest intersecting, every later tick samples another overlap fault.
 if not clear_index(avoid_end,at,heading,.06):return false
 return clear_index(occupied,at,heading,.06)
func fits(state: Vector3i) -> bool:
 if not fit_cache.has(state):fit_cache[state]=source.fits(state) and clear_index(occupied,position(state),DIRECTIONS[state.z])
 return bool(fit_cache[state])
func can_move(a: Vector3i,b: Vector3i) -> bool:
 var edge:=[a,b]
 if not move_cache.has(edge):
  var midpoint:=(position(a)+position(b))*.5
  var ok: bool=source.can_move(a,b);var candidates:=_near_occupied(midpoint);var points:=_near(point_occupied,midpoint)
  for i in 5:
   if not ok:break
   var at:=position(a).lerp(position(b),i/4.0)
   ok=clear_poses(candidates,at,DIRECTIONS[a.z]) and clear_points(points,at,DIRECTIONS[a.z])
  move_cache[edge]=ok
 return bool(move_cache[edge])
func can_turn(a: Vector3i,b: Vector3i) -> bool:
 var edge:=[a,b]
 if not turn_cache.has(edge):
  var ok: bool=source.can_turn(a,b);var candidates:=_near_occupied(position(a));var points:=_near(point_occupied,position(a))
  var heading: Vector2=DIRECTIONS[a.z];var angle:=heading.angle_to(DIRECTIONS[b.z])
  for i in 33:
   if not ok:break
   var direction:=heading.rotated(angle*i/32.0)
   ok=clear_poses(candidates,position(a),direction) and clear_points(points,position(a),direction)
  turn_cache[edge]=ok
 return bool(turn_cache[edge])
