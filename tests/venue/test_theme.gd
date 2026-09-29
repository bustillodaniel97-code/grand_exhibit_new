extends SceneTree
## Theme suite: a venue is a THEME, not a row of economic numbers.
##
## Three classes of defect live here, all of them silent at runtime:
##   · a theme that does not resolve — a typo'd palette key, a kind with no
##     painter, an `extends` that points nowhere — draws NOTHING and reports
##     nothing, exactly like the off-canvas props did before test_geometry.
##   · derived geometry drifting out of the room it was derived from. Counters,
##     queue slots and browse spots are computed from room rects precisely so
##     they cannot disagree with the plan; this is what holds that claim.
##   · a kind in the registry that nobody has drawn yet. Three more venues get
##     authored against this vocabulary, so every kind is rendered here — an
##     entry with a broken painter fails now rather than on the aquarium.
## Run: godot --headless --path <repo> -s tests/venue/test_theme.gd (exit 0 pass)

const Exhibits := preload("res://scenes/venue/floor/exhibits.gd")
const City := preload("res://scenes/venue/floor/city.gd")
## Loaded at RUNTIME: venue_floor.gd refers to the EventBus autoload, and a
## preload is compiled before this suite has registered it.
var VF: GDScript

var _fail: int = 0
## Autoloads are registered as plain nodes by this suite, so the DataLoader
## global identifier does not exist at parse time — reach it through the tree.
var _dl: Node
var _floor: Control
var _frames: int = 0

func check(cond: bool, msg: String) -> void:
	if cond:
		print("PASS: ", msg)
	else:
		_fail += 1
		printerr("FAIL: ", msg)

func _initialize() -> void:
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

	_check_every_venue_resolves()
	_check_natural_history_plan()
	_check_colour_tokens()
	_check_registry_draws()
	_check_surround_styles()
	# The live floor's checks wait for frames. A node added to the tree from
	# _initialize() has not run _ready() yet, so reading its theme here would
	# silently see a null and pass every assertion by accident.
	_floor = (load("res://scenes/venue/floor/venue_floor.tscn") as PackedScene).instantiate()
	_floor.set_size(Vector2(720, 760))
	root.add_child(_floor)

func _process(_delta: float) -> bool:
	_frames += 1
	if _frames < 3:
		return false
	_check_derived_geometry()
	print("---")
	if _fail == 0:
		print("ALL THEME CHECKS PASSED")
	quit(0 if _fail == 0 else 1)
	return true

# --- data ---------------------------------------------------------------------

## Every venue has to produce a usable theme, whether it authors one or inherits
## it. A venue that renders as an empty slab is the failure mode this replaces.
func _check_every_venue_resolves() -> void:
	for vid in _dl.venue_order():
		var t: Object = VF.VenueTheme.for_venue(str(vid))
		var ok: bool = t.rooms.size() >= 4 and not t.palette.is_empty() \
			and not t.props.is_empty() and not t.exhibits.is_empty()
		check(ok, "%s resolves a theme (%d rooms, %d exhibits, %d props)"
			% [vid, t.rooms.size(), t.exhibits.size(), t.props.size()])
		check(not t.role("queue").is_empty() and not t.role("store").is_empty()
			and not t.role("lobby").is_empty() and not t.role("exhibit").is_empty(),
			"%s fills the four load-bearing roles" % vid)
		var bad_kind: String = ""
		for entry in (t.exhibits + t.props):
			var kind: String = str((entry as Dictionary).get("kind", ""))
			if not Exhibits.has_kind(kind):
				bad_kind = kind
		for band in ["carpet", "floor", "wall", "ceiling"]:
			for entry in t.dressing.get(band, []):
				var kind: String = str((entry as Dictionary).get("kind", ""))
				if not Exhibits.has_kind(kind):
					bad_kind = kind
		check(bad_kind == "", "%s names only registered kinds (offender '%s')"
			% [vid, bad_kind])

