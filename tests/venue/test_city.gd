extends SceneTree
## City suite: the surround has to be alive, behind the museum, and untappable.
##
## Three defects this exists to catch, all of them silent:
##   · draw order. z_index is global within a canvas layer, so the surround is
##     kept behind the museum by Y-sort and a one-pixel lift instead. A tie at
##     y = 0 would resolve on child order alone, and the day someone reorders
##     _ready() the lawn paints over the gallery floor with no error anywhere.
##   · dead traffic. Cars that stop moving, or that wrap inside the visible wedge
##     of road, look worse than no cars at all — and neither shows up in a still.
##   · stolen taps. The surround covers most of the canvas. If it ever became a
##     Control, or drew inside a room rect, it would eat the upgrade sheet.
## Run: godot --headless --path <repo> -s tests/venue/test_city.gd (exit 0 pass)

const Iso := preload("res://scenes/venue/floor/iso.gd")
const City := preload("res://scenes/venue/floor/city.gd")

var _fail: int = 0
var _floor: Control
var _city: Node2D
var _frames: int = 0
var _t: float = 0.0
var _done: bool = false
var _last_cars: Array[Vector2] = []
var _odo := PackedFloat32Array()
var _max_gy: float = 0.0
var _min_alpha: float = 1.0

func check(cond: bool, msg: String) -> void:
	if cond:
		print("PASS: ", msg)
	else:
		_fail += 1
		printerr("FAIL: ", msg)

func _initialize() -> void:
	_check_layout()
	_check_footprint_remap()
	_boot_floor()

# --- the surround follows the plan --------------------------------------------
##
## Every scenery position in city.gd — the apron, the kerb, the hedges, the
## neighbouring blocks — is authored against ONE nominal 15x17 footprint. The
## first venue with a different plan (a 16x18 L) put a hedge through its east
## wing and a neighbouring block under its floor, which on screen reads as the
## museum being pasted onto a different picture.
##
## set_footprint() remaps the surround onto the plan the venue actually has. Two
## properties have to hold, and neither is visible in a still:
##   · identity at nominal, so the venues authored before it are untouched
##   · no scenery inside any room, for every venue in the data file
func _check_footprint_remap() -> void:
	var city: Node2D = City.new()

	# Identity when the plan is the one everything was authored against.
	city.set_footprint(City.NOMINAL)
	var same := true
	for g in [Vector2(-4.3, 0.4), Vector2(16.6, 2.0), City.STREET_G, City.CANOPY_G]:
		same = same and city.map_point(g).is_equal_approx(g)
	check(same, "a nominal 15x17 plan maps every scenery point to itself")
	check(city.canopy_offset().is_equal_approx(Vector2.ZERO),
		"and moves the entrance canopy not at all")

	# A bigger plan pushes the surround OUT, keeping its clearance rather than
	# scaling it — a stretched road would read as a motorway.
	city.set_footprint(Rect2(0.0, 0.0, 18.0, 20.0))
	var east: Vector2 = city.map_point(Vector2(16.6, 2.0))
	check(is_equal_approx(east.x, 19.6),
		"a hedge 1.6 tiles east of a 15-wide plan sits 1.6 east of an 18-wide one "
			+ "(got %.2f, want 19.60)" % east.x)
	check(city.map_point(Vector2(7.5, 8.5)).is_equal_approx(Vector2(9.0, 10.0)),
		"a point on the entrance axis stays on it as the plan grows")

	# The real claim: sweep every authored venue.
	for entry in _authored_venues():
		var rooms: Array = entry["rooms"]
		city.set_footprint(entry["bounds"])
		var intruders: Array = []
		for g in _scenery_points(String(entry["surround"])):
			var q: Vector2 = city.map_point(g)
			for r in rooms:
				# A quarter tile of slack: the forecourt planters deliberately
				# stand ~0.35 outside the lobby's front wall, flanking the doors.
				if (r as Rect2).grow(-0.25).has_point(q):
					intruders.append("%.1f,%.1f" % [q.x, q.y])
					break
		check(intruders.is_empty(),
			"%s: no surround scenery lands inside a room%s"
				% [entry["id"], "" if intruders.is_empty()
					else " (%d: %s)" % [intruders.size(), str(intruders.slice(0, 3))]])
	city.free()

