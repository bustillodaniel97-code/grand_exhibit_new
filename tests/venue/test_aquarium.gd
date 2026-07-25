extends SceneTree
## Aquarium suite: venue 2 is a DIFFERENT attraction, not venue 1 repainted.
##
## Venue progression is one-way, so the aquarium is the first thing a player sees
## after giving up the natural-history hall forever. Three classes of defect
## would make that landing flat, and all three are silent:
##   · the theme not being its own — an `extends` left in, a plan that is the
##     first venue's rects, a palette that still reads warm at a glance.
##   · geometry that only works for venue 1. Every waypoint here is derived from
##     THESE room rects, and the projected diamond is 960px wide against a 720px
##     canvas, so a room placed a tile too far east puts its props and the people
##     walking to them off screen with no error at all.
##   · a floor plan with a hole in it. Rooms are the only thing painted over the
##     shell slab, so a tile no room claims is a patch of bare foundation in the
##     middle of the building.
## Run: godot --headless --path <repo> -s tests/venue/test_aquarium.gd (exit 0 pass)

const Iso := preload("res://scenes/venue/floor/iso.gd")
const Exhibits := preload("res://scenes/venue/floor/exhibits.gd")
const City := preload("res://scenes/venue/floor/city.gd")
## Loaded at RUNTIME: venue_floor.gd refers to the EventBus autoload, and a
## preload is compiled before this suite has registered it.
var VF: GDScript

## The venue the aquarium is authored on. Its data id still reads "copper_kettle"
## because quests, the store and three other suites key off that string; the
## PLAYER-facing name is the aquarium's.
const VENUE := "copper_kettle"
## Pixels of margin a prop anchor or waypoint must keep from the clip edge, as in
## tests/venue/test_geometry.gd — half a tile of x, enough for a figure's width.
const EDGE_INSET := 26.0
## Minimum props per room, matched to the density floor the first venue holds.
const MIN_PROPS := {"gallery": 12, "archive": 7, "promotions": 6, "ticket": 12, "lobby": 10}

var _fail: int = 0
var _dl: Node
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
	_dl = root.get_node("DataLoader")
	_dl.reload_all()
	VF = load("res://scenes/venue/floor/venue_floor.gd") as GDScript

	_check_identity()
	_check_plan()
	_check_surround()
	_check_views_in_their_room()
	_boot_floor()

# --- data ----------------------------------------------------------------------

## The aquarium has to be authored, not inherited, and it has to read cool from
## across the room. Both are things a well-meaning edit can undo without any test
## noticing, and both are the whole point of the venue.
func _check_identity() -> void:
	var raw: Dictionary = _dl.get_venue(VENUE).get("theme", {}) as Dictionary
	check(not raw.has("extends"), "the aquarium authors its own theme instead of inheriting one")
	check(raw.has("rooms") and raw.has("exhibits") and raw.has("palette"),
		"the theme block carries its own plan, palette and exhibits")

	var t: Object = VF.VenueTheme.for_venue(VENUE)
	var first: Object = VF.VenueTheme.for_venue("whispering_pines")
	# Cool against the dark shell is the brief: every department accent must be
	# bluer than it is red, which is the cheapest honest test of "at a glance".
	var warm: String = ""
	for dept in ["ticket", "gallery", "archive", "promotions"]:
		var col: Color = t.accent(dept)
		if col.b <= col.r:
			warm = "%s %s" % [dept, col.to_html(false)]
	check(warm == "", "every room accent reads cool, blue over red (offender %s)" % warm)
	var shared: String = ""
	for dept in ["ticket", "gallery", "archive", "promotions"]:
		if t.accent(dept).is_equal_approx(first.accent(dept)):
			shared = dept
	check(shared == "", "no accent is the natural-history venue's (offender %s)" % shared)
	check(t.col("floor").b > first.col("floor").b
		and t.col("floor").r < first.col("floor").r,
		"the floor is sea glass where the first venue's is cream")

	# Sea life needed kinds the dinosaur hall did not. Naming them here is what
	# stops a later "tidy-up" collapsing the aquarium back onto plinths.
	var used: Dictionary = {}
	for entry in (t.exhibits + t.props):
		used[str((entry as Dictionary).get("kind", ""))] = true
	for band in ["carpet", "floor", "wall", "ceiling"]:
		for entry in t.dressing.get(band, []):
			used[str((entry as Dictionary).get("kind", ""))] = true
	for kind in ["tank", "hung_skeleton", "touch_pool", "kelp", "porthole"]:
		check(used.has(kind), "the aquarium uses the '%s' kind" % kind)
	var unknown: String = ""
	for kind in used.keys():
		if not Exhibits.has_kind(str(kind)):
			unknown = str(kind)
	check(unknown == "", "every kind the aquarium names is registered (offender '%s')" % unknown)

