extends SceneTree
## test_nav_reachability.gd — every room must be walkable-to, in every venue.
##
## The report this exists for: "NPCs never take stairs", and on Sunspire the
## promotions stairs not joining the gallery staircase. No venue is missing a
## stair room — all twelve have one per raised storey — so the failure is
## CONNECTIVITY: the stair exists but the graph does not join through it.
##
## A* over the real nav grid is the only honest way to ask. Anything less
## (checking a stair room exists, eyeballing a screenshot) can pass while the
## crowd is still stranded.
##
## Run: godot --headless --path <repo> -s tests/venue/test_nav_reachability.gd

var _fail: int = 0
var _floor: Control
var _frames: int = 0
var _done: bool = false
var DL: Node

func check(cond: bool, msg: String) -> void:
	if cond:
		print("PASS: ", msg)
	else:
		_fail += 1
		printerr("FAIL: ", msg)

func _initialize() -> void:
	for pair in [["EventBus", "event_bus"], ["DataLoader", "data_loader"],
			["ClockGuard", "clock_guard"], ["Analytics", "analytics"],
			["AdService", "ad_service"], ["IAPService", "iap_service"],
			["GameState", "game_state"], ["SaveSystem", "save_system"],
			["Economy", "economy"]]:
		if root.has_node(pair[0]):
			continue
		var n: Node = (load("res://autoload/%s.gd" % pair[1]) as GDScript).new()
		n.name = pair[0]
		root.add_child(n)
	root.get_node("SaveSystem").set_process(false)
	DL = root.get_node("DataLoader")
	var gs: Node = root.get_node("GameState")
	gs.reset_to_new_game()
	gs.ready_flag = true
	_floor = (load("res://scenes/venue/floor/venue_floor.tscn") as PackedScene).instantiate()
	_floor.set_size(Vector2(720, 760))
	root.add_child(_floor)

func _process(_dt: float) -> bool:
	if _done:
		return true
	_frames += 1
	if _frames < 4:
		return false
	_done = true
	_check_all_venues()
	print("---")
	if _fail == 0:
		print("ALL NAV REACHABILITY CHECKS PASSED")
	quit(0 if _fail == 0 else 1)
	return true

## Nearest walkable cell to a room's middle. A room centre can legitimately sit
## under a desk or an exhibit, so probing one cell would report a false break;
## the crowd only needs SOMEWHERE in the room to be reachable.
func _walkable_in(rect: Rect2, from_id: Vector2i = Vector2i(1 << 30, 1 << 30)) -> Vector2i:
	var best := Vector2i(1 << 30, 1 << 30)
	var steps := 7
	for iy in steps:
		for ix in steps:
			var g := rect.position + Vector2(
				rect.size.x * (float(ix) + 0.5) / float(steps),
				rect.size.y * (float(iy) + 0.5) / float(steps))
			var id: Vector2i = _floor._nav_id(g)
			if not _floor._nav.is_in_boundsv(id):
				continue
			if not _floor._nav.is_point_solid(id):
				# An open cell isolated behind furniture does not prove a whole
				# room inaccessible. Find an actual reachable interior sample.
				if from_id.x != 1 << 30 and _floor._nav.get_id_path(from_id, id).is_empty():
					continue
				return id
	return best

