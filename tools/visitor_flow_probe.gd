extends SceneTree
## Deterministic visitor-flow probe for diagnosing bunching without rendering.
##
## This is a dev tool, not shipping game code. It boots an isolated new game,
## advances the real VenueFloor simulation, and compares three event streams:
## ticket-service releases, crossings into/out of the Promotions doorway, and
## seat arrivals/departures. That distinguishes a burst created upstream from a
## long dwell that merely makes an otherwise steady stream accumulate.
##
##   GRAND_EXHIBIT_TEST_RUN=1 godot --headless --path . \
##     -s tools/visitor_flow_probe.gd -- seconds=120 levels=8 seed=20260731

const DEFAULT_SECONDS := 120.0
const SIM_STEP := 0.05
const RATE_STEP := 0.5
const DOOR_EPS := 0.001

var _args: Dictionary = {}
var _floor: Control
var _economy: Node
var _sim_t := 0.0
var _frames := 0
var _ran := false

var _previous: Dictionary = {} # character instance id -> last observed values
var _served: Array[float] = []
var _door_in: Array[float] = []
var _door_out: Array[float] = []
var _rest_claimed: Array[float] = []
var _rest_seated: Array[float] = []
var _rest_left: Array[float] = []
var _max_near_door := 0
var _max_near_door_states: Dictionary = {}
var _max_near_door_detail: Array[String] = []
var _max_moving_cluster_035 := 0
var _max_moving_cluster_070 := 0
var _max_moving_cluster_sample := ""
var _door_x := 0.0
var _door_y := Vector2.ZERO


func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		var kv := (arg as String).split("=", true, 1)
		if kv.size() == 2:
			_args[kv[0]] = kv[1]

	var autoloads := [
		["EventBus", "res://autoload/event_bus.gd"],
		["DataLoader", "res://autoload/data_loader.gd"],
		["ClockGuard", "res://autoload/clock_guard.gd"],
		["Analytics", "res://autoload/analytics.gd"],
		["AdService", "res://autoload/ad_service.gd"],
		["IAPService", "res://autoload/iap_service.gd"],
		["GameState", "res://autoload/game_state.gd"],
		["SaveSystem", "res://autoload/save_system.gd"],
		["Economy", "res://autoload/economy.gd"],
	]
	for pair in autoloads:
		if root.has_node(pair[0]):
			continue
		var node: Node = (load(pair[1]) as GDScript).new()
		node.name = pair[0]
		root.add_child(node)

	var save_system: Node = root.get_node("SaveSystem")
	save_system.set_process(false)
	var data_loader: Node = root.get_node("DataLoader")
	var game_state: Node = root.get_node("GameState")
	_economy = root.get_node("Economy")
	data_loader.reload_all()
	game_state.reset_to_new_game()
	game_state.ready_flag = true

	var venue := String(_args.get("venue", "whispering_pines"))
	if venue not in game_state.venues_unlocked:
		game_state.venues_unlocked.append(venue)
	game_state.current_venue = venue
	var levels := int(_args.get("levels", "8"))
	for dept in ["ticket", "archive", "promotions", "gallery"]:
		for track in ["staff", "speed", "value"]:
			game_state.set_dept_level(venue, dept, track, levels)

	seed(int(_args.get("seed", "20260731")))
	_floor = (load("res://scenes/venue/floor/venue_floor.tscn") as PackedScene).instantiate()
	_floor.set_size(Vector2(720, 760))
	root.add_child(_floor)
	_floor.time_scale = 0.0


func _process(_delta: float) -> bool:
	_frames += 1
	if _frames < 3 or _ran:
		return false
	_ran = true
	_resolve_promo_door()
	_run_probe(float(_args.get("seconds", str(DEFAULT_SECONDS))))
	quit(0)
	return true


## Resolve the largest opening on the Promotions room's left wall from authored
## wall segments. Venue 1 currently resolves to y=10.35..12.10 at x=10.50.
func _resolve_promo_door() -> void:
	var theme: RefCounted = _floor.get("_theme")
	var promo: Dictionary = theme.role("promo")
	var rect: Rect2 = promo.get("rect", Rect2())
	_door_x = rect.position.x
	var covered: Array[Vector2] = []
	for entry in theme.walls:
		var wall: Dictionary = entry as Dictionary
		if str(wall.get("axis", "x")) != "y":
			continue
		var at := Vector2(float(wall.get("at", [0.0, 0.0])[0]),
			float(wall.get("at", [0.0, 0.0])[1]))
		if absf(at.x - _door_x) > DOOR_EPS:
			continue
		var lo := maxf(at.y, rect.position.y)
		var hi := minf(at.y + float(wall.get("len", 0.0)), rect.end.y)
		if hi > lo:
			covered.append(Vector2(lo, hi))
	covered.sort_custom(func(a: Vector2, b: Vector2) -> bool: return a.x < b.x)
	var cursor := rect.position.y
	var best := Vector2(rect.position.y, rect.end.y)
	var best_size := -1.0
	for span in covered:
		if span.x > cursor and span.x - cursor > best_size:
			best = Vector2(cursor, span.x)
			best_size = span.x - cursor
		cursor = maxf(cursor, span.y)
	if rect.end.y > cursor and rect.end.y - cursor > best_size:
		best = Vector2(cursor, rect.end.y)
	_door_y = best


func _run_probe(seconds: float) -> void:
	var until_rate := 0.0
	while _sim_t < seconds:
		if until_rate <= 0.0:
			_floor.set_rates(_economy.venue_rates(root.get_node("GameState").current_venue))
			until_rate = RATE_STEP
		_floor.advance_sim(SIM_STEP)
		_sim_t += SIM_STEP
		until_rate -= SIM_STEP
		_observe()
	_print_report(seconds)