## The floor plan has to tile the whole footprint: rooms are the only thing
## painted over the shell, so an uncovered tile is bare foundation indoors, and
## an overlapping one makes whichever department loses the tap unreachable.
func _check_plan() -> void:
	var t: Object = VF.VenueTheme.for_venue(VENUE)
	var first: Object = VF.VenueTheme.for_venue("whispering_pines")
	check(t.rooms.size() >= 5, "the plan has %d rooms" % t.rooms.size())
	var same: int = 0
	for room in t.rooms:
		var id: String = str((room as Dictionary).get("id", ""))
		if first.rect(id) == (room["rect"] as Rect2) and first.rect(id) != Rect2():
			same += 1
	check(same == 0, "no room keeps the first venue's rect (%d did)" % same)

	var clash: String = ""
	for a in t.rooms:
		for b in t.rooms:
			if a == b:
				continue
			if (a["rect"] as Rect2).intersects(b["rect"] as Rect2):
				clash = "%s/%s" % [a.get("id"), b.get("id")]
	check(clash == "", "no two rooms overlap (offender %s)" % clash)

	# Sample the centre of every tile in the footprint; each must land in exactly
	# one room.
	var holes: int = 0
	var hole := Vector2.ZERO
	for gx in int(Iso.GRID.x):
		for gy in int(Iso.GRID.y):
			var p := Vector2(float(gx) + 0.5, float(gy) + 0.5)
			var hits: int = 0
			for room in t.rooms:
				if (room["rect"] as Rect2).has_point(p):
					hits += 1
			if hits != 1:
				holes += 1
				hole = p
	check(holes == 0, "every tile of the %s footprint belongs to exactly one room (%d bad, e.g. %s)"
		% [Iso.GRID, holes, hole])

	for want in ["queue", "store", "lobby", "exhibit", "promo"]:
		check(not (t.role(want) as Dictionary).is_empty(), "the plan fills the '%s' role" % want)
	var named: int = 0
	for room in t.rooms:
		if str((room as Dictionary).get("name", "")) != "":
			named += 1
	check(named >= 4, "the rooms carry their own names (%d named)" % named)

## An aquarium on a parkland lawn is the tell that the surround was never
## authored, and the fallback for an unknown style is silent.
func _check_surround() -> void:
	var t: Object = VF.VenueTheme.for_venue(VENUE)
	check(t.surround == "harbour", "the aquarium asks for the harbour surround ('%s')" % t.surround)
	check(City.STYLES.has("harbour"), "City ships the harbour style rather than falling back")
	var sea: Dictionary = City.palette_for("harbour")
	var park: Dictionary = City.palette_for("parkland")
	var water: Color = sea["lawn"]
	check(water.b > water.g and water.b > water.r, "the harbour's ground plane is water, not grass")
	check(not water.is_equal_approx(park["lawn"] as Color),
		"the harbour repaints the derived scheme instead of inheriting it")
	check(not (sea["runner"] as Color).is_equal_approx(park["runner"] as Color),
		"the entrance runner is the aquarium's, not the first venue's red")
	check((City.style_def("harbour") as Dictionary).get("blocks", []) != [],
		"the harbour carries its scenery as data")

## Every viewing spot must stand in the room that holds the exhibit it belongs
## to. Views are offsets from the anchor, so an exhibit nudged half a tile takes
## its audience through a wall with it.
func _check_views_in_their_room() -> void:
	var t: Object = VF.VenueTheme.for_venue(VENUE)
	var stray: String = ""
	var counted: int = 0
	for entry in t.exhibits:
		var e: Dictionary = entry as Dictionary
		var origin: Vector2 = Exhibits.anchor(e)
		var home := Rect2()
		for room in t.rooms:
			if (room["rect"] as Rect2).has_point(origin):
				home = room["rect"] as Rect2
		if home == Rect2():
			stray = "%s has no room" % e.get("id")
			continue
		for off in Exhibits.points(e.get("views", [])):
			counted += 1
			if not home.has_point(origin + off):
				stray = "%s -> %s outside %s" % [e.get("id"), origin + off, home]
	check(stray == "", "all %d viewing spots stand in their exhibit's room (offender %s)"
		% [counted, stray])
	check(t.exhibits.size() >= 6, "the aquarium shows %d exhibits" % t.exhibits.size())

# --- live floor ----------------------------------------------------------------

