extends SceneTree
const City := preload("res://scenes/venue/floor/city.gd")
## Living-floor suite (plan Stage 1 §8): the diorama boots headless with the sim
## running; visitors spawn and queue, queue occupancy responds to the choke
## point, porters complete window->vault loops, and room tap zones emit
## dept_selected. Also exercises the venue_view bottom-sheet wiring.
## Run: godot --headless --path <repo> -s tests/venue/test_floor.gd  (exit 0 pass)

const Iso := preload("res://scenes/venue/floor/iso.gd")

var _frames: int = 0
var _fail: int = 0
var _t: float = 0.0
var _phase: int = 0
var _floor: Control
var _taps: Array = []
var _occupancy_calm: int = 0

func check(cond: bool, msg: String) -> void:
	if cond:
		print("PASS: ", msg)
	else:
		_fail += 1
		printerr("FAIL: ", msg)

func _initialize() -> void:
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
		var n: Node = (load(pair[1]) as GDScript).new()
		n.name = pair[0]
		root.add_child(n)

	var gs: Node = root.get_node("GameState")
	root.get_node("DataLoader").reload_all()
	gs.reset_to_new_game()
	gs.ready_flag = true

	_floor = (load("res://scenes/venue/floor/venue_floor.tscn") as PackedScene).instantiate()
	_floor.set_size(Vector2(720, 760))
	_floor.dept_selected.connect(func(dept_id: String) -> void: _taps.append(dept_id))
	root.add_child(_floor)
	# The sim is driven explicitly below, so time_scale stays at 1: the suite
	# advances SIM seconds rather than waiting real ones.
	_floor.time_scale = 0.0

func _process(delta: float) -> bool:
	_frames += 1
	if _frames < 3:
		return false
	# Advance a fixed slice of SIM time per frame and feed live rates, exactly as
	# venue_view does via its 0.5s timer in game. Pacing on `delta` instead made
	# every assertion below a function of how loaded the machine was.
	const SIM_SLICE := 0.5
	_t += SIM_SLICE
	_floor.set_rates(root.get_node("Economy").venue_rates(root.get_node("GameState").current_venue))
	_floor.advance_sim(SIM_SLICE)
	match _phase:
		0:
			# The authored sidewalk and crossing add a real approach before the
			# original service loop. Allow it to complete without making the
			# porter assertion depend on whether the first pedestrian caught an
			# immediate traffic gap.
			if _t >= 60.0:
				_phase = 1
				_check_alive()
				_occupancy_calm = _floor.get_queue_occupancy()
				# Force the ticket hall into the choke: big promo push, ample porters.
				var gs: Node = root.get_node("GameState")
				var vs: Dictionary = gs.venue_state(gs.current_venue)
				vs["depts"]["promotions"]["staff"] = 8
				vs["depts"]["archive"]["staff"] = 10
				_t = 0.0
		1:
			# 24 more sim seconds with ticket as the choke point.
			if _t >= 24.0:
				_phase = 2
				_check_choke_response()
				_check_tap_zones()
				_check_sheet_wiring()
				print("---")
				if _fail == 0:
					print("ALL FLOOR CHECKS PASSED")
				quit(0 if _fail == 0 else 1)
				return true
	return false

func _check_alive() -> void:
	check(_floor.get_alive_visitor_count() > 0, "visitors spawned and alive after 60 sim s")
	var city: Node = _floor.get("_city")
	var left_route: Array = city.arrival_route(false)
	var right_route: Array = city.arrival_route(true)
	check(not Iso.on_canvas(left_route[0]) and not Iso.on_canvas(right_route[0]),
		"arrivals originate beyond opposite sidewalk edges")
	check(left_route[1].is_equal_approx(city.map_point(City.CROSS_FAR))
			and left_route[2].is_equal_approx(city.map_point(City.CROSS_NEAR)),
		"the sidewalk approach uses both ends of the painted crossing")
	var cars: Array = city.get("_cars")
	check(not cars.is_empty(), "street traffic exists for crossing-gate regression")
	if not cars.is_empty():
		# Put a car over the zebra, then prove only somebody standing at a kerb
		# waits. The old one-sided y test also stopped any indoor visitor moving
		# south near this x, which accumulated the Promotions crowd into one mass.
		cars[0]["gx"] = City.CROSS_GX
		var far_kerb: Vector2 = city.map_point(City.CROSS_FAR)
		var near_kerb: Vector2 = city.map_point(City.CROSS_NEAR)
		check(_floor._waiting_to_cross(far_kerb, near_kerb),
			"a pedestrian at the far kerb waits while a car occupies the zebra")
		var theme = _floor.get("_theme")
		var promo_rect: Rect2 = theme.role("promo").get("rect", Rect2())
		var indoor := Vector2(far_kerb.x, promo_rect.get_center().y)
		check(not _floor._waiting_to_cross(indoor, indoor + Vector2(0.0, 0.5)),
			"street traffic never freezes a visitor moving inside Promotions")
	var opaque := true
	for visitor in _floor._visitors:
		if not is_equal_approx(visitor.node.modulate.a, 1.0):
			opaque = false
	check(opaque, "visitor opacity remains 1.0 throughout the entrance walk")
	check(_floor.get_porter_trips() >= 1, "porter completed at least one window->vault loop")
	_check_reactive_doors()
	check(_floor.get_choke() == "archive",
		"new-game choke is archive (transport 0.25 < pending 0.28)")

