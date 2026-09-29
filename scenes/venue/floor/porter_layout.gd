extends RefCounted
## Measured standing footprint of the original trolley: body plus forward cart.
## Allocation checks the whole parked footprint, not only a free foot coordinate.
const LENGTH := .68
const HALF_WIDTH := .24
const BODY_GAP := .76
const DIRECTIONS := [Vector2.DOWN,Vector2.RIGHT,Vector2.UP,Vector2.LEFT]
var floor_node: Node
var fixed_staff: Array[Vector2] = []
var claimed: Array[Dictionary] = []
var counters: Array[Dictionary] = []
var homes: Array[Dictionary] = []
var drops: Array[Dictionary] = []
var failures: Array[String] = []
var counter_size := Vector2(1.7,.6)
var counter_rects: Array[Rect2] = []
var flat_ground := false
var _height_cells: Dictionary = {}
var _footprint_offsets: Dictionary = {}
## Memoized fits() outcomes keyed [at, heading, check_claims]. fits() is a
## pure function of layout-configure state (nav solidity, heights, counters,
## staff, claims) plus its arguments: claims/staff/counters only mutate in
## configure(), and structural nav writes funnel through _rebuild_navigation(),
## which clears this alongside configure(). Temporary admission masks restore
## synchronously inside one call, so they never leak into cached reads.
## Without this, oriented A* pays ~13us per fits call and up to 31 calls per
## fresh turn edge — a single cold intent search costs ~1.4s of compute while
## the dispatch budget only releases 1.5ms per tick, so a new venue's couriers
## stand at spawn for sim-minutes before their first delivery.
var _fit_cache: Dictionary = {}
## Nav object the cache was built against. _rebuild_navigation() replaces the
## grid wholesale, so a changed identity invalidates every entry even if an
## explicit clear were ever missed.
var _fit_nav: AStarGrid2D = null
var _fit_hits := 0
var _fit_misses := 0
## True while configure() is progressively rebuilding counters/staff/claims.
## fits() evaluated mid-configure observes partial state that later queries
## must not reuse, so the cache is bypassed entirely until configure() ends.
var _configuring := false
const FIT_CACHE_LIMIT := 32768

func footprint(at: Vector2,heading: Vector2) -> Array[Vector2]:
	var right:=Vector2(heading.y,-heading.x)
	var points: Array[Vector2]=[]
	for forward in [-.20,0.0,.22,.45,LENGTH]:
		for side in [-HALF_WIDTH,0.0,HALF_WIDTH]:points.append(at+heading*forward+right*side)
	return points

func _offsets(heading: Vector2) -> Array:
	if not _footprint_offsets.has(heading):
		# Planner turns use a finite set of angles; keep the cache bounded if
		# a visual review supplies arbitrary interpolated headings instead.
		if _footprint_offsets.size()>=256:_footprint_offsets.clear()
		_footprint_offsets[heading]=footprint(Vector2.ZERO,heading)
	return _footprint_offsets[heading]

func _height_at(point: Vector2) -> float:
	var cell:=Vector2i(floori(point.x),floori(point.y))
	if _height_cells.has(cell):return _height_cells[cell]
	var area:=Rect2(Vector2(cell),Vector2.ONE)
	var touches_room:=false
	for room in floor_node._theme.rooms:
		var rect: Rect2=room.rect
		if rect.encloses(area) and room.level==room.rise_to:
			var height: float=floor_node.Iso.level_lift(room.level)
			_height_cells[cell]=height;return height
		if rect.intersects(area):touches_room=true
	if not touches_room:_height_cells[cell]=0.0;return 0.0
	# Fractional room edges and ramps keep their exact authored calculation.
	return floor_node._theme.lift_at(point)

func fits(at: Vector2,heading: Vector2,check_claims: bool=true) -> bool:
	if _configuring:
		return _fits_uncached(at, heading, check_claims)
	if _fit_nav != floor_node._nav:
		_fit_cache.clear()
		_fit_nav = floor_node._nav
	var key := [at, heading, check_claims]
	if _fit_cache.has(key):
		_fit_hits += 1
		return bool(_fit_cache[key])
	_fit_misses += 1
	var result := _fits_uncached(at, heading, check_claims)
	# When full, keep serving hot entries rather than clearing: clearing under
	# thrash would wipe the useful cardinal entries along with one-off rotated
	# turn samples. New keys simply compute fresh until the next invalidation.
	if _fit_cache.size() < FIT_CACHE_LIMIT:
		_fit_cache[key] = result
	return result

func clear_fit_cache() -> void:
	_fit_cache.clear()

func _fits_uncached(at: Vector2,heading: Vector2,check_claims: bool=true) -> bool:
	var lift: float=0.0 if flat_ground else _height_at(at)
	var nav: AStarGrid2D=floor_node._nav
	for offset in _offsets(heading):
		var point: Vector2=at+offset
		var id:=Vector2i(roundi(point.x*4),roundi(point.y*4))
		if not nav.region.has_point(id) or nav.is_point_solid(id):return false
		if not flat_ground and absf(_height_at(point)-lift)>.5:return false
		# The shared walking grid historically reserves only a small disc at a
		# counter anchor. A trolley must clear the actual rotated desk rectangle.
		for rect in counter_rects:
			if point.x>rect.position.x and point.x<rect.end.x and point.y>rect.position.y and point.y<rect.end.y:return false
	for staff in fixed_staff:
		if staff.distance_squared_to(at)<BODY_GAP*BODY_GAP:return false
		if Geometry2D.get_closest_point_to_segment(staff,at,at+heading*LENGTH).distance_squared_to(staff)<.25:return false
	if check_claims:
		for other in claimed:
			if at.distance_to(other.at)<BODY_GAP:return false
			var pair:=Geometry2D.get_closest_points_between_segments(at,at+heading*LENGTH,other.at,other.at+other.heading*LENGTH)
			if pair[0].distance_to(pair[1])<HALF_WIDTH*2+.12:return false
	return true

