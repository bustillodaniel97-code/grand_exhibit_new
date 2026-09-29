extends RefCounted
## Prototype only: incrementally evaluates one router edge without changing the
## route job's neighbor order or heap behavior.
const DIRECTIONS: Array=[Vector2.DOWN,Vector2.RIGHT,Vector2.UP,Vector2.LEFT]
var geometry: RefCounted
var a:=Vector3i.ZERO
var b:=Vector3i.ZERO
var turning:=false
var status:="idle"
var result:=false
var sample:=0
var last_operations:=0
var _edge: Array=[]
var _at:=Vector2.ZERO
var _heading:=Vector2.ZERO
var _angle:=0.0
var _poses: Array=[]
var _points: Array=[]
func begin(target: RefCounted,from: Vector3i,to: Vector3i,is_turn: bool) -> void:
 geometry=target;a=from;b=to;turning=is_turn;_edge=[a,b];sample=0;last_operations=0
 var cache: Dictionary=geometry.turn_cache if turning else geometry.move_cache
 if cache.has(_edge):status="ready";result=bool(cache[_edge]);return
 status="checking";result=true;_at=geometry.position(a);_heading=DIRECTIONS[a.z]
 if turning:_angle=_heading.angle_to(DIRECTIONS[b.z]);_poses=geometry._near_occupied(_at);_points=geometry._near(geometry.point_occupied,_at)
 else:
  var midpoint: Vector2=(_at+geometry.position(b))*.5;_poses=geometry._near_occupied(midpoint);_points=geometry._near(geometry.point_occupied,midpoint)
func advance(max_operations: int,time_budget_usec: int=0) -> void:
 last_operations=0;var began:=Time.get_ticks_usec()
 while status=="checking" and last_operations<max_operations:
  if time_budget_usec>0 and Time.get_ticks_usec()-began>=time_budget_usec:break
  result=_check_sample();sample+=1;last_operations+=1
  if not result or sample>=_sample_count():_finish()
func _sample_count() -> int:return 65 if turning else 7
func _check_sample() -> bool:
 if sample==0:return geometry.source.fits(b)
 if turning:
  if sample<=31:return geometry.source.layout.fits(_at,_heading.rotated(_angle*sample/32.0),false)
  var direction:=_heading.rotated(_angle*(sample-32)/32.0)
  return geometry.clear_poses(_poses,_at,direction) and geometry.clear_points(_points,_at,direction)
 if sample==1:return geometry.source.layout.fits((_at+geometry.position(b))*.5,_heading,false)
 var at: Vector2=_at.lerp(geometry.position(b),(sample-2)/4.0)
 return geometry.clear_poses(_poses,at,_heading) and geometry.clear_points(_points,at,_heading)
func _finish() -> void:
 status="ready"
 if turning:geometry.turn_cache[_edge]=result
 else:geometry.move_cache[_edge]=result
