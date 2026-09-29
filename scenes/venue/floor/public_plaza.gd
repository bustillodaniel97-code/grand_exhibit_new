extends RefCounted
## Bounded exterior population. Routes use the paved apron, never museum/support
## footprints. The building's economy and employee pool remain independent.
const Iso := preload("res://scenes/venue/floor/iso.gd")
const Character := preload("res://scenes/venue/floor/character.gd")
const Exhibits := preload("res://scenes/venue/floor/exhibits.gd")
const STEP := .25
const PUBLIC_DEPTH := 2.4
const MAX_PEOPLE := 4
var nodes: Array[Node2D] = []
var people: Array[Dictionary] = []
var reserved_activities: Dictionary = {}
var journeys: RefCounted
var fixtures: Array[Dictionary] = []
var activities: Array[Dictionary] = []
var obstacles: Array[Rect2] = []
var existing_fixtures: Array[Rect2] = []
var rooms: Array[Rect2] = []
var graph := AStarGrid2D.new()
var apron := Rect2()
var city: Node2D
var canvas: Node2D
var venue := ""
var bounds := Rect2()
var spread := 1.0
var spawn_points: Array[Vector2] = []
var elapsed := 0.0
var completed := {"rest":0,"feed":0,"dog":0}
var failed_routes := 0
var movement_steps := 0
var invalid_steps := 0
var crowd_wait_steps := 0
var crowd_detours := 0
var crowd_yields := 0
var _spawn_clock := 0.0
var _next_person := 0
var _activity_starts: Dictionary={}
var _activity_looks: Dictionary = {}
var _rng := RandomNumberGenerator.new()
var _shared_art: Dictionary = {}
var flocks: Array[Node2D] = []

func clear() -> void:
	for n in nodes:
		if is_instance_valid(n):
			n.get_parent().remove_child(n)
			n.queue_free()
	nodes.clear()
	people.clear()
	reserved_activities.clear()
	_activity_starts.clear()
	fixtures.clear()
	activities.clear()
	obstacles.clear()
	existing_fixtures.clear()
	rooms.clear()
	_shared_art.clear()
	flocks.clear()
	_activity_looks.clear()

func build(parent: Node2D, city_node: Node2D, theme: RefCounted, entrance_x: float, exit_x: float) -> void:
	clear()
	canvas = parent
	city = city_node
	venue = theme.id
	bounds = theme.bounds
	spread = theme.layout_spread
	apron = city.apron_bounds()
	elapsed = 0.0
	_spawn_clock = 0.0
	_next_person = 0
	failed_routes = 0
	movement_steps = 0
	invalid_steps = 0
	crowd_wait_steps = 0
	crowd_detours = 0
	crowd_yields = 0
	completed = {"rest":0,"feed":0,"dog":0}
	_rng.seed = hash(venue)
	for room in theme.rooms:rooms.append(room.rect)
	for obstacle in city.public_obstacles():obstacles.append(obstacle.grow(.16))
	# Legacy venue decorations also occupy the apron. Both actor paths and new
	# furniture placement must respect them, not only this plaza's own props.
	for spec in theme.props+theme.exhibits:
		if spec.get("layer","")=="wall" or spec.get("kind","") in ["hanging","hung_skeleton"]:continue
		var at := Exhibits.v2(spec.get("at"))
		var size := Exhibits.footprint(spec)
		if spec.get("kind","")=="bench":
			size = Vector2(float(spec.get("len",1.5)),.5) if spec.get("axis","x")=="x" else Vector2(.5,float(spec.get("len",1.5)))
		if size == Vector2.ZERO:
			size = Vector2(.6,.6)
			at -= size*.5
		var footprint := Rect2(at,size)
		existing_fixtures.append(footprint)
		obstacles.append(footprint.grow(.16))
	var document: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/outdoor_spaces.json"))
	var design: Dictionary = document[venue]
	# Door lanes are explicit no-furniture zones, including the separate exit.
	var lobby: Rect2 = theme.role("lobby").rect
	var door_lanes: Array[Rect2] = []
	var departure: Rect2=theme.role("departure").get("rect",lobby)
	for door in [Vector2(entrance_x,lobby.end.y),Vector2(exit_x,departure.end.y)]:
		door_lanes.append(Rect2(door.x-.9,door.y,1.8,apron.end.y-door.y))
	for entry in design.fixtures:
		var item: Dictionary = entry.duplicate(true)
		var at := _authored_point(item.at)
		var size := Vector2(1.5,.5) if item.kind == "bench" else Vector2(.6,.6)
		if item.kind in ["fountain","sundial"]:size = Vector2(1.5,1.5)
		var footprint := Rect2(at,size)
		var allowed := apron.encloses(footprint)
		for room in rooms:allowed = allowed and not room.grow(.25).intersects(footprint)
		for lane in door_lanes:allowed = allowed and not lane.intersects(footprint)
		for existing in existing_fixtures:allowed = allowed and not existing.intersects(footprint)
		if not allowed:
			push_error("Invalid plaza fixture %s %s" % [venue,item])
			continue
		item["at"] = at
		item["rect"] = footprint
		fixtures.append(item)
		obstacles.append(footprint.grow(.16))
		_add_fixture(item)
	for entry in design.activities:
		var activity: Dictionary = entry.duplicate(true)
		if activity.kind == "rest":
			var bench: Dictionary = {}
			for fixture in fixtures:
				if fixture.get("id","") == activity.get("fixture","") and fixture.kind == "bench":bench = fixture
			if bench.is_empty():
				push_error("Plaza seat has no matching bench: "+venue+str(activity))
				continue
			var bench_at: Vector2 = bench.at
			activity["at"] = bench_at + Vector2(.75,.95)
			activity["seat"] = bench_at + Vector2(.75,.30)
		else:
			activity["at"] = _authored_point(entry.at)
		activities.append(activity)
	var sidewalk_y: float = city.map_point(Vector2(0,18.42)).y
	spawn_points = [Vector2(bounds.position.x-6,sidewalk_y),Vector2(bounds.end.x+6,sidewalk_y)]
	_build_graph()
	for activity in activities:
		if route(spawn_points[0],activity.at).is_empty():push_error("Unreachable plaza activity: "+venue+str(activity))
		if activity.kind == "feed":
			var birds := _add_node("PlazaBirds",activity.at+Vector2(.35,.4))
			flocks.append(birds)
			birds.draw.connect(func() -> void:
				var feeder: Dictionary = {}
				for person in people:
					if activities[person.activity_index] == activity and person.state == "activity":feeder = person
				_draw_birds(birds,activity,feeder))