func _observe() -> void:
	var near_count := 0
	var near_states: Dictionary = {}
	var near_detail: Array[String] = []
	var moving: Array = []
	var alive: Dictionary = {}
	for visitor in _floor.get("_visitors"):
		var id: int = visitor.node.get_instance_id()
		alive[id] = true
		var state: String = visitor.state
		var seated: bool = visitor.node.seated
		var pos: Vector2 = visitor.pos
		if absf(pos.x - _door_x) <= 1.2 \
				and pos.y >= _door_y.x - 1.2 and pos.y <= _door_y.y + 1.2:
			near_count += 1
			var motion := "walk" if visitor.node.walking else "idle"
			var state_key := state + "/" + motion
			near_states[state_key] = int(near_states.get(state_key, 0)) + 1
			near_detail.append("%s/%s p=%.2f,%.2f goal=%.2f,%.2f path=%d wait=%.2f seat=%d" % [
				state, motion, pos.x, pos.y, visitor.target.x, visitor.target.y,
				visitor.path.size(), visitor.wait, visitor.seat])
		if visitor.node.walking and state in ["browse", "rest", "exit"]:
			moving.append(visitor)

		if _previous.has(id):
			var before: Dictionary = _previous[id]
			var old_state := String(before["state"])
			if old_state == "queue" and state == "browse":
				_served.append(_sim_t)
			if old_state == "browse" and state == "rest":
				_rest_claimed.append(_sim_t)
			if not bool(before["seated"]) and seated:
				_rest_seated.append(_sim_t)
			if old_state == "rest" and state == "exit":
				_rest_left.append(_sim_t)
			var stable_side := int(before["side"])
			var observed_side := _door_side(pos)
			if observed_side != 0 and stable_side != 0 and observed_side != stable_side \
					and pos.y >= _door_y.x - 0.35 and pos.y <= _door_y.y + 0.35:
				if observed_side > 0:
					_door_in.append(_sim_t)
				else:
					_door_out.append(_sim_t)
			if observed_side != 0:
				stable_side = observed_side
			_previous[id] = {"pos": pos, "state": state, "seated": seated,
				"side": stable_side}
		else:
			_previous[id] = {"pos": pos, "state": state, "seated": seated,
				"side": _door_side(pos)}

	if near_count > _max_near_door:
		_max_near_door = near_count
		_max_near_door_states = near_states.duplicate()
		_max_near_door_detail = near_detail.duplicate()
	_measure_moving_clusters(moving)
	for id in _previous.keys():
		if not alive.has(id):
			_previous.erase(id)


func _door_side(pos: Vector2) -> int:
	# A hysteresis band prevents an A* path that runs along the wall line from
	# being miscounted as several rapid in/out crossings by one visitor.
	if pos.x < _door_x - 0.20:
		return -1
	if pos.x > _door_x + 0.20:
		return 1
	return 0


func _print_report(seconds: float) -> void:
	print("FLOW venue=", root.get_node("GameState").current_venue,
		" seconds=", seconds, " seed=", _args.get("seed", "20260731"),
		" levels=", _args.get("levels", "8"))
	print("FLOW doorway x=%.2f y=%.2f..%.2f" % [_door_x, _door_y.x, _door_y.y])
	_print_stream("served", _served)
	_print_stream("door_in", _door_in)
	_print_stream("door_out", _door_out)
	_print_stream("rest_claimed", _rest_claimed)
	_print_stream("rest_seated", _rest_seated)
	_print_stream("rest_left", _rest_left)
	print("FLOW max_near_door=", _max_near_door, " states=", _max_near_door_states)
	for detail in _max_near_door_detail:
		print("FLOW   near ", detail)
	print("FLOW max_moving_cluster radius=.35:", _max_moving_cluster_035,
		" radius=.70:", _max_moving_cluster_070,
		" sample=", _max_moving_cluster_sample)
	print("FLOW final_clumps=", _floor.clump_report())
	print("FLOW final_census=", _floor.state_census())


func _print_stream(label: String, events: Array[float]) -> void:
	var gaps: Array[float] = []
	for i in range(1, events.size()):
		gaps.append(events[i] - events[i - 1])
	var mean := _mean(gaps)
	var deviation := 0.0
	for gap in gaps:
		deviation += pow(gap - mean, 2.0)
	deviation = sqrt(deviation / float(gaps.size())) if not gaps.is_empty() else 0.0
	var cv := deviation / mean if mean > 0.0 else 0.0
	var tight := 0
	for gap in gaps:
		if gap <= 0.35:
			tight += 1
	print("FLOW %-13s n=%3d gap_mean=%5.2f gap_cv=%4.2f tight=%2d times=%s" % [
		label, events.size(), mean, cv, tight, str(events)])


func _mean(values: Array[float]) -> float:
	if values.is_empty():
		return 0.0
	var total := 0.0
	for value in values:
		total += value
	return total / float(values.size())


func _measure_moving_clusters(visitors: Array) -> void:
	for visitor in visitors:
		var close_035 := 0
		var close_070 := 0
		var states: Dictionary = {}
		for other in visitors:
			var distance: float = visitor.pos.distance_to(other.pos)
			if distance <= 0.35:
				close_035 += 1
			if distance <= 0.70:
				close_070 += 1
				states[other.state] = int(states.get(other.state, 0)) + 1
		_max_moving_cluster_035 = maxi(_max_moving_cluster_035, close_035)
		if close_070 > _max_moving_cluster_070:
			_max_moving_cluster_070 = close_070
			_max_moving_cluster_sample = "t=%.2f at=%.2f,%.2f states=%s" % [
				_sim_t, visitor.pos.x, visitor.pos.y, str(states)]
