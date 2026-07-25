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
	_boot_floor()

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
	check(_min_alpha < 0.9,
		"an arrival fades up across the forecourt rather than popping in (min a %.2f)"
			% _min_alpha)
	check(_floor.standing_spots().has(City.STREET_G),
		"the street spawn is declared as a standing spot, so geometry checks cover it")