func _authored_point(raw: Array) -> Vector2:
	var point := Vector2(float(raw[0]),float(raw[1]))
	var authored := Rect2(bounds.position/spread,bounds.size/spread)
	for axis in 2:
		if point[axis] > authored.end[axis]:point[axis] = bounds.end[axis]+point[axis]-authored.end[axis]
		elif point[axis] < authored.position[axis]:point[axis] = bounds.position[axis]+point[axis]-authored.position[axis]
		else:point[axis] *= spread
	return point

func _build_graph() -> void:
	var start := Vector2i(floori((bounds.position.x-6.5)/STEP),floori(apron.position.y/STEP))
	var end := Vector2i(ceili((bounds.end.x+6.5)/STEP),ceili((apron.end.y+1.0)/STEP))
	graph.region = Rect2i(start,end-start+Vector2i.ONE)
	graph.cell_size = Vector2.ONE*STEP
	graph.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	graph.update()
	for y in range(start.y,end.y+1):
		for x in range(start.x,end.x+1):
			var id := Vector2i(x,y)
			graph.set_point_solid(id,not _line_clear(Vector2(id)*STEP,Vector2(id)*STEP,.02))

func walkable(g: Vector2) -> bool:
	var on_apron := apron.grow(-.24).has_point(g)
	var on_pavement := g.y >= apron.end.y+.12 and g.y <= apron.end.y+.57
	var ramp: Vector2 = city.ramp_top()
	var on_ramp := absf(g.x-ramp.x) < .80 and g.y >= ramp.y-.1 and g.y <= apron.end.y+.57
	if not (on_apron or on_pavement or on_ramp):return false
	for room in rooms:
		if room.grow(.20).has_point(g):return false
	for rect in obstacles:
		if rect.has_point(g):return false
	return true

## Exact segment/rectangle intervals prevent corner cuts that a sampled ray
## can miss between two otherwise-clear navigation cells.
func _interval(a: Vector2,b: Vector2,rect: Rect2) -> Vector2:
	var enter := 0.0
	var leave := 1.0
	for axis in 2:
		var delta: float = b[axis]-a[axis]
		if absf(delta)<.000001:
			if a[axis]<rect.position[axis] or a[axis]>rect.end[axis]:return Vector2.INF
		else:
			var near_: float = (rect.position[axis]-a[axis])/delta
			var far_: float = (rect.end[axis]-a[axis])/delta
			enter = maxf(enter,minf(near_,far_))
			leave = minf(leave,maxf(near_,far_))
			if enter>leave:return Vector2.INF
	return Vector2(enter,leave)

