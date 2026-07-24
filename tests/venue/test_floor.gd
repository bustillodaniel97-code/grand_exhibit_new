extends SceneTree
## Living-floor suite (plan Stage 1 §8): the diorama boots headless with the sim
## running; visitors spawn and queue, queue occupancy responds to the choke
## point, porters complete window->vault loops, and room tap zones emit
## dept_selected. Also exercises the venue_view bottom-sheet wiring.
## Run: godot --headless --path <repo> -s tests/venue/test_floor.gd  (exit 0 pass)

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
	_floor.time_scale = 6.0  # 1 real second ~= 6 sim seconds

func _process(delta: float) -> bool:
	_frames += 1
	if _frames < 3:
		return false
	_t += delta
	# Feed live rates (venue_view does this via its 0.5s timer in-game).
	_floor.set_rates(root.get_node("Economy").venue_rates(root.get_node("GameState").current_venue))
	match _phase:
		0:
			# ~5 real seconds (~30 sim s) of steady-state play.
			if _t >= 5.0:
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
			# ~4 more real seconds with ticket as the choke point.
			if _t >= 4.0:
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
	check(_floor.get_alive_visitor_count() > 0, "visitors spawned and alive after ~30 sim s")
	check(_floor.get_porter_trips() >= 1, "porter completed at least one window->vault loop")
	check(_floor.get_choke() == "archive",
		"new-game choke is archive (transport 0.25 < pending 0.28)")

func _check_choke_response() -> void:
	var occ: int = _floor.get_queue_occupancy()
	check(_floor.get_choke() == "ticket", "choke flips to ticket when arrival >> serve")
	check(occ >= 3, "queue occupancy responds to ticket choke (calm=%d, choked=%d)" % [
		_occupancy_calm, occ])
	check(occ > _occupancy_calm, "choked queues hold more visitors than calm state")

func _check_tap_zones() -> void:
	_taps.clear()
	_floor.simulate_tap(Vector2(586, 174))   # vault room center
	_floor.simulate_tap(Vector2(586, 396))   # promotions corner
	_floor.simulate_tap(Vector2(234, 204))   # gallery
	_floor.simulate_tap(Vector2(350, 620))   # ticket hall / queue lanes
	_floor.simulate_tap(Vector2(400, 740))   # carpet: no zone
	check(_taps.size() == 4, "four room taps emitted, carpet tap ignored (got %d)" % _taps.size())
	check("archive" in _taps, "vault tap zone -> archive")
	check("promotions" in _taps, "promo corner tap zone -> promotions")
	check("gallery" in _taps, "gallery tap zone -> gallery")
	check("ticket" in _taps, "ticket hall tap zone -> ticket")

func _check_sheet_wiring() -> void:
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