func _boot_floor() -> void:
	var gs: Node = root.get_node("GameState")
	gs.reset_to_new_game()
	if not (VENUE in gs.venues_unlocked):
		gs.venues_unlocked.append(VENUE)
	gs.current_venue = VENUE
	# A maxed venue is the case the geometry has to survive: five ticket windows
	# open, a full cast, every room's props built.
	for dept in ["ticket", "archive", "promotions", "gallery"]:
		for track in ["staff", "speed", "value"]:
			gs.set_dept_level(VENUE, dept, track, 14)
	gs.ready_flag = true

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
	if _frames == 3:
		# One-way progression arrives here through prestige, so exercise the same
		# path the player takes rather than instantiating the floor on the venue.
		_floor.retheme(VENUE)
	_floor.set_rates(root.get_node("Economy").venue_rates(VENUE))
	_t += delta
	if _t < 6.0:
		return false
	_done = true
	_check_live()
	print("---")
	if _fail == 0:
		print("ALL AQUARIUM CHECKS PASSED")
	quit(0 if _fail == 0 else 1)
	return true

func _check_live() -> void:
	check(_floor.theme_id() == VENUE, "the live floor is showing the aquarium")
	check(_floor.theme_surround() == "harbour", "the live floor asked City for the harbour")

	var props: Array[Vector2] = _floor.prop_anchors()
	var off: int = 0
	var worst := Vector2.ZERO
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

	# A waypoint inside a prop's footprint stands somebody in the furniture.
	var near: float = 1e9
	var np := Vector2.ZERO
	var ng := Vector2.ZERO
	for g in spots:
		for p in props:
			var d: float = g.distance_to(p)
			if d < near:
				near = d
				np = p
				ng = g
	check(near >= 0.34,
		"no waypoint sits on a prop anchor (closest %.2f tiles: %s vs prop %s)" % [near, ng, np])

	var plaques: Dictionary = _floor.plaque_points()
	for dept in plaques.keys():
		var at: Vector2 = Iso.to_screen(plaques[dept])
		check(at.x > 70.0 and at.x < Iso.VIEW.x - 70.0,
			"%s plaque leaves room for its chip at x=%.0f" % [dept, at.x])

	# Counters and queue slots are derived from the ticket rect; a queue that runs
	# out of its own room walks the line through the lobby wall.
	var q: Dictionary = _floor.queue_geometry()
	var q_rect: Rect2 = _floor.room_rect("ticket")
	var inside: bool = true
	for gx in q["window_gx"]:
		if float(gx) < q_rect.position.x or float(gx) > q_rect.end.x:
			inside = false
	check(inside and float(q["counter_gy"]) > q_rect.position.y
		and float((q["slot_gy"] as Array).back()) < q_rect.end.y,
		"the whole queue fits inside the ticket rect %s (counter %.2f, last slot %.2f)"
			% [q_rect, q["counter_gy"], (q["slot_gy"] as Array).back()])

	# Browse spots against the LIVE rects, which is the pair the FSM actually
	# walks: the data check above ran before the floor derived anything.
	var gallery: Rect2 = _floor.room_rect("gallery")
	var stray: String = ""
	var browse: Dictionary = _floor.browse_spots()
	for key in browse.keys():
		for g in browse[key]:
			if not gallery.has_point(g):
				stray = "%s at %s" % [key, g]
	check(stray == "", "every browse spot stands in the tidal hall (offender %s)" % stray)

	var per := {"gallery": 0, "archive": 0, "promotions": 0, "ticket": 0, "lobby": 0}
	for g in props:
		if gallery.has_point(g) or _floor.room_rect("kelpwalk").has_point(g):
			per["gallery"] += 1
		elif _floor.room_rect("archive").has_point(g):
			per["archive"] += 1
		elif _floor.room_rect("promotions").has_point(g):
			per["promotions"] += 1
		elif q_rect.has_point(g):
			per["ticket"] += 1
		else:
			per["lobby"] += 1
	for room in MIN_PROPS.keys():
		check(per[room] >= int(MIN_PROPS[room]),
			"%s carries at least %d props (%d)" % [room, MIN_PROPS[room], per[room]])
	check(props.size() >= 55, "the floor carries at least 55 props (%d)" % props.size())

	# Taps have to reach every department on THIS plan, not on venue 1's.
	for dept in ["ticket", "gallery", "archive", "promotions"]:
		check(_floor.tap_zone_at(_floor.room_center(dept)) == dept,
			"a tap in the middle of the %s room selects it" % dept)
	check(_floor.get_alive_visitor_count() > 0, "the aquarium fills with visitors")