func _line_clear(a: Vector2,b: Vector2,margin: float = 0.0) -> bool:
	for room in rooms:
		if _interval(a,b,room.grow(.21+margin)).is_finite():return false
	for rect in obstacles:
		if _interval(a,b,rect.grow(.01+margin)).is_finite():return false
	var ramp: Vector2 = city.ramp_top()
	var surfaces := [apron.grow(-.24),
		Rect2(bounds.position.x-7,apron.end.y+.12,bounds.size.x+14,.45),
		Rect2(ramp.x-.80,ramp.y-.1,1.60,apron.end.y+.57-ramp.y+.1)]
	var intervals: Array[Vector2] = []
	for rect in surfaces:
		var interval := _interval(a,b,rect.grow(-margin))
		if interval.is_finite():intervals.append(interval)
	intervals.sort_custom(func(x: Vector2,y: Vector2) -> bool:return x.x<y.x)
	var covered := 0.0
	for interval in intervals:
		if interval.x>covered+.000001:return false
		covered = maxf(covered,interval.y)
	return covered>=1.0

func route(from: Vector2,to: Vector2) -> Array[Vector2]:
	var result:=_route(from,to,[],true)
	if result.is_empty() and OS.has_environment("GRAND_EXHIBIT_JOURNEY_DEBUG"):print("ROUTE_FAILURE ",venue," ",from," -> ",to)
	return result

func _route(from: Vector2,to: Vector2,avoid: Array,report_failure: bool) -> Array[Vector2]:
	var start := Vector2i((from/STEP).round())
	var end := Vector2i((to/STEP).round())
	var out: Array[Vector2] = []
	if not graph.is_in_boundsv(start) or not graph.is_in_boundsv(end):
		if report_failure:failed_routes += 1
		return out
	# A walker yielding between samples can be on clear pavement while
	# rounding to the kerb's solid cell. Connect to a visible neighboring
	# sample instead of stranding a physically valid continuous position.
	if graph.is_point_solid(start) and from.distance_to(Vector2(start)*STEP)>.0001:
		var best:=INF
		var original:=start
		for x in range(-1,2):
			for y in range(-1,2):
				var candidate:=original+Vector2i(x,y)
				if not graph.is_in_boundsv(candidate) or graph.is_point_solid(candidate):continue
				var at:=Vector2(candidate)*STEP
				if from.distance_to(at)<best and _line_clear(from,at) and _crowd_clear(from,at,avoid):
					start=candidate;best=from.distance_to(at)
	if graph.is_point_solid(start) or graph.is_point_solid(end):
		if report_failure:failed_routes += 1
		return out
	var raw := graph.get_point_path(start,end)
	if raw.is_empty():
		if report_failure:failed_routes += 1
		return out
	# The exact standing point can be clear while its rounded graph sample is
	# inside another person's margin. Start from the exact point in that case.
	if raw.size()>1 and not _crowd_clear(from,raw[0],avoid):raw.remove_at(0)
	# String-pull only through verified open pavement; never a straight-line
	# fallback when an A* route is missing.
	var cursor := from
	var i := 0
	while i < raw.size():
		var furthest := -1
		for j in range(i,raw.size()):
			if not _line_clear(cursor,raw[j],.02) or not _crowd_clear(cursor,raw[j],avoid):break
			furthest = j
		if furthest < 0:
			if report_failure:failed_routes += 1
			return []
		out.append(raw[furthest])
		cursor = raw[furthest]
		i = furthest+1
	if not _line_clear(cursor,to,.02) or not _crowd_clear(cursor,to,avoid):
		if report_failure:failed_routes += 1
		return []
	out.append(to)
	return out

static func _segment_gap(a: Vector2,b: Vector2,c: Vector2,d: Vector2) -> float:
	var ab := b-a;var cd := d-c
	var denominator := ab.cross(cd)
	if absf(denominator)>.00000001:
		var t := (c-a).cross(cd)/denominator
		var u := (c-a).cross(ab)/denominator
		if t>=0 and t<=1 and u>=0 and u<=1:return 0.0
	return minf(minf(a.distance_to(_nearest(a,c,d)),b.distance_to(_nearest(b,c,d))),
		minf(c.distance_to(_nearest(c,a,b)),d.distance_to(_nearest(d,a,b))))

static func _nearest(p: Vector2,a: Vector2,b: Vector2) -> Vector2:
	return a+(b-a)*clampf((p-a).dot(b-a)/maxf(a.distance_squared_to(b),.00000001),0,1)

func body_radius(p: Dictionary) -> float:
	return .20 if p.node.identity.get("age_group","")=="child" else .24

func _narrow_sections(p: Dictionary) -> Array:
	if p.get("passage_path",[])==p.path:return p.get("passage_sections",[])
	p.passage_path=p.path.duplicate()
	p.passage_sections=[]
	p.passage_from=p.pos
	var cursor: Vector2=p.pos
	for leg in p.path.size():
		var waypoint: Vector2=p.path[leg]
		var delta:=waypoint-cursor
		var pieces:=maxi(1,ceili(delta.length()/.5))
		var normal:=Vector2(-delta.y,delta.x).normalized()*.65
		for i in pieces:
			var a:=cursor+delta*float(i)/pieces
			var b:=cursor+delta*float(i+1)/pieces
			var middle:=(a+b)*.5
			if not _line_clear(middle,middle+normal) and not _line_clear(middle,middle-normal):
				p.passage_sections.append({"a":a,"b":b,"leg":leg})
		cursor=waypoint
	return p.passage_sections