## The shipped natural-history plan, asserted as data rather than as pixels: the
## conversion is only honest if the rooms are still where the FSM expects them.
func _check_natural_history_plan() -> void:
	var t: Object = VF.VenueTheme.for_venue("whispering_pines")
	check(t.surround == "parkland", "whispering_pines asks for the parkland surround")
	var all_ground := true
	for room in t.rooms:
		all_ground = all_ground and int(room.get("level",0))==0 and int(room.get("rise_to",0))==0
	check(all_ground,"Pines is an accessible ground-level lodge without the repeated center stair")
	check(t.rect("archive").end.x<=t.rect("gallery").position.x,"Pines conservation occupies its rear-left wing")
	check(not t.rect("reception_court").size.is_zero_approx(),"Pines has a separate reception court for its second admission group")
	# Rooms may not overlap: a tap lands in the first one that claims the tile,
	# so an overlap makes a department unreachable without any error.
	var clash: String = ""
	for a in t.rooms:
		for b in t.rooms:
			if a == b:
				continue
			if (a["rect"] as Rect2).intersects(b["rect"] as Rect2):
				clash = "%s/%s" % [a.get("id"), b.get("id")]
	check(clash == "", "no two rooms overlap (offender %s)" % clash)
	# An inheriting venue must come back with the SAME plan, or `extends` is a
	# copy that will drift.
	#
	# Tested against a SYNTHETIC heir registered into DataLoader for the duration
	# of the check, not against a shipped venue. An earlier version scanned the
	# roster for whoever still inherited, which meant the mechanism went untested
	# the moment the last venue got its own theme — and that is precisely when a
	# regression in it would go unnoticed. `extends` stays supported for future
	# venues whether or not any current one uses it, so the test says that.
	var loader: Node = _dl
	var probe := "test_heir_probe"
	(loader.venues as Dictionary)[probe] = {
		"id": probe, "name": "Heir Probe", "order": 999,
		"theme": {"extends": "whispering_pines"},
	}
	check(VF.VenueTheme.raw_extends(probe) == "whispering_pines",
		"`extends` is read back off the venue's theme block")
	var heir: Object = VF.VenueTheme.for_venue(probe)
	check(heir.rect("gallery") == t.rect("gallery")
		and heir.exhibits.size() == t.exhibits.size()
		and heir.surround == t.surround,
		"an heir resolves to the parent's plan, exhibits and surround")

	# And an override replaces a whole top-level key while the rest still comes
	# down the chain — the half of `extends` that a plain copy would not give.
	(loader.venues as Dictionary)[probe]["theme"] = {
		"extends": "whispering_pines", "surround": "nightfall",
	}
	var tweaked: Object = VF.VenueTheme.for_venue(probe)
	check(tweaked.surround == "nightfall" and tweaked.rect("gallery") == t.rect("gallery"),
		"an heir can override one key and inherit the rest")
	(loader.venues as Dictionary).erase(probe)

# --- derived geometry ----------------------------------------------------------

## Counters, queue slots and browse spots are DERIVED from room rects. This is
## the check that keeps that true: a theme edit that moves a wall must move them,
## and one that does not is the silent disagreement the derivation exists to
## prevent.
func _check_derived_geometry() -> void:
	var floor_node: Control = _floor
	var q: Dictionary = floor_node.queue_geometry()
	var inside := true
	for w in int(q.windows):
		var station: Dictionary = q.stations[w]
		var room: Rect2 = floor_node.room_rect(station.room)
		inside = inside and room.has_point(station.center)
		for j in int(q.slots):inside = inside and room.has_point(floor_node._slot_pos(w,j))
	check(inside,"every counter and queue slot belongs to its authored admission room")
	check(int(q["windows"]) == 5 and int(q["slots"]) == 6,
		"queue derives 5 windows of 6 slots (%d x %d)" % [q["windows"], q["slots"]])

	# Every browse spot must stand in the room that holds its exhibit, or a
	# visitor walks through a wall to look at it.
	var spots: Dictionary = floor_node.browse_spots()
	check(spots.size() >= 6, "the theme publishes %d exhibits with viewing spots" % spots.size())
	var stray: String = ""
	var gallery: Rect2 = floor_node.room_rect("gallery")
	for key in spots.keys():
		for g in spots[key]:
			if not gallery.has_point(g):
				stray = "%s at %s" % [key, g]
	check(stray == "", "every browse spot stands in the gallery (offender %s)" % stray)

	# Re-theming is what makes one-way venue progression visible. It must not
	# leave the previous venue's cast or props behind.
	# Re-themed to an INHERITING venue, so the prop count is the one thing that
	# must not move: a rebuild that ran twice, or one that failed to clear, shows
	# up as a count that is not the count it started with. (The aquarium's own
	# rebuild is covered by tests/venue/test_aquarium.gd, which knows its plan.)
	# Re-theme to an INHERITING venue, whose plan is identical to the one the
	# floor already holds — that is what makes a changed prop count mean "rebuilt
	# twice or failed to clear" rather than "this venue simply has more props".
	var twin: String = ""
	for vid in ["sunspire", "cloudrest", "aurora_world"]:
		if VF.VenueTheme.raw_extends(vid) == "whispering_pines":
			twin = vid
			break
	if twin == "":
		twin = "whispering_pines"
	var before: int = floor_node.prop_anchors().size()
	floor_node.retheme(twin)
	check(floor_node.theme_id() == twin, "retheme switches the live venue")
	check(floor_node.prop_anchors().size() == before,
		"re-themed floor rebuilds its props exactly once (%d -> %d)"
			% [before, floor_node.prop_anchors().size()])
	check(floor_node.get_alive_visitor_count() == 0,
		"re-theming sends the old venue's visitors home")

	# A venue's authored overview includes its zoom and framing offset. Retheme is
	# the live prestige path, so it must apply both immediately rather than waiting
	# for an unrelated window resize before the next museum is framed correctly.
	floor_node.retheme("chronos_spire")
	var authored_scale: float = floor_node._theme.camera_zoom
	var centered: Vector2 = (floor_node.size - floor_node.FLOOR * authored_scale) * 0.5
	check(is_equal_approx(floor_node._canvas.scale.x, authored_scale),
		"retheme immediately applies the new venue's authored camera zoom")
	check(floor_node._canvas.position.is_equal_approx(
		centered + floor_node._theme.camera_offset * authored_scale),
		"retheme immediately applies the new venue's authored framing offset")

