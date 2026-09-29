extends RefCounted
## Resumable oriented A*. Each advance does bounded work, including path
## reconstruction. Geometry caches can be shared; search state belongs to a job.
var geometry: RefCounted
var generation := -1
var status := "idle"
var result: Array = []
var expanded := 0
var last_operations := 0
var last_usec := 0
var seek_refuge := false
var _start := Vector3i.ZERO
var _goal := Vector3i.ZERO
var _current := Vector3i.ZERO
var _rebuild := Vector3i.ZERO
var _edge := 0
var _validation := 0
var _heap: Array = []
var _cost: Dictionary = {}
var _previous: Dictionary = {}
var _closed: Dictionary = {}

func pending() -> bool:
 return status in ["validating","searching","building"]

func begin(source: RefCounted,from: Vector2,heading: Vector2,to: Vector2,end_heading: Vector2,refuge: bool=false) -> void:
 seek_refuge=refuge
 geometry=source;generation=geometry.generation
 result.clear();_heap.clear();_cost.clear();_previous.clear();_closed.clear()
 expanded=0;last_operations=0;last_usec=0;_validation=0;_edge=4
 _start=geometry.key(from,heading);_goal=geometry.key(to,end_heading)
 if _start.z<0 or _goal.z<0 or geometry.position(_start).distance_to(from)>.001 or geometry.position(_goal).distance_to(to)>.001:
  status="unreachable";return
 status="validating"

func cancel() -> void:
 status="cancelled";result.clear();_heap.clear();_cost.clear();_previous.clear();_closed.clear()

func advance(max_operations: int=32,time_budget_usec: int=1500) -> void:
 last_operations=0
 var began:=Time.get_ticks_usec()
 if geometry!=null and geometry.generation!=generation:cancel()
 while pending() and last_operations<maxi(0,max_operations):
  if time_budget_usec>0 and Time.get_ticks_usec()-began>=time_budget_usec:break
  last_operations+=1
  match status:
   "validating":
    if not geometry.fits(_start if _validation==0 else _goal):status="unreachable";break
    _validation+=1
    if _validation==(1 if seek_refuge else 2):
     _cost[_start]=0.0;_push([0.0 if seek_refuge else geometry.estimate(_start,_goal),_start]);status="searching"
   "searching":
    if _edge==4:
     if _heap.is_empty():status="unreachable";break
     var state: Vector3i=_pop()[1]
     if _closed.has(state):continue
     _closed[state]=true;expanded+=1
     if (geometry.is_refuge(state) if seek_refuge else state==_goal):status="building";_rebuild=state;continue
     _current=state;_edge=0
    else:
     _visit_edge(_edge);_edge+=1
   "building":
    if _rebuild==_start:
     result.reverse();status="ready"
     _heap.clear();_cost.clear();_previous.clear();_closed.clear()
    else:
     var parent: Vector3i=_previous[_rebuild]
     var delta: Vector2=geometry.position(_rebuild)-geometry.position(parent)
     result.append({"at":geometry.position(_rebuild),"heading":geometry.DIRECTIONS[_rebuild.z],"turn":_rebuild.z!=parent.z,"reverse":delta.dot(geometry.DIRECTIONS[_rebuild.z])<0})
     _rebuild=parent
 last_usec=Time.get_ticks_usec()-began

func _visit_edge(index: int) -> void:
 var next: Vector3i=_current
 var extra: float
 if index<2:
  var dir: Vector2=geometry.DIRECTIONS[_current.z]
  var movement:=1 if index==0 else -1
  next=Vector3i(_current.x+int(dir.x)*movement,_current.y+int(dir.y)*movement,_current.z)
  if _closed.has(next) or not geometry.can_move(_current,next):return
  extra=geometry.STEP if movement>0 else geometry.STEP*1.2
 else:
  next.z=posmod(_current.z+(-1 if index==2 else 1),4)
  if _closed.has(next) or not geometry.can_turn(_current,next):return
  extra=.38
 var candidate: float=float(_cost[_current])+extra
 if candidate>=float(_cost.get(next,INF)):return
 _cost[next]=candidate;_previous[next]=_current
 _push([candidate+(0.0 if seek_refuge else geometry.estimate(next,_goal)),next])

func _push(value: Array) -> void:
 _heap.append(value);var i:=_heap.size()-1
 while i>0:
  var parent: int=(i-1)/2
  if float(_heap[parent][0])<=float(value[0]):break
  _heap[i]=_heap[parent];i=parent
 _heap[i]=value

func _pop() -> Array:
 var result: Array=_heap[0];var tail: Array=_heap.pop_back()
 if _heap.is_empty():return result
 var i:=0
 while i*2+1<_heap.size():
  var child:=i*2+1
  if child+1<_heap.size() and float(_heap[child+1][0])<float(_heap[child][0]):child+=1
  if float(tail[0])<=float(_heap[child][0]):break
  _heap[i]=_heap[child];i=child
 _heap[i]=tail;return result