func _crowd_obstacles(person: Dictionary,radius_override: float = -1.0,reserve_passages: bool = false) -> Array:
	var avoid: Array=[]
	var radius := body_radius(person) if radius_override<0 else radius_override
	for other in people:
		if other==person:continue
		avoid.append({"a":other.pos,"b":other.pos,"radius":radius+body_radius(other)+.06})
		if other.state=="stand_up":
			var seat_activity: Dictionary=activities[other.activity_index]
			avoid.append({"a":seat_activity.seat,"b":seat_activity.at,"radius":radius+body_radius(other)+.06})
		elif other.node.seated and other.state=="sit_down":
			var stance: Vector2=other.pos+Vector2.DOWN*other.node.seating_foot_distance()
			avoid.append({"a":other.pos,"b":stance,"radius":radius+body_radius(other)+.06})
		if reserve_passages and float(other.get("born",0))<=float(person.get("born",INF)):
			# Reserve upcoming one-person passages before either visitor enters.
			# Wide pavement stays open for crossing and overtaking.
			for section in _narrow_sections(other):
				var a: Vector2=section.a
				var b: Vector2=section.b
				# Following pedestrians share a corridor. Reserving its whole
				# length against the person already ahead makes both wait forever.
				if not person.get("path",[]).is_empty() and (person.path[0]-person.pos).normalized().dot((b-a).normalized())>.8:continue
				if section.leg==0:
					var direction: Vector2=other.path[0]-other.passage_from
					if (b-other.pos).dot(direction)<0:continue
					if (a-other.pos).dot(direction)<0:a=other.pos
				avoid.append({"a":a,"b":b,"radius":radius+body_radius(other)+.06,"reservation":true})
		if is_instance_valid(other.get("companion")):
			avoid.append({"a":other.companion_pos,"b":other.companion_pos,"radius":radius+.23})
			# A leash needs clearance, but must not be treated as a dog-sized
			# solid wall along its entire length.
			avoid.append({"a":other.pos,"b":other.companion_pos,"radius":radius+.025})
	return avoid

func _crowd_clear(a: Vector2,b: Vector2,avoid: Array,allow_reserved_escape: bool = false) -> bool:
	for obstacle in avoid:
		if allow_reserved_escape and obstacle.get("reservation",false):
			var old_gap := a.distance_to(_nearest(a,obstacle.a,obstacle.b))
			var new_gap := b.distance_to(_nearest(b,obstacle.a,obstacle.b))
			# A reservation cannot imprison a person already inside its area.
			# Physical body/dog obstacles remain enforced independently.
			if old_gap<float(obstacle.radius) and new_gap>=old_gap-.00001:continue
		if _segment_gap(a,b,obstacle.a,obstacle.b)<float(obstacle.radius)-.00001:return false
	return true

func _detour(p: Dictionary,avoid: Array,goal: Vector2 = Vector2.INF) -> Array[Vector2]:
	# Apply temporary occupancy to the same tested pavement graph, then restore
	# it before anybody else routes. Static furniture/wall cells are never opened.
	var changed: Array[Vector2i]=[]
	for obstacle in avoid:
		var radius: float=obstacle.radius
		var low: Vector2=Vector2(minf(obstacle.a.x,obstacle.b.x),minf(obstacle.a.y,obstacle.b.y))-Vector2.ONE*radius
		var high: Vector2=Vector2(maxf(obstacle.a.x,obstacle.b.x),maxf(obstacle.a.y,obstacle.b.y))+Vector2.ONE*radius
		for y in range(floori(low.y/STEP),ceili(high.y/STEP)+1):
			for x in range(floori(low.x/STEP),ceili(high.x/STEP)+1):
				var id := Vector2i(x,y)
				if graph.is_in_boundsv(id) and not graph.is_point_solid(id) and not _crowd_clear(Vector2(id)*STEP,Vector2(id)*STEP,[obstacle]):
					graph.set_point_solid(id,true);changed.append(id)
	var start := Vector2i((p.pos/STEP).round())
	if changed.has(start) and _crowd_clear(p.pos,p.pos,avoid):graph.set_point_solid(start,false)
	var path := _route(p.pos,p.path.back() if not goal.is_finite() else goal,avoid,false)
	for id in changed:graph.set_point_solid(id,false)
	if not path.is_empty():
		var direct:=_route(p.pos,path.back(),[],false)
		# Waiting briefly is preferable to a temporary crowd sending somebody
		# all the way around the back of the museum.
		if not direct.is_empty() and _path_length(p.pos,path)>_path_length(p.pos,direct)*1.35+2.0:return []
	return path