func pick(candidates: Array,origin: Vector2,max_distance: float,room: Rect2=Rect2()) -> Dictionary:
	for candidate in candidates:
		# Parking and oriented movement share the same quarter-tile lattice.
		# Recheck the entire footprint after snapping; never snap a valid point
		# into a desk merely to make it addressable by the route graph.
		var at: Vector2=(candidate.at*4.0).round()*.25
		candidate["at"]=at
		if at.distance_to(origin)>max_distance:continue
		if room.has_area() and not room.has_point(at):continue
		if not fits(at,candidate.heading):continue
		var approach: Vector2=at-candidate.heading*.75
		var clear:=true
		for step in [.25,.5,.75]:
			if not fits(at-candidate.heading*step,candidate.heading,false):clear=false;break
		if not clear:continue
		if floor_node._nav_ids(floor_node._vault_entry,approach).is_empty():continue
		candidate["approach"]=approach
		claimed.append(candidate);return candidate
	return {}

func around(origin: Vector2,preferred: Vector2,radius: int) -> Array:
	var candidates: Array=[]
	var center: Vector2i=floor_node._nav_id(origin)
	for r in range(radius+1):
		for y in range(-r,r+1):
			for x in range(-r,r+1):
				if maxi(absi(x),absi(y))!=r:continue
				var at:=Vector2(center+Vector2i(x,y))*.25
				for dir in [preferred,Vector2(preferred.y,-preferred.x),-preferred,Vector2(-preferred.y,preferred.x)]:
					candidates.append({"at":at,"heading":dir})
	return candidates

func configure(owner: Node) -> void:
	# Bypass the fits memo for the whole progressive rebuild: counters, staff
	# and claims accumulate dock by dock, so an entry stored under partial
	# state must never be served to a later pick. Single exit below re-arms
	# the cache; keep it that way if this function ever gains an early return.
	_configuring = true
	_height_cells.clear();_footprint_offsets.clear();_fit_cache.clear();_fit_nav = null
	floor_node=owner;fixed_staff.clear();claimed.clear();counters.clear();homes.clear();drops.clear();failures.clear()
	counter_size=floor_node.Exhibits.v2(floor_node._theme.role("queue").get("queue",{}).get("counter_size"),Vector2(1.7,.6))
	flat_ground=floor_node._theme.levels()==[0]
	counter_rects.clear()
	for w in floor_node._windows_active:
		var station: Dictionary=floor_node._admissions.stations[w]
		var size: Vector2=counter_size if station.front.x==0 else Vector2(counter_size.y,counter_size.x)
		counter_rects.append(Rect2(station.center-size*.5,size).grow(.08))
	for w in floor_node._windows_active:fixed_staff.append(floor_node._admissions.point(w,Vector2(0,-.7)))
	fixed_staff.append_array(floor_node._stations("gallery"));fixed_staff.append_array(floor_node._stations("promotions"))
	for w in floor_node._max_windows:
		var station: Dictionary=floor_node._admissions.stations[w]
		var service_room: Rect2=floor_node._theme.by_id[station.room].rect
		var candidates: Array=[]
		# Park beside the service surface, facing it; do not stand behind its cashier.
		for side in [1.0,-1.0]:
			for width in [1.20,1.45,1.70]:
				for depth in [-.70,-.95,-.45]:
					for heading in [station.front,station.right,-station.right,-station.front]:
						candidates.append({"at":floor_node._admissions.point(w,Vector2(side*width,depth)),"heading":heading})
		var selected:=pick(candidates,station.center,2.15,service_room)
		if selected.is_empty():
			var fallback: Array=[]
			for candidate in around(station.porter,station.front,12):
				var delta: Vector2=candidate.at-station.center
				# Never solve staff circulation by parking in the visitors' queue.
				if delta.dot(station.front)>.15 and absf(delta.dot(station.right))<1.1:continue
				fallback.append(candidate)
			selected=pick(fallback,station.center,2.4,service_room)
		if selected.is_empty():failures.append("counter:%d"%w)
		counters.append(selected)
	var store: Dictionary=floor_node._theme.role("store")
	var room: Rect2=store.rect
	for i in 3:
		var origin: Vector2=floor_node._vault_drop+Vector2(float(i)-1,0)
		var selected:=pick(around(origin,Vector2.DOWN,12),floor_node._vault_drop,3.0,room)
		if selected.is_empty():failures.append("drop:%d"%i)
		drops.append(selected)
	# Each courier owns a bay for unloading and standby. Six separate reserved
	# spaces for three people needlessly consumed the archive's circulation aisle.
	homes=drops.duplicate(true)
	_configuring = false