## Venues with a plan of their own, as {id, surround, rooms, bounds}. Read from
## the data file rather than through DataLoader so this runs before autoloads.
func _authored_venues() -> Array:
	var out: Array = []
	var f: FileAccess = FileAccess.open("res://data/venues.json", FileAccess.READ)
	if f == null:
		return out
	var doc: Variant = JSON.parse_string(f.get_as_text())
	if not (doc is Dictionary):
		return out
	for v in (doc as Dictionary).get("venues", []):
		var theme: Dictionary = (v as Dictionary).get("theme", {})
		if theme.has("extends") or not theme.has("rooms"):
			continue
		var rooms: Array = []
		var bounds := Rect2()
		for r in theme["rooms"]:
			var a: Array = (r as Dictionary)["rect"]
			var rr := Rect2(float(a[0]), float(a[1]), float(a[2]), float(a[3]))
			rooms.append(rr)
			bounds = rr if bounds.size == Vector2.ZERO else bounds.merge(rr)
		out.append({
			"id": str((v as Dictionary).get("id", "?")),
			"surround": str(theme.get("surround", "parkland")),
			"rooms": rooms, "bounds": bounds,
		})
	return out

## Every ground contact point a style plants, in nominal grid space. Hedges are
## SAMPLED along their run: an endpoint test misses one that crosses a wing.
func _scenery_points(style_name: String) -> Array:
	var def: Dictionary = City.style_def(style_name)
	var pts: Array = []
	for b in def.get("blocks", []):
		pts.append(Vector2(float(b[0]), float(b[1])))
		pts.append(Vector2(float(b[0]) + float(b[2]), float(b[1]) + float(b[3])))
	for key in ["trees", "pines", "near_trees", "planters", "lamps"]:
		for t in def.get(key, []):
			pts.append(Vector2(float(t[0]), float(t[1])))
	for h in def.get("hedges", []):
		var a := Vector2(float(h[0]), float(h[1]))
		var b := Vector2(float(h[2]), float(h[3]))
		for i in 9:
			pts.append(a.lerp(b, float(i) / 8.0))
	return pts

# --- static layout, no scene needed -------------------------------------------

func _check_layout() -> void:
	check(Iso.on_canvas(City.STREET_G, 26.0),
		"the street spawn is on canvas with margin (%s -> %s)"
			% [City.STREET_G, Iso.to_screen(City.STREET_G)])
	check(City.STREET_G.y > Iso.GRID.y,
		"the street spawn is OUTSIDE the museum footprint (gy %.2f > %.0f)"
			% [City.STREET_G.y, Iso.GRID.y])
	check(City.CANOPY_G.y > Iso.GRID.y and Iso.on_canvas(City.CANOPY_G, 26.0),
		"the canopy stands outside the facade and on canvas")
	# The approach has to be long enough to read as walking in, not as a nudge.
	check(City.STREET_G.distance_to(Vector2(12.9, 16.3)) > 1.4,
		"the approach from street to door is at least 1.4 tiles")
	# A lane must wrap outside the visible window or cars appear from nowhere.
	for gy in [City.LANE_OUT, City.LANE_IN]:
		var span: Vector2 = City.lane_span(gy)
		check(not Iso.on_canvas(Vector2(span.x, gy)) and not Iso.on_canvas(Vector2(span.y, gy)),
			"lane %.2f wraps off canvas at both ends (%.1f .. %.1f)" % [gy, span.x, span.y])
	check(City.APRON_B.y < City.SIDEWALK_B and City.SIDEWALK_B <= City.KERB_B
			and City.KERB_B < City.ROAD_B,
		"apron, pavement, kerb and road are ordered outward from the building")

# --- live floor ----------------------------------------------------------------