static func _path_length(from: Vector2,path: Array[Vector2]) -> float:
	var length:=0.0
	for point in path:length+=from.distance_to(point);from=point
	return length

func _begin_leg(p: Dictionary,goal: Vector2) -> void:
	p.yield_resume=Vector2.INF
	var static_path := route(p.pos,goal)
	if static_path.is_empty():
		p.path=[];p.pending_goal=Vector2.INF;p.state="route_blocked"
		return
	p.path=_detour(p,_crowd_obstacles(p,-1,true),goal)
	p.pending_goal=goal if p.path.is_empty() else Vector2.INF
	p.repath_in=.65

func _yield_route(p: Dictionary) -> Array[Vector2]:
	var blocker: Dictionary={}
	for other in people:
		if other==p or other.path.is_empty():continue
		var older := float(other.born)<float(p.born)
		# A dog's breadcrumb can be blocked by the older guest even after
		# its owner has started yielding. In that case strict age priority
		# deadlocks both: let the older guest make a courtesy step as well.
		var trapped_companion: bool=is_instance_valid(other.get("companion")) and (other.yield_resume as Vector2).is_finite() and float(other.blocked_time)>3.0 and float(p.blocked_time)>3.0
		if not older and not trapped_companion:continue
		if (p.pos as Vector2).distance_to(other.pos)<1.8:
			blocker=other;break
	if blocker.is_empty():return []
	var physical := _crowd_obstacles(p)
	var reserved := _crowd_obstacles(p,-1,true)
	var angle: float=(p.pos-blocker.pos).angle()
	for radius in [1.0,1.5,2.0,3.0]:
		for sample in 16:
			var a:=angle+TAU*float(sample)/16.0
			var target: Vector2=p.pos+Vector2(cos(a),sin(a))*radius
			if not walkable(target) or not _crowd_clear(target,target,reserved):continue
			# A clear continuous escape can exist even when the rounded start
			# cell is boxed in by temporary occupancy. Verify the entire short
			# segment against pavement and people before bypassing grid sampling.
			if _line_clear(p.pos,target,.02) and _crowd_clear(p.pos,target,physical):return [target]
			var path:=_detour(p,physical,target)
			if path.is_empty():continue
			var length:=0.0
			var cursor: Vector2=p.pos
			for waypoint in path:
				length+=cursor.distance_to(waypoint);cursor=waypoint
			if length<=3.5:return path
	return []

func _add_node(name_: String,g: Vector2) -> Node2D:
	var n := Node2D.new()
	n.name = name_
	canvas.add_child(n)
	n.position = Iso.to_screen(g)
	nodes.append(n)
	return n

func _add_fixture(item: Dictionary) -> void:
	var at: Vector2 = item.at
	var node := _add_node("Plaza_"+item.kind,at+item.rect.size*.5)
	if item.kind in ["bench","planter"]:
		var spec := {"kind":item.kind,"at":at,"museum_venue":venue,"len":1.5,"axis":"x","flip":false}
		if item.kind=="planter":spec["at"] = at+item.rect.size*.5
		else:node.position=Iso.to_screen(Exhibits.anchor(spec))
		var painter := Exhibits.painter(item.kind,spec)
		node.draw.connect(func() -> void:
			node.draw_set_transform(-node.position)
			painter.call(node))
	else:
		var texture := _texture("plaza-"+item.kind)
		if texture != null:
			node.draw.connect(func() -> void:_draw_sprite(node,texture,4.0,.7))
		else:
			node.draw.connect(func() -> void:
				node.draw_set_transform(-node.position)
				Iso.cyl(node,at+Vector2(.75,.75),.52,12,Color("#B0B4A1"))
				Iso.disc(node,at+Vector2(.75,.75),.43,13,Color("#5A9BA2")))

func _texture(key: String) -> Texture2D:
	if not _shared_art.has(key):
		var path := "res://art/environment/"+key+".png"
		_shared_art[key] = load(path) if ResourceLoader.exists(path) else null
	return _shared_art[key]

func _draw_sprite(n: Node2D,texture: Texture2D,ortho: float,target_z: float) -> void:
	var pixel_scale := (Iso.TILE.x / sqrt(2.0)) * ortho / texture.get_width()
	var size := Vector2(texture.get_size()) * pixel_scale
	var target_lift := target_z * (Iso.TILE.x/sqrt(2.0)) * sqrt(5.0)/3.0
	n.draw_texture_rect(texture,Rect2(-size*.5-Vector2(0,target_lift),size),false)