func _check_all_venues() -> void:
	var broken: Array = []
	var checked: int = 0
	for vid_v in DL.venue_order():
		var vid: String = str(vid_v)
		# retheme() is the real venue switch. Assigning GameState.current_venue
		# alone leaves the floor on its previous building, which silently makes
		# a twelve-venue sweep twelve measurements of venue one.
		_floor.retheme(vid)
		_floor._props_key = ""
		_floor._rebuild_props()
		checked += 1

		var lobby: Dictionary = _floor._theme.role("lobby")
		if lobby.is_empty():
			broken.append("%s: no lobby" % vid)
			continue
		var from_id: Vector2i = _walkable_in(lobby["rect"] as Rect2)
		if from_id.x == 1 << 30:
			broken.append("%s: lobby has no walkable cell" % vid)
			continue

		if vid == "copper_kettle":
			var cafe: Dictionary = _floor._theme.role("promo")
			var cafe_rect: Rect2 = cafe["rect"]
			var table_seats := 0
			for prop in _floor._theme.props:
				if str(prop.get("kind", "")) != "cafe_table":
					continue
				for off in _floor.Exhibits.cafe_seat_offsets(prop):
					var seat: Vector2 = _floor.Exhibits.v2(prop.get("at")) + off
					var seat_id: Vector2i = _floor._nav_id(seat)
					table_seats += 1
					check(_floor._seats.has(seat), "Tidewater drawn stool has a visitor seat: %s" % seat)
					check(not _floor._nav.is_point_solid(seat_id) and not _floor._nav.get_id_path(from_id, seat_id).is_empty(), "Tidewater bistro seat reachable: %s" % seat)
			check(table_seats == 6, "Tidewater bistro tables seat six visitors")
			for spot in cafe.get("visitor_spots", []):
				var offset: Vector2 = spot if spot is Vector2 else Vector2(float(spot[0]),float(spot[1]))
				var target := cafe_rect.position + offset
				var target_id: Vector2i = _floor._nav_id(target)
				check(not _floor._nav.is_point_solid(target_id) and not _floor._nav.get_id_path(from_id,target_id).is_empty(), "Tidewater café destination reachable: %s" % target)

		if vid == "sunspire":
			check(_floor._theme.level_at(Vector2(6.5, 10.5)) == 0, "Sunspire solar court is at ground level")
			check(_floor._theme.level_at(Vector2(7.0, 4.0)) == 1, "Sunspire collection remains raised")
			var dial_views := 0
			for exhibit in _floor._theme.exhibits:
				if str(exhibit.get("id", "")) != "solar_dial":
					continue
				for off in exhibit.get("views", []):
					var target: Vector2 = _floor.Exhibits.v2(exhibit.get("anchor")) + _floor.Exhibits.v2(off)
					var target_id: Vector2i = _floor._nav_id(target)
					dial_views += 1
					check(not _floor._nav.is_point_solid(target_id) and not _floor._nav.get_id_path(from_id, target_id).is_empty(), "Sunspire sundial view reachable: %s" % target)
			check(dial_views == 3, "Sunspire sundial offers three viewing positions")

		if vid == "grand_river":
			var garden_seats := 0
			for seat in _floor._seats:
				if _floor.room_rect("scholars_court").has_point(seat):
					garden_seats += 1
					var seat_id: Vector2i = _floor._nav_id(seat)
					check(not _floor._nav.is_point_solid(seat_id) and not _floor._nav.get_id_path(from_id, seat_id).is_empty(), "Grand River garden seat reachable: %s" % seat)
			check(garden_seats == 4, "Grand River garden offers four reachable seat anchors")

		for entry in _floor._theme.rooms:
			var room: Dictionary = entry
			var role: String = str(room.get("role", ""))
			if bool(room.get("nav_blocked", false)) or not bool(room.get("visible", true)):
				continue  # Deliberate non-walkable boundary volumes are not destinations.
			var name: String = str(room.get("id", role))
			var to_id: Vector2i = _walkable_in(room["rect"] as Rect2, from_id)
			if to_id.x == 1 << 30:
				broken.append("%s/%s: no reachable interior sample" % [vid, name])
				continue
			if to_id == from_id:
				continue
			if _floor._nav.get_id_path(from_id, to_id).is_empty():
				broken.append("%s/%s (storey %d): UNREACHABLE from the lobby"
					% [vid, name, int(room.get("level", 0))])

	check(checked >= 12, "swept every venue (%d)" % checked)
	check(broken.is_empty(),
		"every room is reachable from the lobby in every venue (%d break%s)%s"
			% [broken.size(), "" if broken.size() == 1 else "s",
				"" if broken.is_empty() else ":\n    " + "\n    ".join(broken)])
