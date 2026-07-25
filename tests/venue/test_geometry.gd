extends SceneTree
## Geometry + density suite: the diorama has to be WHERE it says it is, and there
## has to be enough of it.
##
## The projected diamond is 980px wide against a 720px canvas, so a quarter of
## the floor plan is clipped away by design (see Iso.TILE). That is fine for the
## FLOOR; it is fatal for anything placed out there, and the failure is silent —
## no error, no warning, the prop simply never renders. The archive's vault door
## (canvas x = 750), its money pile (756), the far half of its shelving (768) and
## one lobby planter (-30) all shipped that way. Every check below is either that
## defect or one of its cousins:
##   · props and waypoints must project inside Iso.VIEW with real margin
##   · a waypoint must not sit inside a prop, or someone stands in the furniture
##   · each room must carry a floor of props, so a later edit cannot quietly
##     thin the density pass back out
##   · the live crowd must spread across the floor instead of all parking in the
##     room with the shortest dwell time
## Run: godot --headless --path <repo> -s tests/venue/test_geometry.gd (exit 0 pass)

const Iso := preload("res://scenes/venue/floor/iso.gd")
## Loaded at RUNTIME, not preloaded: venue_floor.gd refers to the EventBus
## autoload, and a preload is compiled before this suite has registered it.
var VF: GDScript

## Pixels of margin a prop anchor or waypoint must keep from the clip edge. One
## tile of x is 60px; half of that is enough to keep a figure's own width inside.
const EDGE_INSET := 26.0
## Minimum props per room. Measured before this pass: gallery 7, archive 3,
## promotions 3, lobby 5, ticket 45 (of which 40 were individual rope stanchions).
const MIN_PROPS := {"gallery": 12, "archive": 7, "promotions": 6, "ticket": 12, "lobby": 10}

var _fail: int = 0
var _floor: Control
var _frames: int = 0
var _t: float = 0.0
var _done: bool = false

func check(cond: bool, msg: String) -> void:
	if cond:
		print("PASS: ", msg)
	else:
		_fail += 1
		printerr("FAIL: ", msg)

func _initialize() -> void:
	_check_projection()
	_boot_floor()

# --- projection ----------------------------------------------------------------

## gx_window is the placement rule the whole floor is laid out against, so it has
## to agree with to_screen exactly rather than approximately.
func _check_projection() -> void:
	var ok: bool = true
	for gy in [0.0, 2.5, 7.0, 11.0, 17.0]:
		var win: Vector2 = Iso.gx_window(gy, 0.0)
		if absf(Iso.to_screen(Vector2(win.x, gy)).x) > 0.01:
			ok = false
		if absf(Iso.to_screen(Vector2(win.y, gy)).x - Iso.VIEW.x) > 0.01:
			ok = false
	check(ok, "gx_window agrees with to_screen at both clip edges")
	var inset: Vector2 = Iso.gx_window(4.0, 30.0)
	check(inset.x > Iso.gx_window(4.0, 0.0).x and inset.y < Iso.gx_window(4.0, 0.0).y,
		"an inset narrows the window from both sides")
	check(not Iso.on_canvas(Vector2(12.0, 0.0)),
		"the old vault-door tile is confirmed off canvas (grid 12,0 -> x %.0f)"
			% Iso.to_screen(Vector2(12.0, 0.0)).x)
	check(not Iso.on_canvas(Vector2(13.4, 1.2)),
		"the old vault-pile tile is confirmed off canvas")

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
	# values into the player's real save; that is how the battery went red once.
	var ss: Node = root.get_node("SaveSystem")
	ss.set_process(false)
	ss.autosave_interval_sec = 1 << 30

	var gs: Node = root.get_node("GameState")
	root.get_node("DataLoader").reload_all()
	gs.reset_to_new_game()
	# A maxed venue is the case the density pass targets: five ticket windows, a
	# full cast, and every room's props built.
	for dept in ["ticket", "archive", "promotions", "gallery"]:
		for track in ["staff", "speed", "value"]:
			gs.set_dept_level(gs.current_venue, dept, track, 14)
	gs.ready_flag = true

	VF = load("res://scenes/venue/floor/venue_floor.gd") as GDScript
	_floor = (load("res://scenes/venue/floor/venue_floor.tscn") as PackedScene).instantiate()
	_floor.set_size(Vector2(720, 760))
	root.add_child(_floor)
	_floor.time_scale = 8.0