func advance(dt: float) -> void:
	var previous_frame := int(elapsed*8.0)
	elapsed += dt
	if int(elapsed*8.0) != previous_frame:
		for flock in flocks:flock.queue_redraw()
	_spawn_clock += dt
	if _spawn_clock >= 3.0 and people.size()+(journeys.public_count() if journeys!=null else 0) < MAX_PEOPLE:
		_spawn_clock = 0.0
		_spawn()
	for p in people.duplicate():
		var node: Node2D = p.node
		if p.state == "arrive" and activities[p.activity_index].kind == "feed":
			node.prepare_bird_feeding()
		if p.state in ["arrive","sit_down"] and activities[p.activity_index].kind == "rest":
			node.prepare_seating()
		node.walk_backwards=false
		var old: Vector2 = p.pos
		if not p.path.is_empty():
			var target: Vector2 = p.path[0]
			var pace: float = node.preferred_walk_speed()
			# The reserved seat corridor includes its final step onto clear
			# paving; normal detours resume after this short corridor is vacated.
			var seating: bool = p.state in ["sit_down","stand_up"]
			var yielding: bool=(p.yield_resume as Vector2).is_finite()
			var avoid := _crowd_obstacles(p,-1,not yielding)
			p.repath_in = maxf(0,float(p.repath_in)-dt)
			if not seating and p.repath_in<=0 and not _crowd_clear(old,old.move_toward(target,1.1),avoid,true):
				p.repath_in=.65
				var alternate := _detour(p,avoid)
				if not alternate.is_empty():
					p.path=alternate;target=p.path[0];crowd_detours+=1
			var next := old.move_toward(target,dt*pace)
			var can_move := _crowd_clear(old,next,avoid,true)
			if can_move and is_instance_valid(p.get("companion")):
				var next_dog := _companion_target(p,next)
				var dog_avoid := _crowd_obstacles(p,.17)
				can_move = _crowd_clear(p.companion_pos,next_dog,dog_avoid) and _crowd_clear(next,next_dog,_crowd_obstacles(p,.025))
			if can_move:p.pos=next;p.blocked_time=0.0
			else:
				pace=0.0;crowd_wait_steps+=1;p.blocked_time+=dt
				if not seating and p.blocked_time>1.5 and p.repath_in<=.05:
					var aside:=_yield_route(p)
					if not aside.is_empty():
						# A moving companion can invalidate an earlier courtesy
						# path. Replan it without losing the original destination.
						if not yielding:p.yield_resume=p.path.back()
						p.path=aside;target=p.path[0];p.blocked_time=0.0;crowd_yields+=1
			if p.pos.is_equal_approx(target):p.path.pop_front()
			node.walking = not old.is_equal_approx(p.pos)
			node.walk_backwards=p.state=="sit_down"
			node.record_motion(p.pos-old,dt,Vector2.DOWN if node.walk_backwards else p.pos-old)
			if node.walking:movement_steps += 1
			# The last half tile of a seat approach is intentionally inside the
			# owned bench footprint. No other furniture gets this exemption.
			if not seating and (not walkable(p.pos) or not _line_clear(old,p.pos)):
				if invalid_steps < 3:print("PLAZA_STEP_INVALID ",venue," ",p.state," ",old," -> ",p.pos)
				invalid_steps += 1
		else:
			node.walking = false
			if (p.yield_resume as Vector2).is_finite():
				_begin_leg(p,p.yield_resume)
			elif (p.pending_goal as Vector2).is_finite():
				p.blocked_time+=dt
				p.repath_in-=dt
				if p.repath_in<=0:
					p.repath_in=.65
					p.path=_detour(p,_crowd_obstacles(p,-1,true),p.pending_goal)
					if not p.path.is_empty():p.pending_goal=Vector2.INF;p.blocked_time=0.0
					elif p.blocked_time>1.5:
						var aside:=_yield_route(p)
						if not aside.is_empty():
							p.yield_resume=p.pending_goal;p.pending_goal=Vector2.INF;p.path=aside;p.blocked_time=0.0;crowd_yields+=1
			else:_finish_leg(p,dt)
		if not people.has(p):continue
		var feeding: bool = p.state == "activity" and activities[p.activity_index].kind == "feed" and p.path.is_empty() and not (p.pending_goal as Vector2).is_finite()
		if feeding:
			p.activity_time += dt
			# Birds occupy the front-facing quadrant of this real standing point.
			node.set_motion_vector(Vector2(.6,.4),0)
		node.set_bird_feeding(feeding,p.activity_time)
		_place(node,p.pos)
		if is_instance_valid(p.get("companion")):
			_update_companion(p,dt,old)

func _visitor_slot(kind: String) -> int:
	if not _activity_looks.has(kind):
		var deck: Array = range(Character.LOOK_COUNT)
		for i in range(deck.size()-1,0,-1):
			var j := _rng.randi_range(0,i)
			var swap: int = deck[i];deck[i]=deck[j];deck[j]=swap
		_activity_looks[kind]=deck
	var deck: Array = _activity_looks[kind]
	for attempt in deck.size():
		var slot: int = deck.pop_front()
		deck.append(slot)
		var used := false
		for p in people:
			if p.node.look_slot()==slot:used=true;break
		if not used:return slot
	return int(deck[0])