func _boot_floor() -> void:
	seed(20260725)
	for pair in [["EventBus", "res://autoload/event_bus.gd"],
			["DataLoader", "res://autoload/data_loader.gd"],
			["ClockGuard", "res://autoload/clock_guard.gd"],
			["Analytics", "res://autoload/analytics.gd"],
			["AdService", "res://autoload/ad_service.gd"],
			["IAPService", "res://autoload/iap_service.gd"],
			["GameState", "res://autoload/game_state.gd"],
			["SaveSystem", "res://autoload/save_system.gd"],
			["Economy", "res://autoload/economy.gd"]]:
		if root.has_node(pair[0]):
			continue
		var n: Node = (load(pair[1]) as GDScript).new()
		n.name = pair[0]
		root.add_child(n)
	# Doctoring GameState with SaveSystem's autosave running writes the doctored
	# values into the player's real save.
	var ss: Node = root.get_node("SaveSystem")
	ss.set_process(false)
	ss.autosave_interval_sec = 1 << 30

	var gs: Node = root.get_node("GameState")
	root.get_node("DataLoader").reload_all()
	gs.reset_to_new_game()
	for dept in ["ticket", "archive", "promotions", "gallery"]:
		for track in ["staff", "speed", "value"]:
			gs.set_dept_level(gs.current_venue, dept, track, 14)
	gs.ready_flag = true

	_floor = (load("res://scenes/venue/floor/venue_floor.tscn") as PackedScene).instantiate()
	_floor.set_size(Vector2(720, 760))
	root.add_child(_floor)
	_floor.time_scale = 6.0

func _process(delta: float) -> bool:
	if _done:
		return true
	_frames += 1
	if _frames == 2:
		_city = _floor.get("_city")
		_check_order()
		if _city != null:
			_last_cars = _city.car_positions()
			_odo.resize(_last_cars.size())
		return false
	if _frames < 2:
		return false
	_t += delta
	_floor.set_rates(root.get_node("Economy").venue_rates(
		root.get_node("GameState").current_venue))
	_sample_visitors()
	_sample_cars()
	if _t < 6.0:
		return false
	_done = true
	_check_traffic()
	_check_taps()
	_check_arrivals()
	_check_cars_never_overlap()
	print("---")
	if _fail == 0:
		print("ALL CITY CHECKS PASSED")
	quit(0 if _fail == 0 else 1)
	return true

## The whole surround rides on being ordered before Ground. Assert the mechanism,
## not the picture: added first, lifted above the canvas origin so Y-sort cannot
## tie, left on the default z band, and carrying no input handler of its own.
func _check_order() -> void:
	check(_city != null and is_instance_valid(_city), "the floor builds a City node")
	if _city == null:
		return
	var canvas: Node = _city.get_parent()
	var ground: Node = canvas.get_node_or_null("Ground")
	check(canvas.get_children().find(_city) == 0, "the city is the first child of the canvas")
	check(ground != null and _city.position.y < ground.position.y,
		"the city sits above the ground plane in Y-sort order (%.1f < %.1f)"
			% [_city.position.y, ground.position.y if ground != null else 0.0])
	check(_city.z_index == 0, "the city stays on the default z band")
	check(not _city.has_method("_gui_input"), "the city has no input handler of its own")
	check(canvas.y_sort_enabled, "the canvas is Y-sorted, which is what orders it")

## Distance TRAVELLED, not start-to-end displacement: a lane is a loop, so a car
## that has gone all the way round can finish where it started.
func _sample_cars() -> void:
	var now: Array[Vector2] = _city.car_positions()
	for i in now.size():
		var d: float = absf(now[i].x - _last_cars[i].x)
		if d < 1.0:              # anything larger is a wrap, not a step
			_odo[i] += d
	_last_cars = now

func _check_traffic() -> void:
	var now: Array[Vector2] = _city.car_positions()
	check(now.size() == City.CAR_COUNT, "%d cars on the road" % now.size())
	var moved: int = 0
	var inside: bool = true
	for i in now.size():
		if _odo[i] > 1.5:
			moved += 1
		var span: Vector2 = City.lane_span(now[i].y)
		if now[i].x < span.x - 0.01 or now[i].x > span.y + 0.01:
			inside = false
	check(moved == now.size(), "every car actually drove (%d of %d)" % [moved, now.size()])
	check(inside, "every car is still inside its lane span")
	var cars: Array = _city.get("_cars")
	var yielding: Dictionary = cars[0]
	yielding["gx"] = City.CROSS_MIN_GX - 0.73
	yielding["dir"] = 1.0
	yielding["gy"] = City.LANE_OUT
	City.Routes.start(yielding,PackedVector2Array([Vector2(-30,City.LANE_OUT),Vector2(36,City.LANE_OUT)]),true)
	var before: float = float(yielding["gx"])
	_city.advance(0.25, true)
	var stop_line: float = City.CROSS_MIN_GX - 0.72
	check(float(yielding["gx"]) <= stop_line + 0.001,
		"an approaching car yields at the painted crossing")
	before = float(yielding["gx"])
	_city.advance(0.25, false)
	check(float(yielding["gx"]) > before,
		"the yielding car resumes when the crossing clears")