func _process(delta: float) -> bool:
	if _done:
		return true
	_frames += 1
	if _frames < 3:
		return false
	_t += delta
	_floor.set_rates(root.get_node("Economy").venue_rates(
		root.get_node("GameState").current_venue))
	if _t < 6.0:
		return false
	_done = true
	_check_on_canvas()
	_check_density()
	_check_waypoints_clear_of_props()
	_check_crowd_spread()
	print("---")
	if _fail == 0:
		print("ALL GEOMETRY CHECKS PASSED")
	quit(0 if _fail == 0 else 1)
	return true

func _check_on_canvas() -> void:
	var props: Array[Vector2] = _floor.prop_anchors()
	var worst := Vector2.ZERO
	var off: int = 0
	for g in props:
		if not Iso.on_canvas(g, EDGE_INSET):
			off += 1
			worst = g
	check(off == 0, "every prop anchor is on canvas with %.0fpx margin (%d off, worst %s -> %s)"
		% [EDGE_INSET, off, worst, Iso.to_screen(worst)])

	var spots: Array[Vector2] = _floor.standing_spots()
	var soff: int = 0
	var sworst := Vector2.ZERO
	for g in spots:
		if not Iso.on_canvas(g, EDGE_INSET):
			soff += 1
			sworst = g
	check(soff == 0, "every waypoint the cast walks to is on canvas (%d off, worst %s -> %s)"
		% [soff, sworst, Iso.to_screen(sworst)])

	for dept in VF.PLAQUE_G.keys():
		var at: Vector2 = Iso.to_screen(VF.PLAQUE_G[dept])
		check(at.x > 70.0 and at.x < Iso.VIEW.x - 70.0,
			"%s plaque leaves room for its chip at x=%.0f" % [dept, at.x])

func _check_density() -> void:
	var props: Array[Vector2] = _floor.prop_anchors()
	var per := {"gallery": 0, "archive": 0, "promotions": 0, "ticket": 0, "lobby": 0}
	for g in props:
		if VF.R_GALLERY.has_point(g) or VF.R_CORRIDOR.has_point(g):
			per["gallery"] += 1
		elif VF.R_VAULT.has_point(g):
			per["archive"] += 1
		elif VF.R_PROMO.has_point(g):
			per["promotions"] += 1
		elif VF.R_TICKET.has_point(g):
			per["ticket"] += 1
		else:
			per["lobby"] += 1
	for room in MIN_PROPS.keys():
		check(per[room] >= int(MIN_PROPS[room]),
			"%s carries at least %d props (%d)" % [room, MIN_PROPS[room], per[room]])
	check(props.size() >= 55, "the floor carries at least 55 props (%d)" % props.size())

## A waypoint inside a prop's footprint stands somebody in the furniture. Anchors
## are prop CENTRES of mass rather than exact footprints, so this is a proximity
## test with the tolerance set just under the smallest prop on the floor.
func _check_waypoints_clear_of_props() -> void:
	var props: Array[Vector2] = _floor.prop_anchors()
	var worst: float = 1e9
	var wp := Vector2.ZERO
	var wg := Vector2.ZERO
	for g in _floor.standing_spots():
		for p in props:
			var d: float = g.distance_to(p)
			if d < worst:
				worst = d
				wp = p
				wg = g
	check(worst >= 0.34,
		"no waypoint sits on a prop anchor (closest %.2f tiles: %s vs prop %s)" % [worst, wg, wp])

## The floor is a closed system of MAX_ALIVE people, so where they stand is set
## by the RATIO of dwell times. With the old 0.6s service floor the ticket hall
## emptied in seconds and the entire crowd parked in the gallery; this asserts no
## single stage of the loop owns the floor.
func _check_crowd_spread() -> void:
	var c: Dictionary = _floor.state_census()
	var alive: int = _floor.get_alive_visitor_count()
	check(alive >= 20, "a maxed venue fills up (%d alive, cap %d)" % [alive, VF.MAX_ALIVE])
	if alive < 20:
		return
	var queueing: int = int(c["queue"]) + int(c["to_queue"])
	var away: int = int(c["browse"])
	var leaving: int = int(c["linger"]) + int(c["exit"])
	check(queueing >= 4, "the ticket hall holds a visible queue (%d)" % queueing)
	check(away >= 4, "the exhibits hold an audience (%d)" % away)
	check(leaving >= 3, "the lobby is on somebody's route out (%d)" % leaving)
	var worst: int = maxi(queueing, maxi(away, leaving))
	check(float(worst) / float(alive) <= 0.72,
		"no single stage holds more than 72%% of the floor (worst %d of %d)" % [worst, alive])