func activity_available(candidate: int) -> bool:
	var occupied: Array=reserved_activities.keys()
	for p in people:occupied.append(int(p.activity_index))
	for index in occupied:
		if index==candidate:return false
		# The dog circuit crosses both standing and bench step-out areas.
		if activities[candidate].kind=="dog" or activities[index].kind=="dog":return false
	return true

func _spawn() -> void:
	if activities.is_empty():return
	# A dog and leash need the full circuit, including bench step-out space.
	# When that activity is due, let existing visits finish before admitting
	# more sitters; otherwise a steady stream can starve its reservation.
	var dog_turn:=false
	for i in activities.size():
		if activities[i].kind!="dog":continue
		var least:=true
		for j in activities.size():
			if j!=i and int(_activity_starts.get(i,0))>=int(_activity_starts.get(j,0)):least=false
		if least:
			dog_turn=true
			if not activity_available(i):return
	var activity_index := -1
	var least_started:=2147483647
	for offset in activities.size():
		var candidate := (_next_person+offset)%activities.size()
		if dog_turn and activities[candidate].kind!="dog":continue
		if activity_available(candidate) and int(_activity_starts.get(candidate,0))<least_started:
			activity_index = candidate
			least_started=int(_activity_starts.get(candidate,0))
	if activity_index<0:return
	var activity: Dictionary = activities[activity_index]
	var start: Vector2 = spawn_points[_next_person%2]
	for person in people:
		# The remote sidewalk is too narrow for opposing traffic. A departure
		# reserves its approach before a new visitor enters from that end.
		if person.pos.distance_to(start)<.65 or (person.state=="exit" and person.home==start):return
	var path := route(start,activity.at)
	if path.is_empty():return
	path=_detour({"pos":start},_crowd_obstacles({},.24,true),activity.at)
	if path.is_empty():return
	var character := Character.new()
	character.name = "PlazaVisitor"
	# Each activity has its own full visitor deck. Coupling appearance to the
	# four activity slots biased the demographic of every repeated activity.
	character.set_look_slot(_visitor_slot(activity.kind))
	canvas.add_child(character)
	nodes.append(character)
	var p := {"node":character,"pos":start,"path":path,"state":"arrive","activity_index":activity_index,
		"wait":0.0,"activity_time":0.0,"repath_in":0.0,"pending_goal":Vector2.INF,"yield_resume":Vector2.INF,"blocked_time":0.0,"born":elapsed,"home":start,"walks":0,"trail":[start],"companion_pos":start,"trail_distance":0.0}
	if activity.kind == "dog":
		p.companion = _add_node("PlazaDog",start)
		p.leash = _add_node("DogLeash",start)
		var dog: Node2D = p.companion
		dog.draw.connect(func() -> void:
			var frame := int(elapsed*8.0)%4 if character.walking else 0
			var tex := _texture("plaza-dog-%02d"%frame)
			if tex != null:_draw_sprite(dog,tex,2.0,.35))
		p.leash.draw.connect(func() -> void:
			var a := character.public_hand_position()
			var b := Iso.to_screen(p.companion_pos)+Vector2(0,city.surface_drop(p.companion_pos)-8)
			var points := PackedVector2Array()
			for i in 9:
				var t := float(i)/8.0
				points.append(a.lerp(b,t)+Vector2(0,sin(t*PI)*3.0)-p.leash.position)
			p.leash.draw_polyline(points,Color("#796749"),1.2,true))
	if journeys==null:
		people.append(p);_place(character,start)
	elif not journeys.arrive_public(p):
		for key in ["node","companion","leash"]:
			if is_instance_valid(p.get(key)):
				nodes.erase(p[key]);p[key].queue_free()
		return
	_activity_starts[activity_index]=int(_activity_starts.get(activity_index,0))+1
	_next_person = activity_index+1