## The surround covers most of the canvas, so a tap out there must fall through
## to nothing rather than opening whatever room rect happens to be nearest.
func _check_taps() -> void:
	var outside := {
		"the road": Vector2(11.0, City.LANE_OUT),
		"the pavement": Vector2(12.0, City.SIDEWALK_B - 0.2),
		"the forecourt": City.STREET_G,
		"the west lawn": Vector2(-3.5, 4.0),
		"the north lawn": Vector2(4.0, -3.5),
	}
	for label in outside.keys():
		var g: Vector2 = outside[label]
		check(_floor.tap_zone_at(Iso.to_screen(g)) == "",
			"a tap on %s opens nothing" % label)
	# and the rooms still answer, so the check above is not passing by accident.
	check(_floor.tap_zone_at(_floor.room_center("gallery")) == "gallery",
		"the gallery still answers a tap")

func _sample_visitors() -> void:
	for v in _floor.get("_visitors"):
		_max_gy = maxf(_max_gy, (v.pos as Vector2).y)
		if (v.pos as Vector2).y > Iso.GRID.y:
			_min_alpha = minf(_min_alpha, (v.node as Node2D).modulate.a)

func _check_arrivals() -> void:
	check(_max_gy > Iso.GRID.y,
		"visitors are seen outside the building, on the approach (max gy %.2f)" % _max_gy)
	check(_min_alpha >= 0.99,
		"arrivals stay fully opaque while walking in from off-screen (min a %.2f)"
			% _min_alpha)
	var left: Array = _city.arrival_route(false)
	var right: Array = _city.arrival_route(true)
	check(not Iso.on_canvas(left[0]) and not Iso.on_canvas(right[0]),
		"the two sidewalk approaches begin outside opposite frame edges")
	check(left[1].is_equal_approx(_city.map_point(City.CROSS_FAR))
			and left[2].is_equal_approx(_city.map_point(City.CROSS_NEAR)),
		"arrivals cross the road only on the painted zebra")
	check(_floor.standing_spots().has(_city.street_point()),
		"the street spawn is declared as a standing spot, so geometry checks cover it")

## Two cars share each lane at different speeds, so the faster one catches the
## slower one within a minute of simulated driving. Before the following gap
## existed it drove straight through and the pair rendered stacked on top of
## each other — the "cars riding on top of each other" report. Simulate long
## enough for every pair to converge and wrap, and assert they never overlap.
func _check_cars_never_overlap() -> void:
	var cars: Array = _city.get("_cars")
	check(cars.size() >= 2, "there is traffic to check (%d cars)" % cars.size())
	var min_gap := INF
	var worst := ""
	# 400s at 1/30s steps: several full laps of the lane span, which is what it
	# takes for the wrap-around case to bring a fast car up behind a slow one.
	for _step in 12000:
		_city.advance(1.0 / 30.0, false)
		for i in cars.size():
			for j in range(i + 1, cars.size()):
				var a: Dictionary = cars[i]
				var b: Dictionary = cars[j]
				if float(a.get("wait",0))>0 or float(b.get("wait",0))>0:continue
				if a.axis!=Vector2.RIGHT or b.axis!=Vector2.RIGHT:continue
				if not is_equal_approx(float(a["gy"]), float(b["gy"])):
					continue  # different lanes never interact
				var gap: float = absf(float(a["gx"]) - float(b["gx"]))
				if gap < min_gap:
					min_gap = gap
					worst = "%.2f between cars in lane %.2f" % [gap, float(a["gy"])]
	check(min_gap >= City.CAR_HALF_GX * 2.0 - 0.01,
		"no two cars in a lane ever overlap (closest %s)" % worst)