# --- palette ------------------------------------------------------------------

func _check_colour_tokens() -> void:
	var t: Object = VF.VenueTheme.for_venue("whispering_pines")
	var trim: Color = t.col("trim")
	check(trim.is_equal_approx(Color("#B39358")), "a palette key resolves to its literal")
	check((t.resolve("@trim|d28") as Color).is_equal_approx(trim.darkened(0.28)),
		"the |dNN modifier darkens by NN percent")
	check((t.resolve("@trim|l12") as Color).is_equal_approx(trim.lightened(0.12)),
		"the |lNN modifier lightens by NN percent")
	check((t.resolve("#123456") as Color).is_equal_approx(Color("#123456")),
		"a literal hex passes straight through")
	check(t.resolve("GRAND GALLERY") == "GRAND GALLERY",
		"a plain string is left alone")
	# A typo must be loud. Magenta on the floor is impossible to mistake for art.
	check((t.resolve("@no_such_key") as Color).is_equal_approx(
		VF.VenueTheme.MISSING), "an unknown palette key resolves to the loud MISSING colour")
	# roomfloor.<id> is computed, not authored, and the dressing leans on it.
	check(t.col("roomfloor.gallery").is_equal_approx(
		t.accent("gallery").lerp(t.col("floor"), float(t.by_id.gallery.floor_mix))),
		"roomfloor.<room> is the room accent mixed toward the floor colour")

# --- registry ------------------------------------------------------------------

## Draw one of every kind. A painter that throws, or a kind in the lists with no
## entry in painter(), fails here instead of on somebody else's venue.
func _check_registry_draws() -> void:
	var host := Node2D.new()
	root.add_child(host)
	var drawn: int = 0
	var kinds: Array[String] = Exhibits.kinds()
	for kind in kinds:
		var spec: Dictionary = {
			"at": [3.0, 3.0], "size": [1.4, 0.8], "len": 1.4, "points": [[3.0, 3.0], [4.0, 3.0]],
			"from": [3.0, 3.0], "to": [5.0, 3.0], "bays": 3, "fauna_count": 3,
			"label": "1", "wings": true,
		}
		var painter: Callable = Exhibits.guarded(kind, spec)
		var n := Node2D.new()
		host.add_child(n)
		n.draw.connect(func() -> void: painter.call(n))
		n.queue_redraw()
		drawn += 1
	check(drawn == kinds.size(), "every one of the %d registered kinds has a painter" % drawn)
	check(kinds.has("tank") and kinds.has("hanging") and kinds.has("mural"),
		"the registry carries the kinds an aquarium and an aviary need")
	# Anchors: a piece with a footprint centres on it, one without is placed BY
	# its anchor, and an explicit anchor always wins.
	check(Exhibits.anchor({"at": [2.0, 4.0]}) == Vector2(2.0, 4.0),
		"a footprint-less kind anchors at `at`")
	check(Exhibits.anchor({"at": [2.0, 4.0], "size": [2.0, 1.0]}) == Vector2(3.0, 4.5),
		"a kind with a size anchors at its footprint centre")
	check(Exhibits.anchor({"at": [2.0, 4.0], "size": [2.0, 1.0], "anchor": [9.0, 9.0]})
		== Vector2(9.0, 9.0), "an explicit anchor overrides the default")
	host.queue_free()

# --- surround ------------------------------------------------------------------

func _check_surround_styles() -> void:
	check(City.STYLES.has("parkland"), "City ships the parkland surround style")
	var known: Dictionary = City.style_def("parkland")
	check(not (known.get("trees", []) as Array).is_empty(),
		"parkland carries its scenery as data, not as code")
	# A venue naming a style nobody has authored yet must still render a world.
	# "harbour" used to be the example here; the aquarium ships it, so the probe
	# moved to a style no venue has claimed.
	check(City.style_def("cliffside") == known,
		"an unauthored style falls back to parkland instead of drawing nothing")
	check(not City.palette_for("parkland").is_empty(),
		"a style yields a palette without needing a City instance")
	for vid in _dl.venue_order():
		var t: Object = VF.VenueTheme.for_venue(str(vid))
		check(t.surround != "", "%s names a surround style ('%s')" % [vid, t.surround])
