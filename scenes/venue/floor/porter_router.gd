extends RefCounted
## A trolley has both a footprint and a facing. Point paths cannot represent
## reversing out of a narrow bay or the space required to turn its front end.
const DIRECTIONS := [Vector2.DOWN,Vector2.RIGHT,Vector2.UP,Vector2.LEFT]
const STEP := .25
var generation := 0
var layout: RefCounted
var fit_cache: Dictionary = {}
var turn_cache: Dictionary = {}
var move_cache: Dictionary = {}
var last_expanded := 0
var _heap: Array = []

func configure(source: RefCounted) -> void:
	generation+=1
	layout=source;fit_cache.clear();turn_cache.clear();move_cache.clear()

func key(at: Vector2,heading: Vector2) -> Vector3i:
	return Vector3i(roundi(at.x/STEP),roundi(at.y/STEP),DIRECTIONS.find(heading))

func position(state: Vector3i) -> Vector2:
	return Vector2(state.x,state.y)*STEP

func estimate(state: Vector3i,goal: Vector3i) -> float:
	return position(state).distance_to(position(goal))

func fits(state: Vector3i) -> bool:
	if not fit_cache.has(state):fit_cache[state]=layout.fits(position(state),DIRECTIONS[state.z],false)
	return bool(fit_cache[state])

func can_move(a: Vector3i,b: Vector3i) -> bool:
	var edge:=[a,b]
	if not move_cache.has(edge):
		move_cache[edge]=fits(b) and layout.fits((position(a)+position(b))*.5,DIRECTIONS[a.z],false)
	return bool(move_cache[edge])

func can_turn(a: Vector3i,b: Vector3i) -> bool:
	var edge:=[a,b]
	if not turn_cache.has(edge):
		var ok:=fits(b)
		var start: Vector2=DIRECTIONS[a.z];var finish: Vector2=DIRECTIONS[b.z]
		var angle:=start.angle_to(finish)
		# Fine angular sampling catches corners that fit at the quarter-turn
		# endpoints but sweep into the full bench or counter between them.
		for sample in range(1,32):
			if not ok:break
			if not layout.fits(position(a),start.rotated(angle*sample/32.0),false):ok=false;break
		turn_cache[edge]=ok
	return bool(turn_cache[edge])

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

func route(from: Vector2,heading: Vector2,to: Vector2,end_heading: Vector2) -> Array:
	last_expanded=0;_heap.clear()
	var start:=key(from,heading);var goal:=key(to,end_heading)
	if start.z<0 or goal.z<0 or not fits(start) or not fits(goal):return []
	if position(start).distance_to(from)>.001 or position(goal).distance_to(to)>.001:return []
	var cost: Dictionary={start:0.0};var previous: Dictionary={};var closed: Dictionary={}
	_push([position(start).distance_to(to),start])
	while not _heap.is_empty():
		var state: Vector3i=_pop()[1]
		if closed.has(state):continue
		closed[state]=true;last_expanded+=1
		if state==goal:
			var result: Array=[]
			while state!=start:
				var parent: Vector3i=previous[state]
				var delta:=position(state)-position(parent)
				result.push_front({"at":position(state),"heading":DIRECTIONS[state.z],"turn":state.z!=parent.z,"reverse":delta.dot(DIRECTIONS[state.z])<0})
				state=parent
			return result
		var dir: Vector2=DIRECTIONS[state.z]
		for movement in [1,-1]:
			var next:=Vector3i(state.x+int(dir.x)*movement,state.y+int(dir.y)*movement,state.z)
			if closed.has(next) or not can_move(state,next):continue
			_offer(state,next,STEP if movement>0 else STEP*1.2,to,cost,previous)
		for turn in [-1,1]:
			var next:=Vector3i(state.x,state.y,posmod(state.z+turn,4))
			if closed.has(next) or not can_turn(state,next):continue
			_offer(state,next,.38,to,cost,previous)
	return []

func _offer(state: Vector3i,next: Vector3i,extra: float,to: Vector2,cost: Dictionary,previous: Dictionary) -> void:
	var candidate: float=float(cost[state])+extra
	if candidate>=float(cost.get(next,INF)):return
	cost[next]=candidate;previous[next]=state
	_push([candidate+position(next).distance_to(to),next])