func _check_reactive_doors() -> void:
	var entries: Array = _floor.get("_reactive_doors")
	var ids: Array[String] = []
	for entry in entries:
		ids.append(str((entry as Dictionary).get("id", "")))
	check(ids.has("entrance") and ids.has("exit") and ids.has("vault"),
		"entrance, exit and vault doors register as NPC-reactive")
	var visitors: Array = _floor.get("_visitors")
	var porters: Array = _floor.get("_porters")
	check(not visitors.is_empty() and not porters.is_empty(),
		"live visitors and a porter can exercise the reactive doors")
	if visitors.is_empty() or porters.is_empty():
		return
	var visitor = visitors[0]
	var porter = porters[0]
	var visitor_home: Vector2 = visitor.pos
	var porter_home: Vector2 = porter.pos
	for entry in entries:
		var door: Dictionary = entry as Dictionary
		var id := str(door.get("id", ""))
		var trigger: Vector2 = door.get("trigger", Vector2.ZERO) as Vector2
		if id == "vault":
			porter.pos = trigger
		else:
			visitor.pos = trigger
		_floor._update_reactive_doors(0.25)
		check(float(_floor.door_activity().get(id, 0.0)) >= 0.99,
			"%s door opens when its NPC reaches the threshold" % id)
		visitor.pos = visitor_home
		porter.pos = porter_home

func _check_choke_response() -> void:
	var occ: int = _floor.get_queue_occupancy()
	check(_floor.get_choke() == "ticket", "choke flips to ticket when arrival >> serve")
	check(occ >= 3, "queue occupancy responds to ticket choke (calm=%d, choked=%d)" % [
		_occupancy_calm, occ])
	# Authored queue-entry routes add travel time before a visitor reaches the
	# visible rope lane. At this short sample boundary a calm and choked run can
	# both have six assigned visitors; the choke must never REDUCE the queue.
	check(occ >= _occupancy_calm, "choked queues hold at least the calm occupancy")

func _check_tap_zones() -> void:
	_taps.clear()
	# Ask the floor where its rooms are rather than hardcoding canvas points, so
	# the layout can be rebuilt without silently turning these into dead taps.
	_floor.simulate_tap(_floor.room_center("archive"))
	_floor.simulate_tap(_floor.room_center("promotions"))
	_floor.simulate_tap(_floor.room_center("gallery"))
	_floor.simulate_tap(_floor.room_center("ticket"))
	_floor.simulate_tap(_floor.dead_zone_point())   # outside every room
	check(_taps.size() == 4, "four room taps emitted, carpet tap ignored (got %d)" % _taps.size())
	check("archive" in _taps, "vault tap zone -> archive")
	check("promotions" in _taps, "promo corner tap zone -> promotions")
	check("gallery" in _taps, "gallery tap zone -> gallery")
	check("ticket" in _taps, "ticket hall tap zone -> ticket")

func _check_sheet_wiring() -> void:
	# This suite drives the 2D floor's internals; the 3D floor has test_floor_3d.
	(load("res://scenes/venue/venue_view.gd") as GDScript).set("use_3d", false)
	var vv: Control = (load("res://scenes/venue/venue_view.tscn") as PackedScene).instantiate()
	root.add_child(vv)
	var floor_node: Node = vv.find_child("VenueFloor", true, false)
	check(floor_node != null, "venue_view embeds the VenueFloor diorama")
	var sheet: Node = vv.find_child("DeptSheet", true, false)
	check(sheet != null, "venue_view has the DeptSheet bottom sheet")
	if sheet != null:
		check(not sheet.visible, "dept sheet starts hidden")
		vv._open_sheet("ticket")
		check(sheet.visible, "dept sheet opens on dept select")
		var panel: Node = vv.find_child("DeptPanel", true, false)
		check(panel != null and panel.dept_id == "ticket", "sheet hosts the ticket DeptPanel")
		vv._close_sheet()
	vv.queue_free()