func _finish_leg(p: Dictionary,dt: float) -> void:
	var activity: Dictionary = activities[p.activity_index]
	match p.state:
		"arrive":
			if activity.kind == "rest":
				p.state = "sit_down"
				p.path = [activity.seat+Vector2.DOWN*p.node.seating_foot_distance()]
			else:
				p.state = "activity"
				p.wait = 12.0 if activity.kind == "feed" else 3.0
		"sit_down":
			if not p.node.seated:
				if not p.node.begin_seating(Vector2.DOWN,Vector2.ZERO):_leave(p);return
				# The action origin is under the hips; its first frame's shoes
				# exactly match the stance just reached by the approach walk.
				p.pos=activity.seat
			if not p.node.advance_seating(dt,true):return
			p.state = "activity"
			p.wait = 16.0
		"activity":
			p.wait -= dt
			if p.wait > 0:return
			if activity.kind == "dog" and p.walks < 2:
				var target := _authored_point(activity.walk[p.walks])
				_begin_leg(p,target)
				p.walks += 1
				p.wait = 3.0
			elif activity.kind == "rest":
				# Wait on the bench until the WHOLE exit is available, then hold
				# it through the rise and step-out. Reserving only the shoes let
				# passing visitors strand a standing guest halfway off the bench.
				if not _crowd_clear(p.pos,activity.at,_crowd_obstacles(p)):return
				p.state = "stand_up"
			else:_leave(p)
		"stand_up":
			if p.node.seated:
				if not p.node.advance_seating(dt,false):return
				p.pos+=Vector2.DOWN*p.node.seating_foot_distance()
				p.node.end_seating()
				p.path=[activity.at]
			else:_leave(p)
		"exit":
			if journeys!=null:
				if not journeys.depart_public(p):return
				completed[activity.kind]+=1;people.erase(p);return
			completed[activity.kind] += 1
			for key in ["node","companion","leash"]:
				if is_instance_valid(p.get(key)):
					var n: Node2D = p[key]
					nodes.erase(n)
					n.get_parent().remove_child(n)
					n.queue_free()
			people.erase(p)

func _leave(p: Dictionary) -> void:
	p.state = "exit"
	if journeys!=null:
		p.city_plan=journeys.plan(null,false)
		# Leave the activity by its nearest pavement access; the city journey
		# then follows the open curb to the destination. Sending every park
		# guest across the whole narrow plaza creates avoidable head-on jams.
		var left: Vector2=city.map_point(city.NEAR_WALK_LEFT)
		var right: Vector2=city.map_point(city.NEAR_WALK_RIGHT)
		p.city_plan.entry=left if p.pos.distance_to(left)<p.pos.distance_to(right) else right
		_begin_leg(p,p.city_plan.entry)
	else:_begin_leg(p,p.home)

func _place(n: Node2D,g: Vector2) -> void:
	if not is_instance_valid(n) or not n.is_inside_tree():return
	n.position = Iso.to_screen(g)+Vector2(0,city.surface_drop(g))
	if n is Character:
		n.scale = Vector2.ONE*n.age_scale()

func _companion_target(p: Dictionary,next: Vector2) -> Vector2:
	var trail: Array=p.trail.duplicate();trail.append(next)
	var distance: float=p.trail_distance+(p.pos as Vector2).distance_to(next)
	var index:=0
	while index<trail.size()-1:
		var segment: float=(trail[index] as Vector2).distance_to(trail[index+1])
		if distance-segment<.52:break
		distance-=segment;index+=1
	return trail[index]

func _update_companion(p: Dictionary,_dt: float,old: Vector2) -> void:
	# Follow the owner's actual walked polyline. A perpendicular offset would
	# cut corners through benches, walls and the slab edge.
	var moved: float = old.distance_to(p.pos)
	if moved > 0.00001:
		p.trail.append(p.pos)
		p.trail_distance += moved
		while p.trail.size() > 1:
			var length: float = (p.trail[0] as Vector2).distance_to(p.trail[1])
			if p.trail_distance-length < .52:break
			p.trail_distance -= length
			p.trail.pop_front()
		p.companion_pos = p.trail[0]
	_place(p.companion,p.companion_pos)
	p.companion.scale.x = -1.0 if p.node.facing < 0 else 1.0
	p.companion.queue_redraw()
	p.leash.position = p.companion.position
	p.leash.queue_redraw()

func bird_position(activity: Dictionary,index: int,time: float) -> Vector2:
	var phase := time*1.6+index*2.1
	return activity.at+Vector2(.3,.4)+Vector2(cos(phase*.28)*.18+float(index)*.20,sin(phase*.28)*.10)

func _draw_birds(node: Node2D,activity: Dictionary,p: Dictionary) -> void:
	var tex := _texture("plaza-pigeon")
	if tex == null:return
	for i in 3:
		var phase := elapsed*1.6+i*2.1
		var ground := bird_position(activity,i,elapsed)
		if not walkable(ground):continue
		var at := Iso.to_screen(ground)-node.position
		var hop := maxf(0,sin(phase*3.0))*1.8
		node.draw_set_transform(at+Vector2(0,-hop))
		_draw_sprite(node,tex,1.0,.15)
	if p.get("state","") == "activity":
		node.draw_set_transform(Vector2.ZERO)
		var flight := fposmod(float(p.activity_time),Character.ActivitySprites.DURATION)-Character.ActivitySprites.RELEASE_TIME
		if flight < 0 or flight > .9:return
		for i in 4:
			var t := clampf((flight-float(i)*.025)/.70,0,1)
			if flight < float(i)*.025:continue
			var a: Vector2 = p.node.public_hand_position(true)-node.position
			var b := Iso.to_screen(bird_position(activity,i%3,elapsed))-node.position
			node.draw_circle(a.lerp(b,t)+Vector2(0,-sin(t*PI)*5),.9,Color("#E0C998"))
