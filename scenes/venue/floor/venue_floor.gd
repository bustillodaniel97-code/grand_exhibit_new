extends Control
## VenueFloor — the living museum, as an isometric diorama.
##
## The simulation runs entirely in GRID space (see iso.gd); nothing here knows
## about canvas pixels except at draw time and at tap time. That separation is
## what let the visitor/porter FSM come across from the old flat-plan version
## unchanged — only the waypoint constants changed units, from pixels to tiles.
##
## WHAT THIS FILE NO LONGER DECIDES. The floor plan, the room names, the palette,
## the exhibits, the furniture, the wall art and the surround are all THEME data
## now (data/venues.json -> venue.theme, drawn through exhibits.gd). This file
## owns the simulation and the assembly; a venue owns how it looks. That split is
## the point: six venues used to render as the same building because the building
## was written here.
##
## Everything the cast walks to DERIVES from the theme's room rects. Counters sit
## a fixed inset into the queue room, queue slots run back from the counters,
## browse spots are offsets from the exhibit they belong to, and the porters'
## home is relative to the store room. Move a rect and the room moves with it —
## there is no second copy of the layout that can silently disagree.
##
## Props are individual Y-sorted nodes rather than one flat static layer, so a
## visitor can stand behind a counter and in front of a bench in the same frame.

signal dept_selected(dept_id: String)
signal item_selected(dept_id: String, index: int)

const UI := preload("res://scripts/ui/ui_kit.gd")
const IncomeFeedback := preload("res://scenes/venue/floor/income_feedback.gd")
const Character := preload("res://scenes/venue/floor/character.gd")
const VenueGrade := preload("res://scenes/venue/floor/venue_grade.gdshader")
const Iso := preload("res://scenes/venue/floor/iso.gd")
const PublicPlaza := preload("res://scenes/venue/floor/public_plaza.gd")
const City := preload("res://scenes/venue/floor/city.gd")
const MuseumArchitecture := preload("res://scenes/venue/floor/museum_architecture.gd")
const MuseumProps := preload("res://scenes/venue/floor/museum_props.gd")
const MuseumSurfaces := preload("res://scenes/venue/floor/museum_surfaces.gd")
const Exhibits := preload("res://scenes/venue/floor/exhibits.gd")
const ManagerSystem := preload("res://scripts/managers/manager_system.gd")
const DecorSystem := preload("res://scripts/meta/decor_system.gd")

const FLOOR := Vector2(720, 760)      # logical canvas the diorama is fitted into

## Pixels of margin a decor anchor keeps from the horizontal clip edge. One tile
## of x is 60px, so half a tile is enough to keep a piece's own width on screen.
const DECOR_EDGE_INSET := 26.0

# --- Fixed simulation limits ---------------------------------------------------
##
## Engine budgets, not venue dressing: they bound how many nodes the floor can
## hold and how fast the visual loop may run, so they stay here rather than in a
## theme where a content author could quietly triple the draw calls.
const MAX_ALIVE := 34
const MAX_CROWD := 14
const MAX_STACK_VIS := 10
const HARD_MAX_WINDOWS := 5
## Seconds a window spends on one visitor, as a VISUAL pace — the economy's real
## throughput is Economy's business, not the diorama's.
##
## The floor is a closed system of MAX_ALIVE people, so where they stand is set
## purely by the ratio of dwell times, and the old 0.6s floor made the ticket
## hall the fastest stage by an order of magnitude: five windows chewing through
## 8 visitors a second emptied every queue and parked the entire crowd in the
## gallery. Measured over 180 sim seconds, a 4.8s floor holds ~13 people in the
## queues, ~10 at the exhibits and ~11 crossing the lobby, against 4 / 16 / 14
## before; tests/venue/test_geometry.gd asserts no single state takes the floor.
const MIN_SERVE_S := 4.8

# --- Depth --------------------------------------------------------------------
## Actors shrink slightly toward the back of the hall. Subtle on top of a real
## iso projection — the projection already carries most of the depth read.
const DEPTH_SCALE_BACK := 0.88
const DEPTH_SCALE_FRONT := 1.06

# --- Theme --------------------------------------------------------------------

## One venue's look, resolved from data/venues.json.
##
## A theme is inert: it parses, resolves its colour tokens and hands back plain
## dictionaries of Rect2s, Vector2s and Colors. It never draws and never touches
## a node, which is what lets a test load one and assert on a floor plan without
## booting the diorama.
class VenueTheme extends RefCounted:
	## Colour tokens a theme may use anywhere a colour is expected:
	##   "@trim"              a palette key
	##   "@room.gallery|d10"  that key, darkened 0.10
	##   "@floor|l14"         that key, lightened 0.14
	##   "#RRGGBB"            a literal
	## A key that does not exist resolves to magenta and warns, because a silent
	## fallback to black is indistinguishable from a shadow.
	const MISSING := Color(1.0, 0.0, 1.0)
	## How many `extends` hops to follow before assuming the data is cyclic.
	const MAX_INHERIT := 4

	var id: String = ""
	var surround: String = "parkland"
	var palette: Dictionary = {}          # String -> Color
	var rooms: Array = []                 # resolved room dicts, in draw order
	var by_id: Dictionary = {}            # room id -> room dict
	var by_dept: Dictionary = {}          # dept id -> room dict
	var shell: Dictionary = {}
	## Union of every room rect — the venue's true footprint in tiles.
	var bounds: Rect2 = Rect2()
	var walls: Array = []
	var exhibits: Array = []
	var props: Array = []
	var dressing: Dictionary = {}
	## Hand-authored display points for purchased decor. Keeping these in venue
	## data lets a harbour use quay/gallery edges while a mountain hall uses its
	## terraces; decor no longer repeats the first venue's lobby row everywhere.
	var decor_anchors: Array[Vector2] = []
	## Optional per-venue spatial treatment. `layout_spread` increases authored
	## grid distances without enlarging furniture; `camera_zoom` then frames the
	## larger building. Together they let later museums grow instead of cramming
	## more departments into the introductory venue's footprint.
	var layout_spread: float = 1.0
	var camera_zoom: float = 1.0
	## Authored framing adjustment in logical canvas pixels. Some tall late venues
	## need the building centred above the default midpoint so their entrance is
	## visible without shrinking the cast below the readable camera floor. This is
	## separate from the player's pan: changing venue restores this composition.
	var camera_offset := Vector2.ZERO
	## The readable floor on `camera_zoom`, enforced HERE so the stored value is
	## the effective one. Authoring used to be able to ask for 0.24 while the
	## renderer quietly drew at 0.48, which made four late venues untunable: the
	## dial moved and nothing on screen did. Below this the cast is confetti, so a
	## venue too big for one screen must shrink its LAYOUT and let the player pan.
	const MIN_CAMERA_ZOOM := 0.48
	const MAX_CAMERA_ZOOM := 1.15

	## Which venue this one inherits from, or "" if it authors its own theme.
	## Exposed so tooling and tests can ask "is this still an heir?" instead of
	## hardcoding a venue id that stops being one the day someone authors it.
	static func raw_extends(venue_id: String) -> String:
		var v: Dictionary = DataLoader.get_venue(venue_id)
		var raw: Variant = v.get("theme")
		if raw is Dictionary:
			return str((raw as Dictionary).get("extends", ""))
		return ""

	## The theme for a venue, following `extends` and falling back to the first
	## venue that has one. A venue with no theme at all is a data error, not a
	## reason to leave the player looking at an empty slab.
	static func for_venue(venue_id: String) -> VenueTheme:
		var raw: Dictionary = _raw_for(venue_id)
		if raw.is_empty():
			for other in DataLoader.venue_order():
				raw = _raw_for(str(other))
				if not raw.is_empty():
					push_warning("Theme: venue '%s' has no theme, borrowing '%s'"
						% [venue_id, other])
					break
		var t := VenueTheme.new()
		t.id = venue_id
		t._build(raw)
		return t

	## Flatten an `extends` chain into one theme dict. Overrides replace whole
	## top-level keys, except `palette`, which merges key by key so a venue can
	## repaint one accent without restating the scheme.
	static func _raw_for(venue_id: String) -> Dictionary:
		var chain: Array[Dictionary] = []
		var cursor: String = venue_id
		for _hop in MAX_INHERIT:
			var block: Variant = DataLoader.get_venue(cursor).get("theme", {})
			if not (block is Dictionary) or (block as Dictionary).is_empty():
				break
			chain.push_front(block as Dictionary)
			var base: String = str((block as Dictionary).get("extends", ""))
			if base == "" or base == cursor:
				break
			cursor = base
		var out: Dictionary = {}
		for block in chain:
			for key in block.keys():
				if key == "palette" and out.has("palette"):
					var merged: Dictionary = (out["palette"] as Dictionary).duplicate()
					merged.merge(block["palette"] as Dictionary, true)
					out["palette"] = merged
				else:
					out[key] = block[key]
		out.erase("extends")
		return out

	func _build(raw: Dictionary) -> void:
		surround = str(raw.get("surround", "parkland"))
		layout_spread = maxf(float(raw.get("layout_spread", 1.0)), 0.5)
		var want_zoom: float = float(raw.get("camera_zoom", 1.0))
		camera_zoom = clampf(want_zoom, MIN_CAMERA_ZOOM, MAX_CAMERA_ZOOM)
		var offset: Variant = raw.get("camera_offset", [0.0, 0.0])
		if offset is Array and (offset as Array).size() >= 2:
			camera_offset = Vector2(float(offset[0]), float(offset[1]))
		if want_zoom < MIN_CAMERA_ZOOM - 0.005:
			push_warning(("Theme: venue '%s' asks for camera_zoom %.2f, below the "
				+ "readable floor %.2f — raised. Reduce layout_spread instead; the "
				+ "camera cannot shrink further without turning visitors into dots.")
				% [id, want_zoom, MIN_CAMERA_ZOOM])
		var pal: Dictionary = raw.get("palette", {}) as Dictionary
		for key in pal.keys():
			palette[str(key)] = _colour(str(pal[key]))
		# Rooms resolve next because dressing references "@roomfloor.<id>", which
		# only exists once a room's accent and its floor mix are known.
		_build_rooms(raw.get("rooms", []) as Array)
		shell = resolve(raw.get("shell", {})) as Dictionary
		# The building's real extent is the UNION of its rooms, not a fixed
		# rectangle. Deriving it is what lets a venue be L-shaped, have a
		# courtyard, or run tall and narrow instead of every venue being the
		# same 15x17 square with its rooms permuted inside it.
		bounds = Rect2()
		for entry in rooms:
			var rr: Rect2 = (entry as Dictionary)["rect"]
			bounds = rr if bounds.size == Vector2.ZERO else bounds.merge(rr)
		walls = _spread_specs(resolve(raw.get("walls", [])) as Array, true)
		exhibits = _spread_specs(resolve(raw.get("exhibits", [])) as Array)
		props = _spread_specs(resolve(raw.get("props", [])) as Array)
		dressing = _spread_dressing(resolve(raw.get("dressing", {})) as Dictionary)
		for point in raw.get("decor_anchors", []):
			if point is Array and (point as Array).size() >= 2:
				decor_anchors.append(Vector2(float(point[0]), float(point[1]))
					* layout_spread)

	func _build_rooms(raw_rooms: Array) -> void:
		var cream: Color = palette.get("floor", UI.FLOOR_CREAM)
		for entry in raw_rooms:
			if not (entry is Dictionary):
				continue
			var room: Dictionary = (entry as Dictionary).duplicate(true)
			var r: Array = room.get("rect", [0, 0, 1, 1]) as Array
			room["rect"] = Rect2(float(r[0]), float(r[1]), float(r[2]), float(r[3]))
			if not is_equal_approx(layout_spread, 1.0):
				var old_rect: Rect2 = room["rect"]
				room["rect"] = Rect2(
					Vector2(snappedf(old_rect.position.x * layout_spread, 0.0001),
						snappedf(old_rect.position.y * layout_spread, 0.0001)),
					Vector2(snappedf(old_rect.size.x * layout_spread, 0.0001),
						snappedf(old_rect.size.y * layout_spread, 0.0001)))
				_spread_room_fields(room)
			# Storey. Normalised here so every reader can treat it as an int and a
			# venue that never mentions levels behaves exactly as before.
			room["level"] = int(room.get("level", 0))
			# `rise_to` makes the room a STAIR: the lift ramps across its long axis
			# from `level` to `rise_to` instead of stepping at the threshold, so a
			# walker climbs it rather than teleporting a storey mid-stride.
			room["rise_to"] = int(room.get("rise_to", room["level"]))
			var dept: String = str(room.get("dept", ""))
			var accent: Color = palette.get("room." + dept, cream) if dept != "" else cream
			room["accent"] = accent
			room["floor"] = accent.lerp(cream, float(room.get("floor_mix", 1.0))) \
				if dept != "" else cream
			palette["roomfloor." + str(room.get("id", ""))] = room["floor"]
			rooms.append(room)
			by_id[str(room.get("id", ""))] = room
			if dept != "":
				by_dept[dept] = room

	func _scaled_pair(value: Variant) -> Variant:
		if value is Array and (value as Array).size() >= 2:
			return [float(value[0]) * layout_spread,
				float(value[1]) * layout_spread]
		return value

	func _scaled_pairs(value: Variant) -> Variant:
		if not (value is Array):
			return value
		var out: Array = []
		for entry in value:
			out.append(_scaled_pair(entry))
		return out

	func _spread_room_fields(room: Dictionary) -> void:
		for key in ["plaque", "door", "exit", "marketer"]:
			if room.has(key):
				room[key] = _scaled_pair(room[key])
		for key in ["stations", "visitor_spots", "linger"]:
			if room.has(key):
				room[key] = _scaled_pairs(room[key])
		for block_key in ["store", "crowd"]:
			if not (room.get(block_key) is Dictionary):
				continue
			var block: Dictionary = room[block_key]
			for key in ["home", "entry", "drop", "pile", "origin"]:
				if block.has(key):
					block[key] = _scaled_pair(block[key])
			for key in ["home_step", "col_step", "row_step", "row_shear"]:
				if block.has(key):
					block[key] = float(block[key]) * layout_spread
		var queue: Variant = room.get("queue")
		if queue is Dictionary:
			for station in queue.get("stations",[]):
				for key in ["at","porter","exit"]:
					if station.has(key):station[key] = _scaled_pair(station[key])
			for key in ["first_gx", "gx_step", "counter_gy", "porter_lane_gy",
					"slot_lead", "slot_gap", "lane_offset"]:
				if (queue as Dictionary).has(key):
					queue[key] = float(queue[key]) * layout_spread
			if (queue as Dictionary).has("counter_size"):
				# Counter furniture stays its authored size; only its placement
				# and the walking lanes around it expand.
				pass

	func _spread_specs(source: Array, walls_only: bool = false) -> Array:
		if is_equal_approx(layout_spread, 1.0):
			return source
		for value in source:
			if not (value is Dictionary):
				continue
			var spec: Dictionary = value
			for key in ["at", "anchor", "from", "to"]:
				if spec.has(key):
					spec[key] = _scaled_pair(spec[key])
			if walls_only and spec.has("len"):
				spec["len"] = float(spec["len"]) * layout_spread
			var barrier: Variant = spec.get("barrier")
			if barrier is Dictionary:
				for key in ["from", "to"]:
					if (barrier as Dictionary).has(key):
						barrier[key] = _scaled_pair(barrier[key])
		return source

	func _spread_dressing(source: Dictionary) -> Dictionary:
		if is_equal_approx(layout_spread, 1.0):
			return source
		for key in source.keys():
			var group: Variant = source[key]
			if group is Array:
				source[key] = _spread_specs(group as Array)
			elif group is Dictionary:
				_spread_specs([group])
		return source

	# --- Storeys ----------------------------------------------------------------
	##
	## A venue is a BUILDING, not a floor plan: the later ones want a mezzanine
	## over the entrance, a tower wing, a lounge you climb to. All of that is
	## carried by one int per room plus a stair room, and NONE of it reaches the
	## simulation — see Iso.LEVEL_H.

	## Every storey this venue uses, ascending. Level 0 is always present so a
	## flat venue still gets its one ground node.
	func levels() -> Array:
		var seen := {0: true}
		for entry in rooms:
			var room: Dictionary = entry as Dictionary
			seen[int(room.get("level", 0))] = true
			seen[int(room.get("rise_to", 0))] = true
		var out: Array = seen.keys()
		out.sort()
		return out

	## Screen-y offset for a grid point — which storey a thing standing there is
	## drawn on. Points outside every room are on the forecourt, at ground level.
	func lift_at(g: Vector2) -> float:
		var room: Dictionary = room_at(g)
		if room.is_empty():
			return 0.0
		var from_level: int = int(room.get("level", 0))
		var to_level: int = int(room.get("rise_to", from_level))
		if to_level == from_level:
			return Iso.level_lift(from_level)
		return lerpf(Iso.level_lift(from_level), Iso.level_lift(to_level),
			_rise_t(room, g))

	## The storey a point belongs to for DEPTH purposes. A stair belongs to its
	## higher end for its top half, so a climbing figure passes in front of the
	## upper floor's edge at the moment it steps onto it.
	func level_at(g: Vector2) -> int:
		var room: Dictionary = room_at(g)
		if room.is_empty():
			return 0
		var from_level: int = int(room.get("level", 0))
		var to_level: int = int(room.get("rise_to", from_level))
		if to_level == from_level:
			return from_level
		return from_level if _rise_t(room, g) < 0.5 else to_level

	## How far along a stair's climb a point is, 0 at the bottom, 1 at the top.
	##
	## Must agree with `stair_axis`, which is the axis _draw_stairs lays the treads
	## along. This carried its own copy of the "longer side" guess, so the moment a
	## flight named an axis the steps you SEE and the height you GAIN could
	## disagree — treads climbing north while the lift ramped east. Reading the one
	## field is what keeps them in step; the old guess survives only as the fallback
	## for a flight that names no axis.
	func _rise_t(room: Dictionary, g: Vector2) -> float:
		var r: Rect2 = room["rect"]
		var along_x: bool = r.size.x >= r.size.y
		if room.has("stair_axis"):
			along_x = str(room["stair_axis"]) == "x"
		var t: float = 0.0
		if along_x:
			t = (g.x - r.position.x) / maxf(r.size.x, 0.001)
		else:
			t = (g.y - r.position.y) / maxf(r.size.y, 0.001)
		if bool(room.get("rise_reverse", false)):
			t = 1.0 - t
		return clampf(t, 0.0, 1.0)

	## The room containing a grid point, or an empty dict. Rooms never overlap
	## (test_theme holds that), so the first hit is the only hit.
	func room_at(g: Vector2) -> Dictionary:
		for entry in rooms:
			var room: Dictionary = entry as Dictionary
			if (room["rect"] as Rect2).has_point(g):
				return room
		return {}

	# --- Lookups ---------------------------------------------------------------

	func rect(room_id: String) -> Rect2:
		return (by_id.get(room_id, {}) as Dictionary).get("rect", Rect2()) as Rect2

	## The first room playing a given role, or an empty dict. Roles are how the
	## floor asks "where does the queue go" without knowing that this venue calls
	## that room the ticket hall.
	func role(role_name: String) -> Dictionary:
		for room in rooms:
			if str((room as Dictionary).get("role", "")) == role_name:
				return room
		return {}

	func accent(dept: String) -> Color:
		return (by_dept.get(dept, {}) as Dictionary).get("accent",
			palette.get("floor", UI.FLOOR_CREAM)) as Color

	func col(key: String, def: Color = MISSING) -> Color:
		return palette.get(key, def)

	# --- Token resolution ------------------------------------------------------

	## Deep-copy a theme fragment, turning every colour token into a Color and
	## leaving everything else alone. Names and kind strings never begin with
	## '@' or '#', so there is nothing to escape.
	func resolve(value: Variant) -> Variant:
		if value is String:
			var s: String = value
			if s.begins_with("@") or s.begins_with("#"):
				return _colour(s)
			return s
		if value is Array:
			var arr: Array = []
			for item in value:
				arr.append(resolve(item))
			return arr
		if value is Dictionary:
			var out: Dictionary = {}
			for key in (value as Dictionary).keys():
				out[key] = resolve((value as Dictionary)[key])
			return out
		return value

	func _colour(token: String) -> Color:
		if not token.begins_with("@"):
			return Color(token)
		var body: String = token.substr(1)
		var mod: String = ""
		var bar: int = body.find("|")
		if bar >= 0:
			mod = body.substr(bar + 1)
			body = body.substr(0, bar)
		if not palette.has(body):
			push_warning("Theme '%s': unknown palette key '%s'" % [id, body])
			return MISSING
		var out: Color = palette[body]
		if mod.begins_with("d"):
			out = out.darkened(float(mod.substr(1)) * 0.01)
		elif mod.begins_with("l"):
			out = out.lightened(float(mod.substr(1)) * 0.01)
		return out

var time_scale: float = 1.0    # test hook: accelerate the visual sim

var _theme: VenueTheme
var _world_copy: BackBufferCopy
var _world_edges: ColorRect
var _canvas: Node2D
var _plaza := PublicPlaza.new()
var _journeys = preload("res://scenes/venue/floor/city_journeys.gd").new(self)
var _city: Node2D              # the block outside the museum, behind the ground
var _ground: Node2D            # floors + walls of storey 0, behind everything
const WallOcclusion := preload("res://scenes/venue/floor/wall_occlusion.gd")
var _occluding_walls: Array[Node2D] = []
var _crowd_traffic:=preload("res://scenes/venue/floor/crowd_traffic.gd").new()
var _cart_dispatch:=preload("res://scenes/venue/floor/cart_dispatch.gd").new()
## One extra node per storey above the ground, level -> Node2D. Each carries
## that storey's rise as its position and its own z band; see _build_upper_grounds.
var _upper_grounds: Dictionary = {}
var _stacks_layer: Node2D      # window ticket-stub stacks
var _pile_layer: Node2D        # vault pile
var _labels_layer: Node2D      # room plaques, always above the cast
const StationCallouts := preload("res://scenes/venue/floor/station_callouts.gd")
var _station_callout_rects: Array[Rect2] = []
var _station_anchor_points: Array[Vector2] = []
var _station_layout_size := Vector2.ZERO
var _station_ui: Control       # real Control buttons anchored over ticket counters
var _light_grade: ColorRect    # one-pass warm key / cool depth world treatment
var _station_chips: Array[Button] = []
var _station_upgrade: Array[Button] = []
## Late venues are deliberately larger than one phone screen.  Never solve that
## by shrinking the museum until visitors become confetti: keep a readable
## minimum camera scale and let the player drag the campus beneath the viewport.
## The floor lives on VenueTheme and is applied when the theme is built, so
## `_theme.camera_zoom` is always already legal — see VenueTheme.MIN_CAMERA_ZOOM.
const MIN_READABLE_CAMERA_ZOOM := VenueTheme.MIN_CAMERA_ZOOM
const PAN_SLOP := 10.0
## Player camera zoom, MULTIPLYING the venue's authored framing.
##
## Trying to keep an entire museum inside one phone screen was the wrong goal, and
## it is what forced late venues to choose between being cropped and being a model
## village in an empty field. The reference genre does not do this: it hands the
## player a zoom and lets them go and look at whatever they are working on.
##
## 1.0 is the authored overview, and it is the FLOOR rather than the middle of the
## range: the widest view is the one the venue was composed for, so a player can
## always get the whole silhouette back with a pinch-out and can never zoom out
## into empty sky. Everything above 1.0 is theirs to drive, and `_clamp_camera_pan`
## already grows the pan allowance as the content outgrows the viewport.
const USER_ZOOM_MIN := 1.0
const USER_ZOOM_MAX := 3.2
const WHEEL_ZOOM_STEP := 1.12
var _user_zoom: float = 1.0
## Live touches by index, so a two-finger pinch can be told from a one-finger
## drag. Godot only synthesises magnify gestures on some platforms, so the pinch
## is measured from the raw touches and the gesture event is taken as a bonus.
var _touches: Dictionary = {}
var _pinch_dist: float = 0.0
var _camera_pan := Vector2.ZERO
var _pointer_down := false
var _pointer_dragged := false
var _pointer_last := Vector2.ZERO
var _pointer_travel := 0.0
var _bags: Array = []          # live money bags: {node, value, born, pos}
var _rejected: Array = []      # capped visual walk-aways; not part of capacity
var _turned_away_total: int = 0
var _bag_drop_history: Array[Vector2] = []
var _animated_exhibits: Array = []
var _props: Array = []         # Y-sorted static furniture nodes
var _prop_g: Array[Vector2] = []   # their grid anchors, for the geometry suite
## Animated facade/vault painters. Each owns a small mutable state dictionary;
## only that prop redraws while its leaves move.
var _reactive_doors: Array = []
var _lobby_standing_geometry: Dictionary = {}
var _nav: AStarGrid2D          # half-tile walking grid; props are solid cells
var _ground_paint: Array = []      # cached dressing painters, banded by draw order
var _font: Font

# --- Layout, derived from the theme's room rects -------------------------------
var _tap_zones: Dictionary = {}          # dept id -> Rect2
var _door_g := Vector2.ZERO              # just inside the entrance facade
var _exit_door_g := Vector2.ZERO         # separate left/front lobby exit
var _exit_wall_g := Vector2.ZERO
## The far end of the entrance approach, out on the forecourt by the kerb. Every
## visitor is born here and dies here, so arrivals walk in off the street under
## the canopy instead of materialising in the doorway. City owns the constant
## because City owns the pavement it stands on.
var _street_g: Vector2 = City.STREET_G
var _marketer_g := Vector2.ZERO
var _porter_home := Vector2.ZERO
var _porter_step: float = 0.7
var _porter_layout = preload("res://scenes/venue/floor/porter_layout.gd").new()
var _porter_router = preload("res://scenes/venue/floor/porter_router.gd").new()
const PorterRouteJob = preload("res://scenes/venue/floor/porter_route_job.gd")
var _porter_planner_cursor := 0
var _porter_planning_usec := 0
var _porter_planning_budget_usec := 1500
var _vault_entry := Vector2.ZERO
var _vault_drop := Vector2.ZERO
var _pile_g := Vector2.ZERO
var _admissions := preload("res://scenes/venue/floor/admission_layout.gd").new()
var _counter_gy: float = 0.0
var _porter_lane_gy: float = 0.0
var _window_gx: Array[float] = []
var _slot_gy: Array[float] = []
var _lane_offset: float = 0.62
var _max_windows: int = 1
var _slots_per_window: int = 6
var _lobby_spots: Array[Vector2] = []
var _crowd_origin := Vector2.ZERO
var _crowd_cols: int = 5
var _crowd_col_step: float = 0.95
var _crowd_row_step: float = 0.8
var _crowd_row_shear: float = 0.5
var _browse: Dictionary = {}             # exhibit id -> Array[Vector2]
var _exhibit_keys: Array[String] = []
var _gallery_egress: Array[Vector2] = []
var _gallery_egress_cursor: int = 0

var _arrival: float = 0.28
var _serve: float = 0.34
var _transport: float = 0.25
var _choke: String = ""
var _value_text: String = "2"

var _visitors: Array = []
var _porters: Array = []
var _queues: Array = []
var _crowd: Array = []
var _stacks: Array[int] = []
var _serve_t: Array[float] = []
var _windows_active: int = 1
var _staff_nodes: Array = []
var _docent_nodes: Array = []
var _promo_nodes: Array = []
var _marketer: Character
var _spawn_t: float = 0.0
var _look_cursor: int = 0
var _porter_trips: int = 0
var _pile_height: float = 8.0
var _pile_flash: float = 0.0
var _stacks_dirty: bool = true
var _cast_key: String = ""
var _props_key: String = ""
## decor id -> grid anchor of the piece as it stands on THIS floor. Rebuilt
## with the props; read by the purchase reveal so it can light up the piece
## that just arrived, and by tests asserting an owned piece really took a spot.
var _decor_anchor_by_id: Dictionary = {}
var _decor_spec_by_id: Dictionary = {}
## Places a visitor can sit, in grid space, derived from the furniture that has
## seats. Benches and café stools were pure scenery: the cast walked past them,
## and a player who watched long enough concluded they were boards built into the
## floor. Seating that nobody uses is worse than no seating, because it advertises
## an affordance the game does not honour.
var _seats: Array[Vector2] = []
## Seat index -> true while occupied. One sitter per seat, or two visitors share a
## slat and read as one smeared figure.
var _seat_taken: Dictionary = {}
## Chance a visitor rests before leaving, once its exhibit stops are done.
##
## Tuned against MEASURED occupancy, not picked. Seats visibly occupied at any
## instant is (rest rate x rest duration), and the first pass — 0.40 chance, a 5-12s
## sit — put one person on a seat in 34 seconds of play across 37 seats. The floor
## read as furniture nobody used, which is the exact complaint this feature exists
## to answer. Real visitors sit for a while, so the duration does most of the work
## and the chance only tops it up.
const REST_CHANCE := 0.55
## How long a sitter stays, seconds. Long on purpose: see REST_CHANCE.
const REST_SECONDS := Vector2(14.0, 30.0)
## How long a visitor may spend walking to a seat before writing it off, seconds.
## Generous — a full crossing of the largest venue is well inside it — so this
## only ever fires on a seat that genuinely cannot be reached.
const REST_TRAVEL_LIMIT := 25.0
## How long a visitor may spend walking to a lobby crowd slot before writing
## it off, seconds. A parked porter cart (or a shifted crowd) can seal the
## assigned slot after assignment with no other recovery: short hops skip
## nav routing, visitors never block each other, and detours cannot rejoin a
## covered target. Same budget as seats; only genuinely unreachable slots hit
## it, and a moving cart clears the way in seconds.
const CROWD_TRAVEL_LIMIT := 25.0

class Visitor:
	var node: Character
	var pos: Vector2 = Vector2.ZERO       # grid space
	var state: String = "to_queue"        # to_queue | queue | crowd | browse | rest | rise | exit
	## Seconds spent walking to a seat without arriving. A visitor that cannot
	## reach the seat it claimed would otherwise walk at it forever, holding the
	## seat and stacking up with everyone behind it — which is exactly what a
	## mis-derived seat point caused once already.
	var rest_travel: float = 0.0
	## Index into VenueFloor._seats while resting, else -1. Held so the seat is
	## released on EVERY exit path — timing out, the venue being rethemed, the
	## visitor being culled — not only the happy one. A leaked seat is invisible
	## until the lounge silently stops being usable.
	var seat: int = -1
	var window: int = -1
	var queue_entered := false
	var waiting_slot := -1
	var departing_window := -1
	var seating_detour_retry := 0.0
	var cart_wait := 0.0
	var cart_retry := 0.0
	var cart_refuge := false
	var cart_refuge_at := Vector2.ZERO
	var cart_refuge_target := Vector2.ZERO
	var cart_refuge_blockers: Array=[]
	## Seconds spent walking to a lobby crowd slot without arriving. See
	## CROWD_TRAVEL_LIMIT: a sealed slot releases back to the lobby instead
	## of holding the visitor (and the slot) forever.
	var crowd_travel: float = 0.0
	## Bounded recovery for a failed exterior exit leg. _begin_exit parks the
	## visitor at the outdoor threshold (no teleport) and retries the plaza
	## route on a 1s backoff; after 8 failed retries the stale park reservation
	## is released and the city plan is remade once. Population stays bounded
	## via MAX_ALIVE; a persistently unroutable visitor waits rather than
	## vanishing on screen or walking through walls.
	var exit_retry: float = 0.0
	var exit_attempts: int = 0
	var target: Vector2 = Vector2.ZERO    # grid space
	## Current travel leg before the final target. Untyped to match native
	## navigation arrays; arrival, admission, browsing and exit own separate legs.
	var path: Array = []
	var outside_path: Array = []          # sidewalk -> crossing -> forecourt
	var city_plan: Dictionary = {}
	var arrival_fade := 0.0
	var uses_crosswalk: bool = false
	var spots: Array = []
	var wait: float = 0.0
	var speed: float = 2.1                # tiles/second
	var tip_due: bool = false
	var tip_mult: float = 1.0

class Porter:
	var node: Character
	var pos: Vector2 = Vector2.ZERO
	var state: String = "idle"            # idle | to_window | collect | to_vault | deposit
	var target: Vector2 = Vector2.ZERO
	var path: Array = []
	var window: int = -1
	var carried: int = 0
	var wait: float = 0.0
	var staged: bool = false
	var dock: Dictionary = {}
	var heading := Vector2.DOWN
	var route_job: RefCounted
	var route_steps: Array = []
	var route_cursor := 0
	var motion_step: Dictionary = {}
	var turn_progress := 0.0
	var replan_after_step := false
	var route_retry := 0.0
	var dispatch_standby := false
	var pedestrian_wait := 0.0

func _ready() -> void:
	name = "VenueFloor"
	clip_contents = true
	custom_minimum_size = Vector2(360, 380)
	_font = ThemeDB.fallback_font
	_load_theme(GameState.current_venue)

	_canvas = Node2D.new()
	# Y-sorting is what makes the diorama hold together: actors and props are
	# ordered by projected depth every frame, so a visitor can pass behind a
	# counter and in front of a bench without any manual layering.
	_canvas.y_sort_enabled = true
	add_child(_canvas)

	# Interactive station overlays live in floor-local screen space, not in the
	# scaled Node2D canvas. They are real 48dp Controls for reliable mobile taps;
	# _layout_station_ui projects their world anchors after every resize.
	_station_ui = Control.new()
	_station_ui.name = "StationUI"
	_station_ui.set_anchors_preset(Control.PRESET_FULL_RECT)
	_station_ui.mouse_filter = Control.MOUSE_FILTER_PASS
	_station_ui.z_index = 6
	add_child(_station_ui)
	_station_ui.clip_contents = true
	_station_ui.draw.connect(_draw_station_leaders)

	_light_grade = ColorRect.new()
	_light_grade.name = "VenueLightingGrade"
	_light_grade.set_anchors_preset(Control.PRESET_FULL_RECT)
	_light_grade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_light_grade.z_index = 5
	var grade_material := ShaderMaterial.new()
	grade_material.shader = VenueGrade
	_light_grade.material = grade_material
	add_child(_light_grade)

	# The scene uses several z bands, so smooth the final world image rather
	# than a CanvasGroup (which does not gather all those bands). Copy the full
	# viewport: a local copy rectangle can omit the floor's HUD-offset edge.
	_world_copy = BackBufferCopy.new()
	_world_copy.copy_mode = BackBufferCopy.COPY_MODE_VIEWPORT
	add_child(_world_copy)
	_world_edges = ColorRect.new()
	_world_edges.name = "WorldEdges"
	_world_edges.set_anchors_preset(Control.PRESET_FULL_RECT)
	_world_edges.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var edge_material := ShaderMaterial.new()
	edge_material.shader = preload("res://art/shaders/world_edges.gdshader")
	_world_edges.material = edge_material
	add_child(_world_edges)
	set_world_edge_smoothing(bool(ProjectSettings.get_setting(
		"rendering/quality/world_edge_smoothing", true)))

	# The city surround goes in FIRST and sits a pixel above the canvas origin,
	# so Y-sort puts the whole block behind Ground and therefore behind every
	# room, prop and actor. It takes no input, so it can never eat a tap.
	#
	# It DOES paint inside the footprint — the lawn fills the whole visible band —
	# which is harmless only because Ground covers the plan on top of it. Scenery
	# is a different matter: hedges, trees and neighbouring blocks are authored
	# against a nominal 15x17 plan, so a bigger or differently-shaped venue got a
	# hedge running through its east wing and a neighbour's roof under its floor.
	# set_footprint re-frames the whole surround around the plan this venue has.
	_city = City.new()
	_city.public_depth = PublicPlaza.PUBLIC_DEPTH
	_city.style = _theme.surround
	_city.venue_id = _theme.id
	_city.set_footprint(_theme.bounds)
	_city.set_entrance(Vector2(_door_g.x, (_theme.role("lobby")["rect"] as Rect2).end.y))
	_canvas.add_child(_city)
	_street_g = _city.street_point()
	_plaza.build(_canvas,_city,_theme,_door_g.x,_exit_door_g.x)
	_journeys.configure()

	# Ground sits at the canvas origin, which projects above every prop and
	# actor, so Y-sorting alone keeps it behind. Do NOT force it with a negative
	# z_index: z_index is global within the canvas layer, not parent-scoped, and
	# a negative value drops the whole diorama behind the app background.
	_ground = Node2D.new()
	_ground.name = "Ground"
	_canvas.add_child(_ground)
	_ground.draw.connect(_draw_ground)
	_build_upper_grounds()
	WallOcclusion.rebuild(_canvas, _theme, _occluding_walls)

	_stacks_layer = Node2D.new()
	_stacks_layer.name = "Stacks"
	# Lifted with the room they belong to, like every other placed thing: the
	# ticket stubs sit on the counters and the vault pile on the archive floor,
	# so a venue that puts either upstairs must carry them up too.
	_stacks_layer.position = _lifted(Vector2(0.0, _counter_gy))
	_stacks_layer.z_index = _level_of_role("queue") * Iso.LEVEL_Z
	_canvas.add_child(_stacks_layer)
	_stacks_layer.draw.connect(_draw_stacks)

	_pile_layer = Node2D.new()
	_pile_layer.name = "VaultPile"
	_pile_layer.position = _lifted(_pile_g)
	_pile_layer.z_index = _theme.level_at(_pile_g) * Iso.LEVEL_Z
	_canvas.add_child(_pile_layer)
	_pile_layer.draw.connect(_draw_pile)

	_labels_layer = Node2D.new()
	_labels_layer.name = "Labels"
	# Above the cast (0) and the cash floats (1) — and above the TOP storey, so a
	# room plaque is never hidden behind the floor above the room it names.
	_labels_layer.z_index = int(_theme.levels().back()) * Iso.LEVEL_Z + 2
	_canvas.add_child(_labels_layer)
	_labels_layer.draw.connect(_draw_labels)

	for i in _max_windows:
		_queues.append([])
		_stacks.append(0)
		_serve_t.append(0.0)

	_marketer = Character.new()
	# Variant 2: the promotions room seats at most two clerks, so this keeps the
	# roaming marketer from being a copy of whoever is standing at the desk.
	_marketer.set_uniform(_theme.accent("promotions"), 2, "promotions")
	_marketer.holding_sign = true
	_marketer.visible = false
	_canvas.add_child(_marketer)
	_place(_marketer, _marketer_g)

	resized.connect(_fit_canvas)
	_fit_canvas()
	_rebuild_props()
	_refresh_cast()
	_refresh_station_ui()
	if EventBus.has_signal("department_upgraded"):
		EventBus.department_upgraded.connect(
			func(v: String, _d: String, _t: String, _l: int) -> void:
				_refresh_cast()
				_refresh_station_ui()
				if v == GameState.current_venue:
					_rebuild_props())
	EventBus.item_upgraded.connect(
		func(v: String, d: String, _i: int, _l: int) -> void:
			if v == GameState.current_venue and d == "ticket":
				_refresh_station_ui())
	EventBus.item_collected.connect(
		func(v: String, d: String, _i: int, _a: Variant) -> void:
			if v == GameState.current_venue and d == "ticket":
				_refresh_station_ui())
	EventBus.cash_changed.connect(func(_cash: Variant) -> void: _refresh_station_ui())
	EventBus.manager_assigned.connect(
		func(_id: String, _dept: String) -> void:
			_cast_key = ""
			_refresh_cast())
	EventBus.manager_ranked_up.connect(
		func(_id: String, _rank: int) -> void:
			_cast_key = ""
			_refresh_cast())
	EventBus.decor_purchased.connect(func(v: String, decor_id: String) -> void:
		if v != GameState.current_venue:
			return
		_props_key = ""
		_rebuild_props()
		# After the rebuild, so the anchor map describes the floor as it now is.
		# Removal fires the same signal and simply finds no anchor.
		if _decor_anchor_by_id.has(decor_id):
			_spawn_decor_reveal(_decor_anchor_by_id[decor_id] as Vector2))
	EventBus.decor_focus_requested.connect(func(v: String, decor_id: String) -> void:
		if v != GameState.current_venue or not _decor_anchor_by_id.has(decor_id):
			return
		var g: Vector2 = _decor_anchor_by_id[decor_id]
		var screen := _canvas.position + (Iso.to_screen(g) + Vector2(0, _theme.lift_at(g))) * _canvas.scale.x
		_pan_camera(size * Vector2(0.5, 0.56) - screen)
		_spawn_decor_reveal(g, str(DataLoader.get_decor(decor_id).get("name", decor_id))))
	# Venue progression is one-way, and the next venue is a different ATTRACTION,
	# not a reskin. Re-theming here is what makes that true on screen instead of
	# only in the balance numbers.
	if EventBus.has_signal("prestige_performed"):
		EventBus.prestige_performed.connect(
			func(_from: String, to_vid: String) -> void: retheme(to_vid))

# --- Theme assembly -----------------------------------------------------------

## Resolve a venue's theme and derive every waypoint on the floor from it.
##
## Nothing below reads a hardcoded tile. The queue rides on the queue room's
## rect, the porters on the store room's, the milling crowd on the lobby's, and
## browse spots hang off the exhibit they belong to — so a venue that moves a
## wall cannot leave a counter standing in the corridor.
func _load_theme(venue_id: String) -> void:
	_theme = VenueTheme.for_venue(venue_id)
	MuseumProps.retain_kit(_theme.id)
	# Every shadowed face in the diorama tints toward this rather than toward
	# black. Taken from the venue's own shell, so a harbour museum's darks stay
	# maritime and a nightfall one's stay indigo, instead of all twelve converging
	# on the same grey. Deepened past the shell itself so a shadow still reads as a
	# shadow and not as a second coat of paint.
	Iso.shade_ambient = _theme.palette.get("shell", Color("#1E2138")).darkened(0.28)

	_tap_zones.clear()
	for dept in _theme.by_dept.keys():
		_tap_zones[dept] = (_theme.by_dept[dept] as Dictionary)["rect"]

	var queue_room: Dictionary = _theme.role("queue")
	var q: Dictionary = queue_room.get("queue", {}) as Dictionary
	var q_rect: Rect2 = queue_room.get("rect", Rect2()) as Rect2
	_max_windows = clampi(Exhibits.i(q.get("windows"), 5), 1, HARD_MAX_WINDOWS)
	_slots_per_window = maxi(Exhibits.i(q.get("slots"), 6), 1)
	_lane_offset = Exhibits.f(q.get("lane_offset"), 0.62)
	_counter_gy = q_rect.position.y + Exhibits.f(q.get("counter_gy"), 1.1)
	# A dedicated service corridor sits behind the tellers. Porters approach
	# counters from this side; visitors own the roped lanes in front.
	_porter_lane_gy = q_rect.position.y + Exhibits.f(
		q.get("porter_lane_gy"), Exhibits.f(q.get("counter_gy"), 1.1) - 1.35)
	_window_gx.clear()
	for w in _max_windows:
		_window_gx.append(q_rect.position.x + Exhibits.f(q.get("first_gx"), 2.3)
			+ float(w) * Exhibits.f(q.get("gx_step"), 2.5))
	_slot_gy.clear()
	for j in _slots_per_window:
		_slot_gy.append(_counter_gy + Exhibits.f(q.get("slot_lead"), 1.0)
			+ float(j) * Exhibits.f(q.get("slot_gap"), 0.55))

	_admissions.configure(q_rect,q,_max_windows,_slots_per_window,.55 if _theme.id=="whispering_pines" else .45,_theme.by_id)
	_slots_per_window=_admissions.slot_count
	_slot_gy.clear()
	for j in _slots_per_window:_slot_gy.append(_admissions.slot(0,j).y)

	var store_room: Dictionary = _theme.role("store")
	var s_at: Vector2 = (store_room.get("rect", Rect2()) as Rect2).position
	var s: Dictionary = store_room.get("store", {}) as Dictionary
	_porter_home = s_at + Exhibits.v2(s.get("home"), Vector2(1.4, 4.4))
	_porter_step = Exhibits.f(s.get("home_step"), 0.7)
	_vault_entry = s_at + Exhibits.v2(s.get("entry"), Vector2(0.75, 1.0))
	_vault_drop = s_at + Exhibits.v2(s.get("drop"), Vector2(3.2, 4.2))
	_pile_g = s_at + Exhibits.v2(s.get("pile"), Vector2(3.7, 4.3))

	var lobby: Dictionary = _theme.role("lobby")
	var lobby_rect: Rect2 = lobby.get("rect", Rect2()) as Rect2
	var l_at: Vector2 = lobby_rect.position
	_door_g = l_at + Exhibits.v2(lobby.get("door"), Vector2(12.9, 2.3))
	# A museum can have a separate departure hall. Legacy venues retain their
	# existing lobby exit; the wall, trigger and outdoor path share this anchor.
	var departure: Dictionary = _theme.role("departure")
	if departure.is_empty():departure=lobby
	var departure_rect: Rect2=departure.rect
	var visible_front_x: float = Iso.gx_window(departure_rect.end.y, 40.0).x + 1.50
	_exit_wall_g = departure_rect.position + Exhibits.v2(departure.get("exit"), Vector2(
		clampf(maxf(departure_rect.position.x + 1.30, visible_front_x), departure_rect.position.x + 1.2, departure_rect.end.x - 1.2) - departure_rect.position.x, departure_rect.size.y))
	_exit_door_g = _exit_wall_g + Vector2(0.0, -0.48)
	_marketer_g = l_at + Exhibits.v2(lobby.get("marketer"), Vector2(11.3, 2.2))
	_lobby_spots.clear()
	for spot in Exhibits.points(lobby.get("linger", [])):
		_lobby_spots.append(l_at + spot)
	var crowd: Dictionary = lobby.get("crowd", {}) as Dictionary
	_crowd_origin = l_at + Exhibits.v2(crowd.get("origin"), Vector2(8.2, 1.1))
	_crowd_cols = maxi(Exhibits.i(crowd.get("cols"), 5), 1)
	_crowd_col_step = Exhibits.f(crowd.get("col_step"), 0.95)
	_crowd_row_step = Exhibits.f(crowd.get("row_step"), 0.8)
	_crowd_row_shear = Exhibits.f(crowd.get("row_shear"), 0.5)

	# The first museum has a tuned two-lane bypass. Other floor plans use
	# their own navigation graph through real doors and stairs; inherited
	# first-museum waypoints can fall in walls or on a different storey.
	# Authored gallery departure: two lanes through the opening immediately
	# west of cashier one, then a west-side bypass around the velvet queues and
	# INFO furniture. Generic A* is used between these anchors, never to choose
	# a random queue opening.
	_gallery_egress.clear()
	var west_x: float = _window_gx[0] - 0.62
	var opening_y: float = q_rect.position.y - 0.32
	var bypass_y: float = lobby_rect.position.y + 0.28
	for lane in (2 if _theme.id == "whispering_pines" and not _admissions.authored else 0):
		var lane_x: float = west_x + float(lane) * 0.34
		var lobby_x: float = maxf(lane_x, Iso.gx_window(bypass_y, 26.0).x)
		if _theme.id == "whispering_pines":
			# The former exit anchors landed on the raised west terrace and
			# stepped directly down its cliff. Both lanes now descend the court
			# stair before joining the ticket-hall bypass.
			var stair: Rect2 = _theme.rect("corridor")
			var stair_x := stair.position.x + stair.size.x * (0.43 + float(lane) * 0.14)
			_gallery_egress.append(Vector2(stair_x, stair.position.y + 0.18))
			_gallery_egress.append(Vector2(stair_x, stair.end.y - 0.18))
		else:
			_gallery_egress.append(Vector2(lane_x, opening_y))
			_gallery_egress.append(Vector2(lane_x, q_rect.position.y + 0.48))
		_gallery_egress.append(Vector2(lane_x, q_rect.end.y - 0.30))
		_gallery_egress.append(Vector2(lobby_x, bypass_y))
	_gallery_egress_cursor = 0

	# Browse spots are OFFSETS from the exhibit they belong to, so an exhibit
	# that moves takes its audience with it. Six exhibits with several viewing
	# spots each: browsers used to pile onto three tiles, which read as a queue
	# for the dinosaur rather than as a gallery being looked at.
	_browse.clear()
	_exhibit_keys.clear()
	for entry in _theme.exhibits:
		var e: Dictionary = entry as Dictionary
		var key: String = str(e.get("id", ""))
		var origin: Vector2 = Exhibits.anchor(e)
		var spots: Array[Vector2] = []
		for off in Exhibits.points(e.get("views", [])):
			spots.append(origin + off)
		if key == "" or spots.is_empty():
			continue
		_browse[key] = spots
		_exhibit_keys.append(key)

	_cache_ground_paint()

## Build every dressing painter once, tagged with the band it draws in. The
## ground item redraws on a choke change and on a staffing change, and rebuilding
## a hundred Callables on each of those is avoidable garbage.
func _cache_ground_paint() -> void:
	_ground_paint.clear()
	for item in _theme.dressing.get("carpet", []):
		_band(0, "patch", item as Dictionary)
	for item in _theme.dressing.get("floor", []):
		_band(1, "rug", item as Dictionary)
	# Wall-layer exhibits (a hung mural, a porthole) draw with the wall dressing
	# rather than on a prop node: they occlude nothing, so they cost no node and
	# batch with the pictures around them.
	for entry in _theme.exhibits:
		var e: Dictionary = entry as Dictionary
		if str(e.get("layer", "floor")) == "wall":
			_band(2, "mural", e)
	for item in _theme.dressing.get("wall", []):
		_band(2, "picture", item as Dictionary)
	for item in _theme.dressing.get("ceiling", []):
		_band(3, "bunting", item as Dictionary)

func _band(index: int, fallback: String, spec: Dictionary) -> void:
	# Storey is resolved ONCE here, from the piece's own grid position, so the
	# per-frame paint is still a flat walk of a cached array.
	var at: Vector2 = Exhibits.v2(spec.get("at", spec.get("from")))
	_ground_paint.append([index, Exhibits.painter(str(spec.get("kind", fallback)), spec),
		_theme.level_at(at)])

func _paint_band(ci: CanvasItem, level: int, index: int) -> void:
	for entry in _ground_paint:
		if int(entry[0]) == index and int(entry[2]) == level:
			(entry[1] as Callable).call(ci)

# --- Public API (venue_view + tests) -----------------------------------------

## Feed the latest Economy.venue_rates dict (called every 0.5s by venue_view).
func set_rates(rates: Dictionary) -> void:
	_arrival = float(rates.get("arrival_per_s", _arrival))
	_serve = float(rates.get("serve_per_s", _serve))
	_transport = float(rates.get("transport_per_s", _transport))
	var new_choke: String = str(rates.get("choke_id", ""))
	var vpv: Variant = rates.get("value_per_visitor")
	if vpv is BigNumber:
		_value_text = vpv.to_notation()
	_update_pile_height()
	if new_choke != _choke:
		_choke = new_choke
		_marketer.visible = _choke == "promotions"
		_ground.queue_redraw()
		_stacks_dirty = true
	_refresh_cast()

## Rebuild the whole diorama as a different venue.
##
## Everyone on the floor is sent home rather than re-targeted: their waypoints
## belong to the old floor plan, and a visitor holding a browse spot from the
## previous building would walk through the new one's walls to reach it.
func retheme(venue_id: String) -> void:
	if venue_id == "" or venue_id == _theme.id:
		return
	# A new building is framed as its author composed it: the player's zoom and pan
	# belonged to the last one, and inheriting them drops you into a corner of a
	# museum you have never seen.
	_user_zoom = 1.0
	_camera_pan = Vector2.ZERO
	_touches.clear()
	_pinch_dist = 0.0
	for v in _visitors:
		v.node.queue_free()
	_journeys.clear()
	_visitors.clear()
	_seat_taken.clear()
	_unreachable_targets.clear()
	_crowd.clear()
	for c in _staff_nodes + _docent_nodes + _promo_nodes:
		(c as Node).queue_free()
	_staff_nodes.clear()
	_docent_nodes.clear()
	_promo_nodes.clear()
	for p in _porters:
		p.node.queue_free()
	_porters.clear()

	# Cash labels and upgrade callbacks belong to the old station bank. Retire
	# them before camera fitting can lay out a smaller bank in the next museum.
	for chip in _station_chips + _station_upgrade:
		_station_ui.remove_child(chip)
		chip.queue_free()
	_station_chips.clear()
	_station_upgrade.clear()
	_load_theme(venue_id)
	_city.style = _theme.surround
	_city.venue_id = _theme.id
	# The new venue's plan is almost certainly a different shape, so the surround
	# has to be re-framed before it redraws or it keeps the old venue's setting.
	_city.set_footprint(_theme.bounds)
	_city.set_entrance(Vector2(_door_g.x, (_theme.role("lobby")["rect"] as Rect2).end.y))
	_street_g = _city.street_point()
	_plaza.build(_canvas,_city,_theme,_door_g.x,_exit_door_g.x)
	_journeys.configure()
	_city.queue_redraw()
	_fit_canvas()
	# Storeys are per-venue: a flat venue following a two-storey one has to lose
	# the upper node, or its rooms keep drawing into a floor that no longer exists.
	_clear_upper_grounds()
	_build_upper_grounds()
	WallOcclusion.rebuild(_canvas, _theme, _occluding_walls)
	_labels_layer.z_index = int(_theme.levels().back()) * Iso.LEVEL_Z + 2

	_queues.clear()
	_stacks.clear()
	_serve_t.clear()
	for i in _max_windows:
		_queues.append([])
		_stacks.append(0)
		_serve_t.append(0.0)
	_windows_active = 1
	_stacks_layer.position = _lifted(Vector2(0.0, _counter_gy))
	_stacks_layer.z_index = _level_of_role("queue") * Iso.LEVEL_Z
	_pile_layer.position = _lifted(_pile_g)
	_pile_layer.z_index = _theme.level_at(_pile_g) * Iso.LEVEL_Z
	_marketer.set_uniform(_theme.accent("promotions"), 2, "promotions")
	_place(_marketer, _marketer_g)

	_cast_key = ""
	_props_key = ""
	_rebuild_props()
	_refresh_cast()
	_refresh_station_ui()
	_ground.queue_redraw()
	_labels_layer.queue_redraw()
	_stacks_dirty = true

func get_alive_visitor_count() -> int:
	return _visitors.size()

func get_queue_occupancy() -> int:
	# Waiting includes the lobby overflow, which is physically outside the ropes.
	var n: int = _crowd.size()
	for q in _queues:
		n += q.size()
	return n

## Opening amount by door id. This is a diagnostic/test surface for proving the
## live simulation drives the procedural painter, not a player-facing API.
func door_activity() -> Dictionary:
	var out: Dictionary = {}
	for entry in _reactive_doors:
		out[str(entry.get("id", "door"))] = float(
			(entry.get("state", {}) as Dictionary).get("open", 0.0))
	return out

func get_porter_trips() -> int:
	return _porter_trips

func get_choke() -> String:
	return _choke

## The venue this floor is themed as, and the City style that theme asked for.
## Tests assert on these rather than on the drawing.
func theme_id() -> String:
	return _theme.id

func theme_surround() -> String:
	return _theme.surround

func room_ids() -> PackedStringArray:
	var out := PackedStringArray()
	for room in _theme.rooms:
		out.append(str((room as Dictionary).get("id", "")))
	return out

func room_rect(room_id: String) -> Rect2:
	return _theme.rect(room_id)

## Grid point in the actual fitted Control, including the venue's camera zoom.
## Geometry checks and external overlays must use this rather than Iso directly:
## later museums can have a larger authored footprint than the base canvas.
func grid_to_view(g: Vector2) -> Vector2:
	return _canvas.position + Iso.to_screen(g) * _canvas.scale.x

## Room-name plaques, as the grid points they are drawn at, keyed by department.
func plaque_points() -> Dictionary:
	var out: Dictionary = {}
	for room in _theme.rooms:
		var r: Dictionary = room as Dictionary
		if not r.has("plaque"):
			continue
		out[str(r.get("dept", r.get("id", "")))] = \
			(r["rect"] as Rect2).position + Exhibits.v2(r["plaque"])
	return out

## Exhibit id -> the grid points visitors stand on to look at it.
func browse_spots() -> Dictionary:
	return _browse.duplicate(true)

## Where the queue geometry actually landed, so a test can assert it sits inside
## the room rect it was derived from instead of trusting the arithmetic.
func queue_geometry() -> Dictionary:
	return {
		"counter_gy": _counter_gy, "window_gx": _window_gx.duplicate(),
		"slot_gy": _slot_gy.duplicate(), "windows": _max_windows,
		"slots": _slots_per_window, "porter_lane_gy": _porter_lane_gy,
		"stations":_admissions.stations.duplicate(true), "authored":_admissions.authored,
	}

func queue_routes() -> Dictionary:
	var mouths: Array[Vector2] = []
	for w in _max_windows:
		mouths.append(_queue_mouth(w))
	return {
		"mouths": mouths,
		"aisle_bottom": _queue_aisle(true),
		"aisle_top": _queue_aisle(false),
	}

## Population by FSM state. The density pass is tuned against this: a floor whose
## whole crowd is parked in one room reads worse than a thinner one spread over
## four, and that is invisible from any single screenshot.
func state_census() -> Dictionary:
	var out := {"to_queue": 0, "queue": 0, "crowd": 0, "browse": 0, "rest": 0,
		"linger": 0, "exit": 0}
	for v in _visitors:
		out[v.state] = int(out.get(v.state, 0)) + 1
	return out

## Look keys of everyone currently on the floor — visitors then staff. The cast
## suite censuses this: a crowd that repeats a look is the defect, and the only
## place it is observable is a populated floor.
func cast_look_keys(include_staff: bool = false) -> PackedStringArray:
	var keys := PackedStringArray()
	for v in _visitors:
		keys.append((v.node as Character).look_key())
	if include_staff:
		for c in _staff_nodes + _docent_nodes + _promo_nodes:
			keys.append((c as Character).look_key())
		for p in _porters:
			keys.append((p.node as Character).look_key())
	return keys

## Grid anchors of every static prop on the floor. The geometry suite walks
## these: a prop whose anchor projects outside Iso.VIEW is simply not there, and
## that failure is silent — the archive lost its vault door, its money pile and
## half its shelving that way and nobody noticed for two passes.
func prop_anchors() -> Array[Vector2]:
	return _prop_g.duplicate()

## Visual density includes passable facades and rope-line drawing anchors.
## Collision checks deliberately use prop_anchors() instead.
func visible_prop_anchors() -> Array[Vector2]:
	var out: Array[Vector2] = []
	for prop in _props:out.append(prop.get_meta("floor_anchor", Vector2.ZERO))
	return out

## Every grid point a character is ever asked to stand on. Same reason: a
## waypoint outside the canvas walks somebody off screen, and one inside a prop
## footprint stands them in the furniture.
func standing_spots() -> Array[Vector2]:
	var out: Array[Vector2] = [
		_door_g, _exit_door_g, _street_g, _marketer_g, _porter_home, _vault_drop, _pile_g]
	for w in _max_windows:
		out.append(_admissions.point(w,Vector2(0,-.7)))
		out.append(_admissions.point(w,Vector2(.8,.5)))
		for j in _slots_per_window:
			out.append(_slot_pos(w, j))
	for i in MAX_CROWD:
		out.append(_crowd_slot(i))
	for spot in _lobby_spots:
		out.append(spot)
	for key in _browse.keys():
		for spot in _browse[key]:
			out.append(spot)
	for spot in _gallery_egress:
		out.append(spot)
	return out

func gallery_egress_routes() -> Array:
	return [
		_gallery_egress.slice(0, 4),
		_gallery_egress.slice(4, 8),
	]

## Dept id for a canvas-space position, or "" if no room hit.
func tap_zone_at(canvas_pos: Vector2) -> String:
	var g: Vector2 = Iso.to_grid(canvas_pos)
	# A booth can share a collection pavilion. Its actual working footprint
	# opens Admissions; the rest of the pavilion retains its gallery action.
	if _admissions.authored:
		var q: Dictionary = _theme.role("queue").get("queue",{})
		var size := Exhibits.v2(q.get("counter_size"),Vector2(1.7,.6))
		for w in mini(_windows_active,_admissions.stations.size()):
			var station: Dictionary = _admissions.stations[w]
			var delta := g-(station.center as Vector2)
			if absf(delta.dot(station.right))<=size.x*.5+.15 and absf(delta.dot(station.front))<=size.y*.5+.3:
				return "ticket"
	for dept_id in _tap_zones.keys():
		if (_tap_zones[dept_id] as Rect2).has_point(g):
			return dept_id
	var room: Dictionary = _theme.room_at(g)
	var merged := str(room.get("merge_into",""))
	if _tap_zones.has(merged):return merged
	return ""

## Canvas-space centre of a department's room. Tests aim with this instead of
## hardcoding pixel coordinates, so the layout stays free to move.
func room_center(dept_id: String) -> Vector2:
	var r: Rect2 = _tap_zones.get(dept_id, _theme.role("queue").get("rect", Rect2()))
	return Iso.to_screen(r.position + r.size * 0.5)

## A canvas point inside the diorama but outside every room (the lobby floor),
## for asserting that dead taps do nothing.
func dead_zone_point() -> Vector2:
	var r: Rect2 = _theme.role("lobby").get("rect", Rect2()) as Rect2
	return Iso.to_screen(r.position + r.size * 0.5)

## Canvas point -> grid coords. Public because anything that has to place or hit
## something from a screen position needs it, not just the floor itself.
func canvas_to_grid(canvas_pos: Vector2) -> Vector2:
	return Iso.to_grid(canvas_pos)

## Live tip bags on the floor.
func bag_count() -> int:
	return _bags.size()

func rejected_count() -> int:
	return _rejected.size()

func turned_away_count() -> int:
	return _turned_away_total

func bag_drop_history() -> Array[Vector2]:
	return _bag_drop_history.duplicate()

func entrance_point() -> Vector2:
	return _door_g

func exit_point() -> Vector2:
	return _exit_door_g

## Same code path as a real click (tests call this directly).
func simulate_tap(canvas_pos: Vector2) -> void:
	var dept: String = tap_zone_at(canvas_pos)
	if dept != "":
		dept_selected.emit(dept)

## Canvas-space anchor of a visible ticket station. Kept public for input tests
## and quest routing; callers never need to know the queue-room formula.
func station_center(index: int) -> Vector2:
	if index < 0 or index >= _windows_active:
		return Vector2.ZERO
	return _lifted(_admissions.point(index))

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_pointer_down = true
			_pointer_dragged = false
			_pointer_travel = 0.0
			_pointer_last = event.position
			accept_event()
		else:
			if _pointer_down and not _pointer_dragged:
				var p: Vector2 = _to_canvas(event.position)
				if not _try_tap_bag(p):
					simulate_tap(p)
			_pointer_down = false
			accept_event()
	elif event is InputEventMouseMotion and _pointer_down:
		var delta: Vector2 = event.position - _pointer_last
		_pointer_last = event.position
		_pointer_travel += delta.length()
		if _pointer_dragged or _pointer_travel >= PAN_SLOP:
			_pointer_dragged = true
			_pan_camera(delta)
			accept_event()
	elif event is InputEventMouseButton and event.pressed and (
			event.button_index == MOUSE_BUTTON_WHEEL_UP
			or event.button_index == MOUSE_BUTTON_WHEEL_DOWN):
		_zoom_at(event.position, WHEEL_ZOOM_STEP
			if event.button_index == MOUSE_BUTTON_WHEEL_UP else 1.0 / WHEEL_ZOOM_STEP)
		accept_event()
	elif event is InputEventMagnifyGesture:
		_zoom_at(event.position, event.factor)
		accept_event()
	elif event is InputEventScreenTouch:
		if event.pressed:
			_touches[event.index] = event.position
			if _touches.size() >= 2:
				# Second finger down: this is a pinch, not a tap or a drag.
				_pointer_dragged = true
				_pinch_dist = _touch_spread()
			else:
				_pointer_down = true
				_pointer_dragged = false
				_pointer_travel = 0.0
				_pointer_last = event.position
		else:
			_touches.erase(event.index)
			if _touches.size() < 2:
				_pinch_dist = 0.0
			if _pointer_down and not _pointer_dragged:
				var p: Vector2 = _to_canvas(event.position)
				if not _try_tap_bag(p):
					simulate_tap(p)
			_pointer_down = false
		accept_event()
	elif event is InputEventScreenDrag:
		_touches[event.index] = event.position
		if _touches.size() >= 2:
			# Pinch: scale by how much the fingers' separation changed, about the
			# midpoint between them, so the thing being examined stays put.
			var spread: float = _touch_spread()
			if _pinch_dist > 1.0 and spread > 1.0:
				_zoom_at(_touch_centre(), spread / _pinch_dist)
			_pinch_dist = spread
			_pointer_dragged = true
		else:
			_pointer_dragged = true
			_pointer_last = event.position
			_pan_camera(event.relative)
		accept_event()

## Separation between the first two live touches, in control pixels.
func _touch_spread() -> float:
	var pts: Array = _touches.values()
	if pts.size() < 2:
		return 0.0
	return (pts[0] as Vector2).distance_to(pts[1] as Vector2)

func _touch_centre() -> Vector2:
	var pts: Array = _touches.values()
	if pts.size() < 2:
		return size * 0.5
	return ((pts[0] as Vector2) + (pts[1] as Vector2)) * 0.5

## Zoom about a point, keeping whatever is under it under it.
##
## Without the focal correction a pinch drags the museum out from under the
## player's fingers: the canvas is centred on the viewport, so scaling alone moves
## every point away from the middle. Convert the focus to canvas space BEFORE the
## scale change, re-project it after, and pan by the difference.
func _zoom_at(focus: Vector2, factor: float) -> void:
	if _canvas == null or factor <= 0.0:
		return
	var before: float = _user_zoom
	_user_zoom = clampf(_user_zoom * factor, USER_ZOOM_MIN, USER_ZOOM_MAX)
	if is_equal_approx(_user_zoom, before):
		return
	var anchor: Vector2 = _to_canvas(focus)
	_fit_canvas()
	_pan_camera(focus - (anchor * _canvas.scale.x + _canvas.position))

func _to_canvas(p: Vector2) -> Vector2:
	var s: float = maxf(_canvas.scale.x, 0.0001)
	return (p - _canvas.position) / s

## Graphics quality hook; disabling removes both the shader and its copy cost.
## Controls are independent siblings and retain their original touch geometry.
func set_world_edge_smoothing(enabled: bool) -> void:
	if _world_edges != null:
		_world_edges.visible = enabled
		_world_copy.visible = enabled

func _fit_canvas() -> void:
	var s: float = minf(size.x / FLOOR.x, size.y / FLOOR.y)
	if s <= 0.0:
		s = 1.0
	if _theme != null:
		s *= _theme.camera_zoom
	# The player's own zoom rides on top of the authored framing.
	s *= _user_zoom
	_canvas.scale = Vector2(s, s)
	_clamp_camera_pan(s)
	_canvas.position = (size - FLOOR * s) * 0.5 + _theme.camera_offset * s + _camera_pan
	# Tell the surround where the picture actually ends. The canvas is letterboxed
	# inside this Control, so the visible area in canvas coordinates is wider and
	# taller than FLOOR — and the city has to reach those edges or the shell shows
	# through above and below it.
	if _city != null:
		_city.set_visible_band(Rect2(-_canvas.position / s, size / s))
	_layout_station_ui()

func _pan_camera(delta: Vector2) -> void:
	if _canvas == null:
		return
	_camera_pan += delta
	_clamp_camera_pan(_canvas.scale.x)
	_canvas.position = (size - FLOOR * _canvas.scale.x) * 0.5 \
		+ _theme.camera_offset * _canvas.scale.x + _camera_pan
	if _city != null:
		_city.set_visible_band(Rect2(
			-_canvas.position / _canvas.scale.x, size / _canvas.scale.x))
	_layout_station_ui()

func _clamp_camera_pan(s: float) -> void:
	# Actual room extents can exceed the nominal canvas even at default zoom.
	# Include elevated walls so panning can expose every wing and upper floor.
	if _theme == null or _theme.rooms.is_empty():
		_camera_pan = Vector2.ZERO
		return
	var bounds := Rect2()
	var first := true
	for entry in _theme.rooms:
		var room: Dictionary = entry
		if not bool(room.get("visible", true)):
			continue
		var rect: Rect2 = room["rect"]
		var top := maxi(int(room.get("level", 0)), int(room.get("rise_to", 0)))
		for corner in [rect.position, Vector2(rect.end.x, rect.position.y), rect.end, Vector2(rect.position.x, rect.end.y)]:
			var point: Vector2 = Iso.to_screen(corner)
			if first:
				bounds = Rect2(point, Vector2.ZERO)
				first = false
			bounds = bounds.expand(point)
			bounds = bounds.expand(point + Vector2(0, Iso.level_lift(top) - Iso.WALL_H))
	# The public courts are part of the playable view: panning must be able to
	# reveal an exterior seating pocket even when the museum fills the overview.
	if _city != null:
		var exterior: Rect2 = _city.apron_bounds()
		for corner in [exterior.position,Vector2(exterior.end.x,exterior.position.y),exterior.end,Vector2(exterior.position.x,exterior.end.y)]:
			bounds = bounds.expand(Iso.to_screen(corner)+Vector2(0,City.DROP))
	var origin := (size - FLOOR * s) * 0.5 + _theme.camera_offset * s
	var low := origin + bounds.position * s
	var high := origin + bounds.end * s
	var margin := Vector2(32, 48)
	var minimum := Vector2(minf(0, size.x - margin.x - high.x), minf(0, size.y - margin.y - high.y))
	var maximum := Vector2(maxf(0, margin.x - low.x), maxf(0, margin.y - low.y))
	_camera_pan.x = clampf(_camera_pan.x, minimum.x, maximum.x)
	_camera_pan.y = clampf(_camera_pan.y, minimum.y, maximum.y)

# --- Per-station interaction -------------------------------------------------

func _refresh_station_ui() -> void:
	if _station_ui == null or not GameState.ready_flag:
		return
	var count: int = mini(_windows_active,
		GameState.dept_items(GameState.current_venue, "ticket").size())
	while _station_chips.size() < count:
		var index: int = _station_chips.size()
		var chip := Button.new()
		chip.name = "StationCash%d" % index
		chip.custom_minimum_size = Vector2(48, 48)
		chip.size = Vector2(48,48)
		chip.clip_text = true
		chip.focus_mode = Control.FOCUS_NONE
		chip.add_theme_font_size_override("font_size", 10)
		_style_station_button(chip,false)
		chip.pressed.connect(_on_station_cash.bind(index))
		chip.mouse_entered.connect(func() -> void:_station_ui.queue_redraw())
		chip.mouse_exited.connect(func() -> void:_station_ui.queue_redraw())
		chip.button_down.connect(func() -> void:_station_ui.queue_redraw())
		chip.button_up.connect(func() -> void:_station_ui.queue_redraw())
		_station_ui.add_child(chip)
		_station_chips.append(chip)

		var up := Button.new()
		up.name = "StationUpgrade%d" % index
		up.custom_minimum_size = Vector2(48, 48)
		up.size = Vector2(48,48)
		up.focus_mode = Control.FOCUS_NONE
		up.add_theme_font_size_override("font_size", 20)
		_style_station_button(up,true)
		up.tooltip_text = tr("Upgrade station %d") % (index + 1)
		up.pressed.connect(_on_station_upgrade.bind(index))
		up.mouse_entered.connect(func() -> void:_station_ui.queue_redraw())
		up.mouse_exited.connect(func() -> void:_station_ui.queue_redraw())
		up.button_down.connect(func() -> void:_station_ui.queue_redraw())
		up.button_up.connect(func() -> void:_station_ui.queue_redraw())
		_station_ui.add_child(up)
		_station_upgrade.append(up)
	while _station_chips.size() > count:
		_station_chips.pop_back().queue_free()
		_station_upgrade.pop_back().queue_free()

	for i in count:
		var pending: BigNumber = Economy.item_pending(GameState.current_venue, "ticket", i)
		var cooldown: int = Economy.item_collect_remaining(GameState.current_venue, "ticket", i)
		var level: int = GameState.item_level(GameState.current_venue, "ticket", i)
		var chip: Button = _station_chips[i]
		var has_caption:=cooldown>0 or not pending.is_zero()
		var caption_changed:=not chip.has_meta("caption") or bool(chip.get_meta("caption"))!=has_caption
		chip.add_theme_font_size_override("font_size",10 if has_caption else 12)
		chip.set_meta("cash_ready",cooldown==0 and not pending.is_zero())
		chip.set_meta("cooldown",cooldown>0)
		chip.set_meta("caption",has_caption)
		if caption_changed:
			for state in ["normal","hover","pressed","disabled","focus"]:
				var style:=StyleBoxEmpty.new()
				style.content_margin_top=24.0 if has_caption else 0.0
				chip.add_theme_stylebox_override(state,style)
		if cooldown > 0:
			chip.text = "%d:%02d" % [cooldown / 60, cooldown % 60]
			chip.modulate = Color(1, 1, 1, 0.62)
		else:
			chip.text = ("$" + pending.to_notation()) if not pending.is_zero() else str(i+1)
			chip.modulate = Color.WHITE
		chip.tooltip_text = tr("Station %d · Level %d\n%s") % [i+1,level,("Collect $"+pending.to_notation()) if not pending.is_zero() else "Open station upgrades"]
		if cooldown>0:chip.tooltip_text=tr("Station %d · Ready in %d:%02d")%[i+1,cooldown/60,cooldown%60]
		var up: Button = _station_upgrade[i]
		var maxed: bool = level >= Economy.item_max_level()
		up.text = ""
		up.size = Vector2(48,48)
		up.disabled = maxed
		up.visible = not maxed
		up.modulate = Color(1, 1, 1, 0.55) if maxed else Color.WHITE
	_layout_station_ui()

func _style_station_button(button: Button, upgrade: bool) -> void:
	button.add_theme_color_override("font_color",Color("#BDE2C9") if upgrade else Color("#F1EEE4"))
	button.add_theme_color_override("font_hover_color",Color.WHITE)
	button.add_theme_color_override("font_pressed_color",Color.WHITE)
	button.add_theme_color_override("font_outline_color",Color("#203831"))
	button.add_theme_constant_override("outline_size",0 if upgrade else 2)
	for state in ["normal","hover","pressed","disabled","focus"]:
		button.add_theme_stylebox_override(state,StyleBoxEmpty.new())

func _layout_station_ui() -> void:
	if _station_ui == null or _canvas == null:return
	var anchors: Array[Vector2]=[]
	var s: float=maxf(_canvas.scale.x,.0001)
	for i in _station_chips.size():anchors.append(_canvas.position+station_center(i)*s)
	if anchors!=_station_anchor_points or size!=_station_layout_size:
		_station_anchor_points=anchors
		_station_layout_size=size
		var bounds:=Rect2(Vector2(12,12),size-Vector2(24,24))
		var exclusions: Array[Rect2]=[Rect2(Vector2(size.x-90,0),Vector2(90,180))]
		_station_callout_rects=StationCallouts.arrange(anchors,bounds,exclusions)
	_station_ui.z_index=int(_theme.levels().back())*Iso.LEVEL_Z+4
	if _world_edges != null:
		_world_edges.z_index = _station_ui.z_index - 1
		_world_copy.z_index = _world_edges.z_index
	for i in _station_chips.size():
		var rect: Rect2=_station_callout_rects[i]
		var shown:=rect.has_area()
		_station_chips[i].visible=shown
		_station_upgrade[i].visible=shown and not _station_upgrade[i].disabled
		_station_chips[i].size=Vector2(48,48)
		_station_chips[i].position=rect.position
		_station_upgrade[i].position=rect.position+Vector2(52,0)
	_station_ui.queue_redraw()

func _draw_station_leaders() -> void:
	for i in mini(_station_anchor_points.size(),_station_callout_rects.size()):
		var rect: Rect2=_station_callout_rects[i]
		if not rect.has_area():continue
		var anchor: Vector2=_station_anchor_points[i]
		var chip: Button=_station_chips[i]
		var has_caption: bool=chip.get_meta("caption",false)
		var center:=rect.position+Vector2(24,16 if has_caption else 24)
		var edge:=StationCallouts.nearest_edge(Rect2(rect.position,Vector2(100,48)),anchor)
		if anchor.distance_to(edge)>32:
			_station_ui.draw_line(anchor,edge,Color("#43534f85"),1.0,true)
			_station_ui.draw_circle(anchor,2.0,Color("#43534fa0"))
		var ready: bool=chip.get_meta("cash_ready",false)
		var cooldown: bool=chip.get_meta("cooldown",false)
		var radius:=13.0 if has_caption else 14.0
		if chip.is_pressed():radius-=1.0
		_station_ui.draw_circle(center+Vector2(0,2),radius+1,Color("#1e2b3038"))
		_station_ui.draw_circle(center,radius+1,Color("#f5d983") if ready else Color("#d8cba5"))
		_station_ui.draw_circle(center,radius-1,Color("#c39332") if ready else Color("#324842"))
		if chip.is_hovered():_station_ui.draw_arc(center,radius+3,0,TAU,32,Color("#fff1c2"),1.5,true)
		if ready:
			_station_ui.draw_string(_font,center+Vector2(-4,5),"$",HORIZONTAL_ALIGNMENT_LEFT,-1,14,Color("#fff1bc"))
		elif cooldown:
			_station_ui.draw_arc(center,7,0,TAU,24,Color("#d8cba5"),1.2,true)
			_station_ui.draw_polyline(PackedVector2Array([center+Vector2(0,-4),center,center+Vector2(3,1)]),Color("#d8cba5"),1.4,true)
		if _station_upgrade[i].visible:
			var up_center:=rect.position+Vector2(76,24)
			_station_ui.draw_circle(up_center+Vector2(0,2),14,Color("#1e2b3038"))
			_station_ui.draw_circle(up_center,13,Color("#254e46"))
			_station_ui.draw_arc(up_center,13,0,TAU,32,Color("#a4cfba"),1,true)
			if _station_upgrade[i].is_hovered():_station_ui.draw_arc(up_center,16,0,TAU,32,Color("#d3f6da"),1.5,true)
			var ink:=Color("#c4eed5")
			_station_ui.draw_line(up_center+Vector2(0,5),up_center+Vector2(0,-5),ink,2,true)
			_station_ui.draw_polyline(PackedVector2Array([up_center+Vector2(-4,-1),up_center+Vector2(0,-5),up_center+Vector2(4,-1)]),ink,2,true)

func _on_station_cash(index: int) -> void:
	var cooldown: int = Economy.item_collect_remaining(GameState.current_venue, "ticket", index)
	if cooldown > 0:
		EventBus.toast_requested.emit("Cashier ready in %d:%02d" % [cooldown / 60, cooldown % 60])
		return
	var amount: BigNumber = Economy.collect_item(GameState.current_venue, "ticket", index)
	if amount.is_zero():
		item_selected.emit("ticket", index)
		return
	_spawn_float("+" + amount.to_notation(),
		_admissions.point(index,Vector2(0,-.4)))
	_refresh_station_ui()

func _on_station_upgrade(index: int) -> void:
	item_selected.emit("ticket", index)

# --- Placement ----------------------------------------------------------------

## Project a grid point onto its storey. The one place a static layer gets the
## same lift the moving cast gets from _place().
func _lifted(g: Vector2) -> Vector2:
	return Iso.to_screen(g) + Vector2(0.0, _theme.lift_at(g))

## Move a node to a grid position: project, lift to its storey, then scale for
## depth. Every moving figure in the venue goes through here, which is why a
## storey costs nothing in the FSM — a walker's grid position is unchanged and
## only what is DRAWN moves up.
func _place(n: Node2D, g: Vector2) -> void:
	n.position = Iso.to_screen(g) + Vector2(0.0, _theme.lift_at(g) + _city.surface_drop(g))
	# Depth band, so a figure upstairs is never drawn behind the floor it is
	# standing on. Recomputed per move because a walker on a stair changes storey
	# mid-stride.
	var band: int = _theme.level_at(g) * Iso.LEVEL_Z
	if n.z_index != band:
		n.z_index = band
	# Normalise depth against THIS venue's footprint, not a global grid, or a
	# tall narrow venue would compress its whole depth range into a fraction of
	# the scale curve and its cast would barely change size front to back.
	var span: float = _theme.bounds.size.x + _theme.bounds.size.y
	if span <= 0.0:
		span = Iso.GRID.x + Iso.GRID.y
	var t: float = clampf((g.x + g.y - _theme.bounds.position.x - _theme.bounds.position.y) / span, 0.0, 1.0)
	n.scale = Vector2.ONE * lerpf(DEPTH_SCALE_BACK, DEPTH_SCALE_FRONT, t)
	if n is Character:
		# The world is orthographic: shrinking only people at the back changes
		# their stride and leg/seat proportions while furniture stays full size.
		n.scale = Vector2.ONE * (n as Character).age_scale()

# --- Cast (staffing visuals follow real dept levels) --------------------------

func _staff_level(dept_id: String) -> int:
	if not GameState.ready_flag:
		return 1
	return GameState.dept_level(GameState.current_venue, dept_id, "staff")

## The grid points a room's staff stand on. Theme coordinates are room-relative,
## so a room that moves takes its staff with it.
func _stations(room_id: String) -> Array[Vector2]:
	var room: Dictionary = _theme.by_id.get(room_id, {}) as Dictionary
	var at: Vector2 = (room.get("rect", Rect2()) as Rect2).position
	var out: Array[Vector2] = []
	for p in Exhibits.points(room.get("stations", [])):
		out.append(at + p)
	return out

func _refresh_cast() -> void:
	if not GameState.ready_flag:
		return
	var manager_key: String = ""
	for dept in ["ticket", "gallery", "promotions", "archive"]:
		for mid in ManagerSystem.assigned_ids(dept):
			manager_key += "/%s:%d" % [mid, ManagerSystem.rank(mid)]
	var key: String = "%d/%d/%d/%d%s" % [
		_staff_level("ticket"), _staff_level("gallery"),
		_staff_level("promotions"), _staff_level("archive"), manager_key]
	if key == _cast_key:
		return
	_cast_key = key

	_windows_active = clampi(_staff_level("ticket"), 1, _max_windows)
	while _staff_nodes.size() < _windows_active:
		var i: int = _staff_nodes.size()
		var c: Character = Character.new()
		c.set_uniform(_theme.accent("ticket"), i, "ticket")
		c.set_motion_vector(_admissions.stations[i].front,0.0)
		_canvas.add_child(c)
		_place(c, _admissions.point(i,Vector2(0,-.7)))
		_staff_nodes.append(c)
	while _staff_nodes.size() > _windows_active:
		_staff_nodes.pop_back().queue_free()

	var gallery_posts: Array[Vector2] = _stations("gallery")
	var docents: int = clampi(_staff_level("gallery"), 0, gallery_posts.size())
	while _docent_nodes.size() < docents:
		var c: Character = Character.new()
		c.set_uniform(_theme.accent("gallery").darkened(0.2), _docent_nodes.size(), "docent")
		_canvas.add_child(c)
		_place(c, gallery_posts[_docent_nodes.size()])
		_docent_nodes.append(c)
	while _docent_nodes.size() > docents:
		_docent_nodes.pop_back().queue_free()

	var promo_posts: Array[Vector2] = _stations("promotions")
	var clerks: int = clampi(_staff_level("promotions"), 1, promo_posts.size())
	while _promo_nodes.size() < clerks:
		var c: Character = Character.new()
		c.set_uniform(_theme.accent("promotions"), _promo_nodes.size(), "promotions")
		_canvas.add_child(c)
		_place(c, promo_posts[_promo_nodes.size()])
		_promo_nodes.append(c)
	while _promo_nodes.size() > clerks:
		_promo_nodes.pop_back().queue_free()

	var porters: int = clampi(_staff_level("archive"), 1, 3)
	while _porters.size() < porters:
		var p := Porter.new()
		var c: Character = Character.new()
		c.set_uniform(_theme.accent("archive"), _porters.size(), "porter")
		c.with_cart = true
		_canvas.add_child(c)
		p.pos = _porter_home + Vector2(float(_porters.size()) * _porter_step, 0.0)
		p.target = p.pos
		p.node = c
		_place(c, p.pos)
		_porters.append(p)
	while _porters.size() > porters:
		var dead: Porter = _porters.pop_back()
		_cart_dispatch.remove(dead,true)
		dead.node.queue_free()

	_apply_manager_aura("ticket", _staff_nodes)
	_apply_manager_aura("gallery", _docent_nodes)
	_apply_manager_aura("promotions", _promo_nodes)
	var porter_nodes: Array = []
	for porter in _porters:
		porter_nodes.append(porter.node)
	_apply_manager_aura("archive", porter_nodes)
	_rebuild_props()
	# Initial cast creation can reuse a current prop/nav cache. A new courier
	# must still receive its bay before the first simulation tick.
	for p in _porters:
		if not p.staged and p.state!="awaiting_entry" and _nav!=null:
			_rebuild_porter_staging();break
	_ground.queue_redraw()

func _apply_manager_aura(dept_id: String, staff: Array) -> void:
	var assigned: Array[String] = ManagerSystem.assigned_ids(dept_id)
	assigned.sort()
	for i in staff.size():
		var rank_value := ManagerSystem.rank(assigned[i]) if i < assigned.size() else 0
		(staff[i] as Character).manager_rank = rank_value
		(staff[i] as Character).queue_redraw()

func _update_pile_height() -> void:
	if not GameState.ready_flag:
		return
	var earned: BigNumber = BigNumber.from_save(
		GameState.venue_state(GameState.current_venue).get("earned_total", {}))
	var approx: float = 0.0
	if not earned.is_zero():
		approx = float(earned.e) + log(maxf(earned.m, 0.01)) / log(10.0)
	_pile_height = clampf(8.0 + approx * 6.0, 8.0, 74.0)
	_pile_layer.queue_redraw()

# --- Simulation ---------------------------------------------------------------

## Largest simulation step taken in one go. A dropped frame, a hitch, or an app
## resuming from background can hand _process a delta of a second or more; feeding
## that to the movers straight through makes visitors and porters advance in
## teleports and skips the states in between. Sub-stepping keeps the sim's
## behaviour independent of how smoothly it is being drawn.
const MAX_SIM_STEP := 0.05

func _process(delta: float) -> void:
	if not GameState.ready_flag:
		return
	advance_sim(delta * time_scale)

## Advance the visual sim by `seconds`, in fixed sub-steps. Public because the
## suites drive it directly: pacing a test on wall-clock made its assertions a
## function of machine load, which is how the porter-loop check ended up failing
## about half the time on a busy box.
func advance_sim(seconds: float) -> void:
	_plan_porter_routes()
	var remaining: float = maxf(seconds, 0.0)
	while remaining > 0.0:
		var dt: float = minf(remaining, MAX_SIM_STEP)
		remaining -= dt
		_city.advance(dt, _pedestrian_crossing())
		_plaza.advance(dt)
		_spawn_t += dt
		_try_spawn()
		_update_serve(dt)
		_crowd_traffic.refresh_obstacles(dt)
		_crowd_traffic.begin_step()
		_update_visitors(dt)
		_update_rejected(dt)
		_journeys.advance(dt)
		_update_porters(dt,false)
		_update_reactive_doors(dt)
		_update_exhibit_motion(dt)
		_update_bags(dt)
		if _pile_flash > 0.0:
			_pile_flash = maxf(_pile_flash - dt * 2.0, 0.0)
			var pulse := sin(_pile_flash * PI) * 0.12
			_pile_layer.scale = Vector2(1.0 + pulse, 1.0 + pulse * 0.72)
			_pile_layer.queue_redraw()
		elif _pile_layer.scale != Vector2.ONE:
			_pile_layer.scale = Vector2.ONE
	if _stacks_dirty:
		_stacks_dirty = false
		_stacks_layer.queue_redraw()

## Only animated exhibit nodes redraw, at their baked frame rate.
func _update_exhibit_motion(dt: float) -> void:
	for entry in _animated_exhibits:
		var motion: Dictionary = entry["state"]
		var fps := float(motion.get("fps",8.0))
		var count := int(motion.get("frame_count",64))
		motion["elapsed"] = fposmod(float(motion["elapsed"]) + dt, float(count)/fps)
		var frame := int(float(motion["elapsed"]) * fps) % count
		if frame != int(motion["frame"]):
			motion["frame"] = frame
			var node: Node2D = entry["node"]
			if is_instance_valid(node):
				node.queue_redraw()

func _try_spawn() -> void:
	# The old floor could never spawn faster than one visitor every 1.2s, so a
	# fully upgraded museum held about fifteen people and still read as a diagram.
	# MAX_ALIVE is the real cap now; this only paces the arrivals up to it.
	#
	# The 0.7s floor is set by the BAKE, not by the economy. Filling to MAX_ALIVE
	# in twelve seconds outran CharacterBaker and left a third of the cast drawing
	# ~18 primitives apiece instead of blitting one quad, which measured as a
	# 1270-draw-call spike over the first ten seconds of a session. Arriving half
	# as fast keeps the ramp inside the bake and costs nothing at steady state,
	# where throughput is set by dwell time and never approaches this rate.
	var interval: float = clampf(1.0 / clampf(_arrival, 0.2, 8.0), 0.7, 6.0)
	if _spawn_t < interval:
		return
	_spawn_t = 0.0
	if _visitors.size() >= MAX_ALIVE:
		# This is a renderer/population budget, not a service failure. Silently
		# defer the next arrival; showing an angry walk-away here lied whenever
		# cashier slots were visibly open but the gallery already held the cap.
		return
	var best: int = -1
	for w in _windows_active:
		if _queues[w].size() < _slots_per_window \
				and (best == -1 or _queues[w].size() < _queues[best].size()):
			best = w
	if best == -1 and _crowd.size() >= MAX_CROWD:
		_try_spawn_rejected()
		return
	var v := Visitor.new()
	var c: Character = Character.new()
	c.set_look_slot(_next_look_slot())
	_canvas.add_child(c)
	v.node = c
	# Guests emerge at real neighborhood doors, stopped transport, or the
	# distant district boundary and follow the connected public approach.
	v.outside_path = _journeys.arrival_route()
	v.uses_crosswalk = true
	v.pos = v.outside_path[0]
	v.path = v.outside_path.slice(1)
	var lobby_front: float = (_theme.role("lobby")["rect"] as Rect2).end.y
	v.path.append(Vector2(_door_g.x, _street_g.y))
	var apron := Vector2(_door_g.x, lobby_front + .5)
	v.path.append(apron)
	v.path.append_array(_nav_path(apron, _door_g))
	v.path.append(_door_g)
	v.speed = c.preferred_walk_speed()*randf_range(.96,1.08)
	_place(c, v.pos)
	c.modulate.a = 0.0
	_visitors.append(v)
	# Join an indoor line only after reaching the entrance. An off-screen child
	# waiting at the crossing must not reserve the first place at an empty till.
	v.state="arriving";v.target=_door_g

## The look slot least represented among the visitors already on the floor.
##
## Rolling a slot at random is not good enough at these populations: with 24
## slots and fifteen people on screen the birthday paradox alone puts three of
## them in the same face, and a repeated face is the most obvious tell that a
## crowd is procedural. Dealing the rarest slot makes every visitor unique while
## the floor holds fewer than LOOK_COUNT of them.
func _next_look_slot() -> int:
	var used := PackedInt32Array()
	used.resize(Character.LOOK_COUNT)
	used.fill(0)
	var cast: Array=_visitors.duplicate()
	cast.append_array(_rejected)
	for person in _journeys.people:cast.append(person.v)
	for v in cast:
		var s: int = (v.node as Character).look_slot()
		if s >= 0:
			used[s] += 1
	var best: int = _look_cursor
	var fewest: int = 1 << 30
	for i in Character.LOOK_COUNT:
		# Sweeping from a rolling cursor stops ties always resolving to slot 0,
		# which would make the first faces of every session identical.
		var s: int = (_look_cursor + i) % Character.LOOK_COUNT
		if used[s] < fewest:
			fewest = used[s]
			best = s
			if fewest == 0:
				break
	_look_cursor = (best + 1) % Character.LOOK_COUNT
	return best

## Overflow visitors mill in the lobby between the reception desk and the
## carpet. Rows shear east as they come forward so the block stays inside the
## visible wedge (gx >= gy - 12) all the way to the front row.
func _crowd_slot(i: int) -> Vector2:
	var col: int = i % _crowd_cols
	var row: int = i / _crowd_cols
	return _crowd_origin + Vector2(
		float(col) * _crowd_col_step + float(row) * _crowd_row_shear,
		float(row) * _crowd_row_step)

func _free_window() -> int:
	var best: int=-1
	for w in _windows_active:
		var approaching:=false
		for guest in _queues[w]:
			if not guest.queue_entered:approaching=true;break
		# One guest uses a lane's approach at a time. Other waiting guests keep
		# their lobby places until that entrance is clear, avoiding opposing
		# approaches to the same narrow mouth around a rotated counter.
		if not approaching and _queues[w].size()<_slots_per_window and (best<0 or _queues[w].size()<_queues[best].size()):best=w
	return best

func _static_lobby_standing(at: Vector2) -> bool:
	var room: Rect2=_theme.role("lobby").get("rect",Rect2())
	var id:=_nav_id(at)
	if not room.has_point(at) or not _nav.region.has_point(id) or _nav.is_point_solid(id):return false
	# Seat access cells are intentionally walkable for sitting. They are not
	# permission for a waiting visitor to stand in a bench or its access lane.
	for spec in _theme.props:
		if str(spec.get("kind",""))=="bench" and Exhibits.solid_rect(spec).grow(.30).has_point(at):return false
	for seat in _seats:
		var approach: Vector2=_seat_approaches.get(seat,seat)
		if Geometry2D.get_closest_point_to_segment(at,seat,approach).distance_to(at)<.64:return false
	return true

func _clear_lobby_standing(at: Vector2) -> bool:
	# Geometry changes only when navigation is rebuilt. Keep live crowd
	# occupancy separate so arrivals do not rescan every bench for every slot.
	if not _lobby_standing_geometry.has(at):_lobby_standing_geometry[at]=_static_lobby_standing(at)
	if not bool(_lobby_standing_geometry[at]):return false
	if not _crowd_traffic.standing_clear(at):return false
	for other in _crowd:
		if other.target.distance_to(at)<.64:return false
	return true

func _hold_in_lobby(v: Visitor) -> bool:
	for index in MAX_CROWD:
		var used:=false
		for other in _crowd:
			if other.waiting_slot==index:used=true;break
		if used:continue
		var preferred:=_crowd_slot(index);var center:=_nav_id(preferred)
		for radius in range(9):
			for y in range(-radius,radius+1):
				for x in range(-radius,radius+1):
					if maxi(absi(x),absi(y))!=radius:continue
					var at: Vector2=preferred if radius==0 else Vector2(center+Vector2i(x,y))*.25
					if not _clear_lobby_standing(at):continue
					var path:=_nav_path(v.pos,at)
					if path.is_empty() and v.pos.distance_to(at)>.5:continue
					v.waiting_slot=index;v.state="to_crowd";v.window=-1
					v.crowd_travel=0.0
					v.target=at;v.path=path;_crowd.append(v)
					return true
	return false

func _promote_waiters() -> void:
	for v in _crowd.duplicate():
		if v.state!="crowd":continue
		var w:=_free_window()
		if w<0:return
		_assign_to_window(v,w)

## New arrivals approach from outside the waiting lanes. Otherwise a shortest
## route can enter beside the cashier and walk against the line to reach its tail.
func _mask_admission_actions(skip_station: int=-1,skip_guest: Variant=null) -> Array[Vector2i]:
	var changed: Array[Vector2i]=[]
	for station_index in _windows_active:
		if station_index==skip_station:continue
		var station: Dictionary=_admissions.stations[station_index]
		var head:=_admissions.slot(station_index,0)
		var tail:=_admissions.slot(station_index,_slots_per_window-1)
		var bounds:=Rect2(head,Vector2.ZERO).expand(tail).grow(_lane_offset+.5)
		var first:=_nav_id(bounds.position);var last:=_nav_id(bounds.end)
		for y in range(first.y,last.y+1):
			for x in range(first.x,last.x+1):
				var id:=Vector2i(x,y)
				if not _nav.region.has_point(id) or _nav.is_point_solid(id):continue
				var delta:=Vector2(id)*.25-(station.center as Vector2)
				var along: float=delta.dot(station.front)
				if absf(delta.dot(station.right))<=_lane_offset-.08 and along>=_admissions.slot_lead-.35 and along<=_admissions.slot_lead+float(_slots_per_window-1)*_admissions.slot_gap+.15:
					_nav.set_point_solid(id,true);changed.append(id)
	# Keep admission traffic outside the occupied seat and its stand-up area.
	# Reserve the complete action footprint even while a guest is approaching
	# their claimed seat; otherwise a later sit can invalidate an arrival route.
	for guest in _visitors:
		if guest==skip_guest:continue
		if not _has_seating_claim(guest):continue
		var start: Vector2=guest.target
		var finish:=_seating_front(guest)
		var bounds:=Rect2(start,Vector2.ZERO).expand(finish).grow(.72)
		var first:=_nav_id(bounds.position);var last:=_nav_id(bounds.end)
		for y in range(first.y,last.y+1):
			for x in range(first.x,last.x+1):
				var id:=Vector2i(x,y)
				if not _nav.region.has_point(id) or _nav.is_point_solid(id):continue
				var point:=Vector2(id)*.25
				if Geometry2D.get_closest_point_to_segment(point,start,finish).distance_to(point)<.72:
					_nav.set_point_solid(id,true);changed.append(id)
	return changed

func _queue_entry_path(from: Vector2, w: int) -> Array:
	var changed:=_mask_admission_actions()
	var path:=_nav_path(from,_queue_mouth(w))
	for id in changed:_nav.set_point_solid(id,false)
	return path

func _has_seating_claim(v: Visitor) -> bool:
	return v.seat>=0 and v.state in ["rest","rise"]

func _seating_front(v: Visitor) -> Vector2:
	var facing: Vector2=_seat_facings.get(v.target,Vector2.DOWN)
	return v.target+facing*v.node.seating_foot_distance()

func _detour_seating(v: Visitor, next: Vector2) -> bool:
	if v.state!="to_queue_entry":return false
	for other in _visitors:
		if other==v or not _has_seating_claim(other):continue
		var a: Vector2=other.target;var b:=_seating_front(other)
		var pair:=Geometry2D.get_closest_points_between_segments(v.pos,next,a,b)
		var before:=Geometry2D.get_closest_point_to_segment(v.pos,a,b).distance_squared_to(v.pos)
		var after:=Geometry2D.get_closest_point_to_segment(next,a,b).distance_squared_to(next)
		if pair[0].distance_to(pair[1])<.60 and after<before:
			if v.seating_detour_retry<=0:
				v.seating_detour_retry=.5
				var replacement:=_queue_entry_path(v.pos,v.window)
				if not replacement.is_empty():v.path=replacement
			return true
	return false

func _assign_to_window(v: Visitor, w: int) -> void:
	_crowd.erase(v);v.waiting_slot=-1
	v.state="to_queue_entry";v.window=w;v.queue_entered=false
	_queues[w].append(v)
	var mouth:=_queue_mouth(w)
	v.path=_queue_entry_path(v.pos,w);v.target=mouth

func _refresh_waiting_line(w: int) -> void:
	for i in _queues[w].size():
		var guest: Visitor=_queues[w][i]
		if not guest.queue_entered:continue
		var target:=_slot_pos(w,i)
		if not guest.target.is_equal_approx(target):
			guest.target=target;guest.path=_nav_path(guest.pos,target)
			guest.state="to_queue"

func _enter_waiting_line(v: Visitor) -> void:
	# Mouth arrival establishes order. Faster arrivals do not wait behind an
	# empty position belonging to someone still walking across the lobby.
	var queue: Array=_queues[v.window];queue.erase(v)
	var index:=0
	while index<queue.size() and queue[index].queue_entered:index+=1
	queue.insert(index,v);v.queue_entered=true;v.state="to_queue"
	v.target=_slot_pos(v.window,index);v.path=_nav_path(v.pos,v.target)
	_refresh_waiting_line(v.window)

func _slot_pos(w: int, idx: int) -> Vector2:
	return _admissions.slot(w,idx)

func _queue_mouth(w: int) -> Vector2:
	return _admissions.mouth(w)

## Visitors leave the HEAD of a line through the gap beside their own register.
## Sending everybody back to the common queue mouth made a served guest retrace
## the entire rope lane, then cut through Promotions to reach the gallery.
func _cashier_exit(w: int) -> Vector2:
	if _admissions.authored:return _admissions.stations[w].exit
	var q: Rect2 = _theme.role("queue").get("rect", Rect2())
	var center_x: float = (_window_gx[0] + _window_gx.back()) * 0.5
	var side: float = -1.0 if _window_gx[w] <= center_x else 1.0
	# Alternate the exact side at the centre register so consecutive guests do
	# not stack on one tile.
	if absf(_window_gx[w] - center_x) < 0.05:
		side = -1.0 if bool(_gallery_egress_cursor & 1) else 1.0
	var x := clampf(_window_gx[w] + side * (_lane_offset + 0.34),
		q.position.x + 0.65, q.end.x - 0.65)
	# Old row layouts can put a side departure in a wall after room spreading.
	# Resolve the actual free destination before asking navigation for a path.
	return _safe_nav_spot(Vector2(x, _counter_gy + 0.72))

## Shared side aisle around the OUTSIDE of the rope bank. It has a bottom point
## below every post and a top point above the counters, so a served visitor can
## leave without clipping sideways through a rope or walking through a teller.
func _queue_aisle(bottom: bool) -> Vector2:
	if _admissions.authored:return _admissions.mouth(0) if bottom else _admissions.stations[0].porter
	var q: Rect2 = _theme.role("queue").get("rect", Rect2())
	var x: float = minf(_window_gx.back() + _lane_offset + 0.55, q.end.x - 0.65)
	var y: float = _queue_mouth(0).y if bottom else _porter_lane_gy
	return Vector2(x, y)

func _serve_time() -> float:
	var per_window: float = clampf(_serve, 0.25, 3.0) / float(maxi(_windows_active, 1))
	return clampf(1.0 / per_window, MIN_SERVE_S, 8.0)

func _update_serve(dt: float) -> void:
	# Tell the economy which tills actually have a customer. It is rate-based and
	# books takings every tick regardless; this only decides WHICH window's pile
	# they land on, so an empty window stops counting money by itself.
	var busy := PackedInt32Array()
	for w in _windows_active:
		if _queues[w].is_empty():
			_serve_t[w] = 0.0
			continue
		var front: Visitor = _queues[w][0]
		if front.state != "queue" or front.pos.distance_to(_slot_pos(w,0))>.03 or not front.path.is_empty():
			continue
		busy.append(w)
		_serve_t[w] += dt
		if _serve_t[w] >= _serve_time():
			_serve_t[w] = 0.0
			_serve_visitor(w)
	Economy.set_busy_stations(GameState.current_venue, busy)

func _serve_visitor(w: int) -> void:
	var v: Visitor = _queues[w].pop_front()
	_stacks[w] += 1
	_stacks_dirty = true
	if w < _staff_nodes.size():
		var teller: Node2D = _staff_nodes[w]
		var base: Vector2 = teller.scale
		var tw := teller.create_tween()
		tw.tween_property(teller, "scale", base * 1.16, 0.09)
		tw.tween_property(teller, "scale", base, 0.16)
	_spawn_float("+$" + _value_text, _admissions.point(w,Vector2(0,-1)), true)
	# A happy visitor tips. Both the odds and the size come from the venue's
	# satisfaction, so fast service and good decor are what make the floor worth
	# looking at — see Economy.roll_bag.
	_refresh_waiting_line(w)
	var keys: Array = _exhibit_keys.duplicate()
	keys.shuffle()
	var spots: Array = []
	# The ticket purchase branches into legible visitor intents: Gallery only,
	# Promotions only, or Promotions followed by Gallery. Previously Promotions
	# was merely an occasional detour prepended to one mandatory gallery route.
	var intent_roll := randf()
	var visits_promo: bool = intent_roll < 0.55
	var visits_gallery: bool = intent_roll >= 0.20
	if visits_promo:
		var promo: Dictionary = _theme.role("promo")
		if not promo.is_empty():
			var pr: Rect2 = promo["rect"]
			var cafe_spots := Exhibits.points(promo.get("visitor_spots", []))
			if str(promo.get("experience", "")) == "cafe" and not cafe_spots.is_empty():
				cafe_spots.shuffle()
				for cafe_spot in cafe_spots.slice(0, randi_range(1, 3)):
					spots.append(pr.position + cafe_spot)
				var cap := maxi(Economy.track_max_level(
					GameState.current_venue, "speed"), 1)
				var service_quality := clampf(float(
					GameState.dept_level(GameState.current_venue, "promotions", "speed")
					+ GameState.dept_level(GameState.current_venue, "promotions", "value"))
					/ float(cap * 2), 0.0, 1.0)
				v.tip_mult = 1.0 + service_quality
				v.tip_due = randf() < minf(Economy.bag_drop_chance(
					GameState.current_venue) + service_quality * 0.15, 0.80)
			else:
				spots.append(pr.position + Vector2(
					randf_range(pr.size.x * 0.32, pr.size.x * 0.68),
					randf_range(pr.size.y * 0.58, pr.size.y * 0.78)))
	if visits_gallery:
		# Multiple exhibit stops make the upper hall feel like a destination.
		for k in keys.slice(0, randi_range(1, 3)):
			var opts: Array = _browse[k]
			spots.append(opts[randi() % opts.size()])
	if spots.is_empty() and not _lobby_spots.is_empty():
		spots.append(_lobby_spots.pick_random())
	if not v.tip_due:
		v.tip_due = Economy.roll_bag(GameState.current_venue)
	v.spots = []
	for spot in spots:
		v.spots.append(_safe_nav_spot(spot))
	v.state = "browse"
	v.departing_window=v.window
	v.window = -1
	v.target = v.spots.pop_front()
	# Step sideways through the clear gap at the register, then let navigation
	# choose the nearest route to this guest's destination. Nobody walks back to
	# the tail of the line after already being served.
	var cashier_exit := _cashier_exit(w)
	v.path = _nav_path(v.pos, cashier_exit)
	v.path.append(cashier_exit)
	v.path.append_array(_nav_path(cashier_exit, v.target))
	_promote_waiters()

func _update_visitors(dt: float) -> void:
	_promote_waiters()
	var done: Array = []
	for v in _visitors:
		v.arrival_fade=minf(1.0,v.arrival_fade+dt*2.5);v.node.modulate.a=v.arrival_fade
		var arrived: bool = _move(v, dt)
		match v.state:
			"arriving":
				if arrived:
					var w:=_free_window()
					if w>=0:_assign_to_window(v,w)
					elif not _hold_in_lobby(v):
						v.state="admission_full";v.wait=1.2
						v.node.reaction="angry";_turned_away_total+=1
			"admission_full":
				v.wait-=dt
				if v.wait<=0:_begin_exit(v)
			"to_crowd":
				if arrived:
					v.state="crowd"
					v.crowd_travel=0.0
				else:
					# A sealed slot (parked cart, shifted crowd) has no other
					# recovery: release it and re-hold for a clear one, else
					# admit defeat exactly like a lobby that never had room.
					v.crowd_travel+=dt
					if v.crowd_travel>CROWD_TRAVEL_LIMIT:
						v.crowd_travel=0.0
						_crowd.erase(v)
						v.waiting_slot=-1
						if not _hold_in_lobby(v):
							v.state="admission_full";v.wait=1.2
							v.node.reaction="angry";_turned_away_total+=1
			"to_queue_entry":
				if arrived:_enter_waiting_line(v)
			"to_queue":
				if arrived:
					v.state = "queue"
			"queue", "crowd":
				pass
			"browse":
				if arrived:
					if v.tip_due and _bags.size() < Economy.bag_max_alive():
						_drop_bag(v.pos + Vector2(
							randf_range(-0.42, 0.42), randf_range(-0.30, 0.38)),
							v.tip_mult)
						v.tip_due = false
					if v.wait <= 0.0:
						v.wait = randf_range(1.2, 2.6)
					v.wait -= dt
					if v.wait <= 0.0:
						if not v.spots.is_empty():
							v.target = v.spots.pop_front()
							v.path = _nav_path(v.pos, v.target)
						elif randf() >= REST_CHANCE or not _begin_rest(v):
							_begin_exit(v)
			"rest":
				v.node.prepare_seating()
				if not arrived:
					# Give up on an unreachable seat rather than orbit it.
					v.rest_travel += dt
					if v.rest_travel > REST_TRAVEL_LIMIT:
						_begin_exit(v)
				if arrived:
					if not v.node.seated:
						if OS.has_environment("GRAND_EXHIBIT_SEAT_DEBUG"):
							print("[SEATDBG] sat down at ", v.target)
						var front: Vector2 = _seat_facings.get(v.target,Vector2.DOWN)
						var offset := Iso.to_screen(v.target)-Iso.to_screen(v.pos)
						if not v.node.begin_seating(front,offset):
							_begin_exit(v)
							continue
						v.wait = randf_range(REST_SECONDS.x, REST_SECONDS.y)
					if not v.node.advance_seating(dt,true):continue
					v.wait -= dt
					if v.wait <= 0.0:
						v.state = "rise"
			"rise":
				if v.node.advance_seating(dt,false):_begin_exit(v)
			"linger":
				if arrived:
					_begin_exit(v)
			"exit":
				if arrived and _journeys.accept(v):
					done.append(v)
			"exit_blocked":
				# _move above already walks the indoor leg toward outside_exit.
				# Retry only the outdoor plaza leg on a bounded backoff; never
				# teleport, never drop collision, never delete on screen.
				v.exit_retry -= dt
				if v.exit_retry <= 0.0:
					# A plan without an entry/kind (e.g. a synthetic injection)
					# can never route; remake it instead of resuming with a
					# degenerate target that later trips the city handoff.
					if not v.city_plan.has("entry") or not v.city_plan.has("kind"):
						var stale_park := int(v.city_plan.get("park", -1))
						if stale_park >= 0:
							_plaza.reserved_activities.erase(stale_park)
						v.city_plan = _journeys.plan(v)
						v.exit_attempts = 0
						v.exit_retry = 1.0
					else:
						var outside_exit := _exit_wall_g + Vector2(0, 0.65)
						var entry: Vector2 = v.city_plan.get("entry", outside_exit)
						var route := _plaza.route(outside_exit, entry)
						if not route.is_empty():
							v.path.append_array(route)
							v.target = entry
							v.state = "exit"
							v.exit_attempts = 0
							v.exit_retry = 0.0
							_unreachable_targets.erase("public_exit")
						else:
							v.exit_attempts += 1
							if v.exit_attempts >= 8:
								var old_park := int(v.city_plan.get("park", -1))
								if old_park >= 0:
									_plaza.reserved_activities.erase(old_park)
								v.city_plan = _journeys.plan(v)
								v.exit_attempts = 0
							v.exit_retry = 1.0
	for v in done:
		_release_seat(v)
		_visitors.erase(v)
		if v.state!="city":v.node.queue_free()

## Compact live census for gallery-freeze diagnostics (WORLD-OPEN).
## Called by tools on a bounded interval, not every tick: each entry carries a
## stable visitor id plus the state needed to tell a capacity wait from a stall
## (state, position/target, first path points, speed, wait, seat, windows,
## cart refuge, city plan). Callers diff successive censuses to derive age and
## movement; the floor itself stays rate-limited by only building this on demand.
func visitor_census() -> Array:
	var out: Array = []
	for v in _visitors:
		var first_points: Array = []
		for i in mini(3, v.path.size()):
			first_points.append(str(v.path[i]))
		out.append({
			"id": v.node.get_instance_id() if is_instance_valid(v.node) else 0,
			"state": v.state,
			"pos": str(v.pos),
			"target": str(v.target),
			"path_len": v.path.size(),
			"path_first": first_points,
			"speed": v.speed,
			"wait": v.wait,
			"seat": v.seat,
			"window": v.window,
			"departing_window": v.departing_window,
			"cart_refuge": v.cart_refuge,
			"city_kind": str(v.city_plan.get("kind", "")),
			"city_park": int(v.city_plan.get("park", -1)),
			"exit_attempts": v.exit_attempts,
		})
	return out

## Where the furniture offers a seat, in grid space.
##
## Derived from the props rather than authored separately, so a venue that places
## a bench gets usable seating for free and the two can never disagree about where
## the timber is. Offsets mirror the painters in Exhibits: a bench seats two along
## its length, a café table has four stools.
var _seat_approaches: Dictionary = {}
var _seat_facings: Dictionary = {}
var _unreachable_targets: Dictionary = {}

func _add_seat(position: Vector2, front: Vector2, approach_depth: float = .70, facing: Vector2 = Vector2.ZERO) -> void:
	_seats.append(position)
	_seat_approaches[position] = position + front * approach_depth
	_seat_facings[position] = front if facing==Vector2.ZERO else facing

func _rebuild_seats() -> void:
	_seats.clear()
	_seat_approaches.clear()
	_seat_facings.clear()
	if OS.has_environment("GRAND_EXHIBIT_SEAT_DEBUG"):
		print("[SEATDBG] rebuild_seats props=", _theme.props.size())
	_seat_taken.clear()
	for entry in _theme.props:
		var p: Dictionary = entry as Dictionary
		var at: Vector2 = Exhibits.v2(p.get("at"))
		match str(p.get("kind", "")):
			"bench":
				# Along the bench's OWN axis. Benches gained an orientation when
				# they started hugging walls, and this kept deriving seats as if
				# every one still ran along x — so a north-south bench put its two
				# seats out beside itself, often inside the wall it was against.
				# Visitors then walked to a spot that was not a seat, could not
				# arrive, and stacked up waiting on furniture that looked empty.
				var ln: float = Exhibits.f(p.get("len"), 1.5)
				var along: Vector2 = Vector2(1.0, 0.0) \
					if str(p.get("axis", "x")) == "x" else Vector2(0.0, 1.0)
				# Sit on the seat, which moves to the far side when the bench is
				# flipped. Deriving this from `axis` alone would seat everyone
				# behind the backrest on half the benches in the building.
				var depth: float = 0.14 if bool(p.get("flip", false)) else 0.30
				var across: Vector2 = Vector2(0.0, depth) \
					if str(p.get("axis", "x")) == "x" else Vector2(depth, 0.0)
				var front := Vector2.DOWN if str(p.get("axis", "x")) == "x" else Vector2.RIGHT
				# A reading bench may have a desk in front. Keep its actual
				# approach in the clear aisle instead of reopening that desk.
				var approach_depth := Exhibits.f(p.get("approach_depth"), .70)
				if bool(p.get("flip", false)):front = -front
				# Short benches seat one; two approved silhouettes need room between hips.
				if ln < 1.5:
					_add_seat(at + along * (ln * 0.5) + across, front, approach_depth)
				else:
					_add_seat(at + along * (ln * 0.25) + across, front, approach_depth)
					_add_seat(at + along * (ln * 0.75) + across, front, approach_depth)
			"cafe_table":
				for off in Exhibits.cafe_seat_offsets(p):
					# Sit facing the table; approach from its outside edge.
					var facing := Vector2(-signf(off.x),0) if absf(off.x)>=absf(off.y) else Vector2(0,-signf(off.y))
					_add_seat(at + off, off.normalized(),.70,facing)
	# A seat is real if it stands on the museum's own ground. Camera panning
	# makes wing furniture usable even outside the original fixed canvas.
	#
	# That means the PLINTH, not only the rooms. The first cut required a seat to be
	# inside a room, reasoning that a visitor sent outside would be leaving the paid
	# building — which quietly discarded every seat on the forecourt terrace, so
	# widening the apron produced outdoor furniture nobody could use. The terrace is
	# the museum's own ground, an outdoor lounge is the whole point of it, and taking
	# pressure off the indoor lounges is what it is there for.
	var apron: float = Exhibits.f(_theme.shell.get("inset"), 0.35) + 0.6
	var plinth: Rect2 = _theme.bounds.grow(apron)
	var usable: Array[Vector2] = []
	for s in _seats:
		if plinth.has_point(s):
			usable.append(s)
	_seats = usable
	# Rebuilding furniture must not make an occupied bench available again.
	# Bind claims to the physical seat, since indices may change with furniture.
	for visitor in _visitors:
		if visitor.seat < 0:
			continue
		var seat_index := _seats.find(visitor.target)
		if seat_index >= 0 and not _seat_taken.has(seat_index):
			visitor.seat = seat_index
			_seat_taken[seat_index] = true
		else:
			# Removed seats (or duplicate claims from an older layout) release
			# their guest without erasing another guest's valid reservation.
			visitor.seat = -1
			visitor.path.clear()
			visitor.target = visitor.pos
			visitor.state = "rise" if visitor.node.seated else "linger"
	if OS.has_environment("GRAND_EXHIBIT_SEAT_DEBUG"):
		print("[SEATDBG] seats=", _seats.size())

## Send a visitor to rest. False if nothing is free, so the caller can just leave.
func _begin_rest(v: Visitor) -> bool:
	if _seats.is_empty():
		return false
	var order: Array = range(_seats.size())
	order.shuffle()
	for i in order:
		if _seat_taken.has(i):
			continue
		v.seat = int(i)
		_seat_taken[v.seat] = true
		v.state = "rest"
		v.wait = 0.0
		v.rest_travel = 0.0
		v.target = _seats[v.seat]
		v.path = _nav_path(v.pos, v.target)
		return true
	return false

func _release_seat(v: Visitor) -> void:
	if v.seat >= 0:
		_seat_taken.erase(v.seat)
		v.seat = -1
	if v.node != null:
		v.node.end_seating()

func _begin_exit(v: Visitor) -> void:
	_release_seat(v)
	v.state = "exit"
	v.wait = 0.0
	v.city_plan = _journeys.plan(v)
	var sidewalk: Array = [v.city_plan.entry]
	var outside_exit := _exit_wall_g+Vector2(0,.65)
	var lane: int = _gallery_egress_cursor % 2
	_gallery_egress_cursor += 1
	var authored: Array = _gallery_egress.slice(lane * 4, lane * 4 + 4)
	v.path = []
	var cursor: Vector2 = v.pos
	for waypoint in authored:
		v.path.append_array(_nav_path(cursor, waypoint))
		v.path.append(waypoint)
		cursor = waypoint
	v.path.append_array(_nav_path(cursor, _exit_door_g))
	v.path.append(_exit_door_g)
	v.path.append(outside_exit)
	var outdoor_route := _plaza.route(outside_exit,sidewalk[0])
	if outdoor_route.is_empty():
		_unreachable_targets["public_exit"] = true
		v.state = "exit_blocked"
		v.target = outside_exit
		v.exit_retry = 1.0
		v.exit_attempts = 0
	else:
		v.path.append_array(outdoor_route)
		v.target = sidewalk[0]

func _try_spawn_rejected() -> void:
	if _rejected.size() >= 2:
		return
	var v := Visitor.new()
	var c: Character = Character.new()
	c.set_look_slot(_next_look_slot())
	_canvas.add_child(c)
	v.node = c
	v.outside_path = _journeys.arrival_route()
	v.pos = v.outside_path[0]
	v.path = v.outside_path.slice(1)
	v.path.append(Vector2(_door_g.x, _street_g.y))
	var front_y: float = (_theme.role("lobby")["rect"] as Rect2).end.y
	var apron := Vector2(_door_g.x, front_y + .5)
	v.path.append(apron)
	v.path.append_array(_nav_path(apron, _door_g))
	v.target = _door_g
	v.state = "rejected_in"
	v.speed = c.preferred_walk_speed()*randf_range(1.0,1.08)
	_place(c, v.pos)
	_rejected.append(v)
	_turned_away_total += 1

func _update_rejected(dt: float) -> void:
	var done: Array = []
	for v in _rejected:
		var arrived: bool = _move(v, dt)
		if v.state == "rejected_in" and arrived:
			v.node.reaction = "angry"
			v.state = "rejected_wait"
			v.wait = 1.35
		elif v.state == "rejected_wait":
			v.wait -= dt
			if v.wait <= 0.0:
				v.city_plan=_journeys.plan(v)
				_begin_rejected_departure(v)
		elif v.state=="rejected_route_wait":
			v.wait-=dt
			if v.wait<=0:_begin_rejected_departure(v)
		elif v.state == "rejected_out" and arrived and _journeys.accept(v):
			done.append(v)
	for v in done:
		_rejected.erase(v)

func _begin_rejected_departure(v: Visitor) -> void:
	var outside:=Vector2(_door_g.x,(_theme.role("lobby")["rect"] as Rect2).end.y+.65)
	var route:=_plaza.route(outside,v.city_plan.entry)
	if route.is_empty():
		v.state="rejected_route_wait";v.wait=1.0;v.path=[];v.target=v.pos;return
	v.state="rejected_out"
	v.path=_nav_path(v.pos,outside);v.path.append(outside);v.path.append_array(route)
	v.target=v.city_plan.entry

## Grid-space movement. Facing flips on the projected x direction so characters
## turn the way they visually travel, not the way the grid axis points.
func _move(v: Visitor, dt: float) -> bool:
	# Retry timers belong to the simulation tick, not each intermediate point.
	v.seating_detour_retry=maxf(0.0,v.seating_detour_retry-dt)
	v.cart_retry=maxf(0,v.cart_retry-dt)
	if v.state in ["rest","rise"] and v.node.seated:
		v.node.walking=false
		return true
	var remaining:=maxf(dt,0.0)
	# Bound both duplicate waypoints and catch-up work. Each short sweep retains
	# crossing, cart, seat and queue checks, even after reaching a waypoint.
	for segment in 64:
		if v.cart_refuge:
			if not v.target.is_equal_approx(v.cart_refuge_target):v.cart_refuge=false;v.cart_refuge_blockers=[]
			elif v.pos.distance_to(v.cart_refuge_at)<.001:
				if _crowd_traffic.refuge_needed(v):
					v.node.walking=false;return false
				v.cart_refuge=false;v.cart_refuge_blockers=[]
		var goal: Vector2=v.path[0] if not v.path.is_empty() else v.target
		if not _prepare_indoor_segment(v.pos,goal,v.path):
			v.node.walking=false
			return false
		goal=v.path[0] if not v.path.is_empty() else v.target
		var seating_approach:=v.state=="rest" and goal.is_equal_approx(v.target)
		var seat_front: Vector2=_seat_facings.get(v.target,Vector2.DOWN)
		if seating_approach:
			# Stop at planted shoes, not underneath the eventual seated hips.
			goal=v.target+seat_front*v.node.seating_foot_distance()
		if _waiting_to_cross(v.pos,goal):
			v.node.walking=false
			return false
		var d:=goal-v.pos
		var dist:=d.length()
		if dist<.00001:
			v.pos=goal
			_place(v.node,v.pos)
			if not v.path.is_empty():
				v.path.remove_at(0)
				continue
			v.node.walking=false
			return true
		if remaining<=.0000001 or v.speed<=0.0:
			if v.speed<=0.0:v.node.walking=false
			return false
		# A long authored leg or a stalled frame cannot jump a kerb or bypass
		# the local cart broad phase. Ordinary 30/60 Hz steps are smaller still.
		var step:=minf(minf(v.speed*remaining,dist),.125)
		var next:=goal if step>=dist else v.pos+d/dist*step
		if not _crowd_traffic.visitor_clear(v,next):
			v.node.walking=false;v.cart_wait+=remaining;_crowd_traffic.visitor_waits+=1
			if v.cart_wait>=.35:_crowd_traffic.try_detour(v)
			return false
		v.cart_wait=0.0
		if _detour_seating(v,next):
			v.node.walking=false
			return false
		if v.window>=0:
			for other in _visitors:
				if other==v:continue
				if not (other.window==v.window or other.departing_window==v.window):continue
				var near:=_plaza._nearest(other.pos,v.pos,next)
				if near.distance_to(other.pos)<.60 and next.distance_to(other.pos)<v.pos.distance_to(other.pos):
					v.node.walking=false
					return false
		var travel_seconds:=step/v.speed
		v.pos=next
		_place(v.node,v.pos)
		v.node.walk_backwards=seating_approach and d.dot(seat_front)<0
		v.node.record_motion(d/dist*step,travel_seconds,seat_front if v.node.walk_backwards else d)
		v.node.walking=true
		remaining=maxf(remaining-travel_seconds,0.0)
		if step>=dist:
			if not v.path.is_empty():
				v.path.remove_at(0)
			else:
				v.node.walking=false
				return true
	return false

func _waiting_to_cross(pos: Vector2, goal: Vector2) -> bool:
	if _city == null:
		return false
	var crossing_x: float = _city.map_point(City.CROSS_FAR).x
	if absf(pos.x - crossing_x) > 0.5 or absf(goal.x - crossing_x) > 0.5:
		return false
	var near_y: float = _city.map_point(City.CROSS_NEAR).y
	var far_y: float = _city.map_point(City.CROSS_FAR).y
	# Only wait before stepping off a kerb; somebody already in the road keeps
	# moving while traffic yields. Both bounds matter: the former one-sided
	# checks also matched any indoor north/south path at the crossing's x, so a
	# car on the zebra froze whole groups inside Promotions around gy 11.
	var at_far_kerb: bool = absf(pos.y - far_y) <= 0.14 and goal.y < pos.y
	var at_near_kerb: bool = absf(pos.y - near_y) <= 0.14 and goal.y > pos.y
	var stepping_off: bool = at_far_kerb or at_near_kerb
	# A person visibly waiting at the zebra claims right-of-way. Approaching cars
	# stop; only a car already clearing the paint makes the person wait.
	return stepping_off and _city.crossing_has_car()

func _pedestrian_crossing() -> bool:
	var near_y: float = _city.map_point(City.CROSS_NEAR).y
	var far_y: float = _city.map_point(City.CROSS_FAR).y
	var pedestrians: Array=_visitors+_rejected
	for p in _journeys.people:pedestrians.append(p.v)
	for v in pedestrians:
		# Anyone already in the road keeps priority even if the light changes.
		var in_road: bool = v.pos.y > near_y + 0.12 and v.pos.y < far_y - 0.12
		# A person waiting at either kerb claims a gap immediately. This is a
		# reactive crossing, not a decorative traffic light the crowd ignores.
		var at_crossing: bool = v.pos.y > near_y - 0.18 and v.pos.y < far_y + 0.18
		if (in_road or at_crossing) \
				and absf(v.pos.x - _city.map_point(City.CROSS_FAR).x) < 0.55:
			return true
	return false

func _porter_speed(p: Porter) -> float:
	# A brisk working walk has a bounded cadence; upgrade throughput remains
	# in the economy rather than turning the courier into a sprinting sprite.
	return p.node.preferred_walk_speed(clampf(1.7 + _transport * .04, 1.7, 1.95))

func _porter_counter(w: int) -> Dictionary:
	if w<_porter_layout.counters.size() and not _porter_layout.counters[w].is_empty():return _porter_layout.counters[w]
	return {"at":_admissions.stations[w].porter,"heading":_admissions.stations[w].front}

func _porter_bay(p: Porter) -> Dictionary:
	var index:=_porters.find(p)
	if index>=0 and index<_porter_layout.drops.size() and not _porter_layout.drops[index].is_empty():return _porter_layout.drops[index]
	return {"at":_porter_home+Vector2(index*_porter_step,0),"heading":Vector2.DOWN}

func _porter_go(p: Porter,dock: Dictionary,_via_archive: bool=false) -> void:
	p.dispatch_standby=false
	p.dock=dock;p.target=dock.at;p.path=[];p.route_retry=0.0
	if p.route_job!=null:p.route_job.cancel();p.route_job=null
	p.route_steps=[];p.route_cursor=0
	# A staffing refresh can happen between grid points or halfway through a
	# turn. Finish that existing physical step before addressing a new route.
	p.replan_after_step=not p.motion_step.is_empty()
	if not p.replan_after_step:_porter_begin_route(p)

func _porter_begin_route(p: Porter) -> void:
	p.replan_after_step=false;p.node.walking=false;p.node.walk_backwards=false
	p.node.set_motion_vector(p.heading,0.0)
	_cart_dispatch.enqueue(p)

func _plan_porter_routes() -> void:
	_cart_dispatch.advance(512,_porter_planning_budget_usec)
	_porter_planning_usec=_cart_dispatch.last_usec

func _porter_park(p: Porter) -> void:
	p.node.walking=false
	if not p.dock.is_empty():p.node.set_motion_vector(p.dock.heading,0.0)

func _porter_enter(p: Porter) -> void:
	var spawn_dock: Dictionary=_cart_dispatch.spawn_pose(p,_porter_bay(p))
	if spawn_dock.is_empty() or not _crowd_traffic.clear_entry(spawn_dock):
		# This is a new hire waiting to enter, never an existing visible worker.
		p.staged=false;p.state="awaiting_entry";p.node.visible=false;p.route_retry=.25
		return
	p.dock=spawn_dock;p.pos=p.dock.at;p.target=p.pos;p.path=[];p.staged=true
	p.heading=p.dock.heading;p.motion_step={};p.route_job=null;p.route_steps=[];p.route_cursor=0
	p.state="idle";p.route_retry=0;p.node.visible=true
	_place(p.node,p.pos);_porter_park(p)

func _rebuild_porter_staging() -> void:
	_porter_layout.configure(self)
	_porter_router.configure(_porter_layout)
	_cart_dispatch.configure(self)
	_crowd_traffic.configure(self)
	if not _porter_layout.failures.is_empty():push_warning("Porter staging %s: %s"%[_theme.id,_porter_layout.failures])
	for p in _porters:
		var newly_spawned: bool=not p.staged and p.state in ["idle","awaiting_entry"] and p.carried==0
		p.staged=true
		if newly_spawned:
			_porter_enter(p)
		elif p.state in ["to_window","collect"]:
			p.state="to_window";_porter_go(p,_porter_counter(p.window))
		elif p.state in ["to_vault","deposit"]:
			p.state="to_vault";_porter_go(p,_porter_bay(p),true)
		else:_porter_go(p,_porter_bay(p))

## One courier owns each collection point. Ready tills take priority; otherwise
## an unclaimed point is a useful waiting place for the next takings.
func _available_collection(p: Porter, ready_only: bool = false) -> int:
	var best: int=-1
	for w in _windows_active:
		if ready_only and _stacks[w]<1:continue
		var claimed:=false
		for other in _porters:
			if other!=p and _cart_dispatch.claims_collection(other) and other.window==w:
				claimed=true;break
		if not claimed and (best<0 or _stacks[w]>_stacks[best]):best=w
	return best

func _update_porters(dt: float,plan_routes: bool=true) -> void:
	if plan_routes:_plan_porter_routes()
	for p in _porters:
		# Physical bays keep standby staff separate; never ghost a real employee.
		if p.node!=null:p.node.modulate.a=1.0
		match p.state:
			"awaiting_entry":
				p.route_retry=maxf(0,p.route_retry-dt)
				if p.route_retry==0:_porter_enter(p)
			"idle":
				# Stage a free courier at a till before its next collection. Waiting
				# in the archive until two takings exist adds an empty outward trip
				# to every delivery and used to require an implausibly fast walk.
				var best:=_available_collection(p,p.dispatch_standby)
				if best>=0:
					p.window=best;p.state="to_window"
					_porter_go(p,_porter_counter(best))
				elif p.pos.distance_to(p.target)>.0001 or p.heading!=p.dock.heading:
					_porter_move(p,dt)
			"yielding":
				_porter_move(p,dt)
			"to_window":
				if _porter_move(p,dt):p.state="collect";p.wait=0.0;_porter_park(p)
			"collect":
				p.node.walking=false
				# Dispatch a small collection after a short batching wait too; one
				# completed sale must not sit forever waiting for a second guest.
				p.wait=p.wait+dt if _stacks[p.window]>0 else 0.0
				if _stacks[p.window]>=2 or p.wait>=3.0:
					var take: int=mini(_stacks[p.window],6)
					_stacks[p.window]-=take;_stacks_dirty=true
					p.carried=take;p.node.carry_stack=clampi(take,1,4)
					p.node.queue_redraw();p.state="to_vault"
					_porter_go(p,_porter_bay(p),true)
				elif _stacks[p.window]==0 and _available_collection(p,true)>=0:
					p.state="idle";p.window=-1
			"to_vault":
				if _porter_move(p, dt):
					# Pause inside the archive while the cart visibly unloads.
					# Banking at the room threshold looked like a missing route.
					p.state = "deposit"
					p.wait = 0.55
					_porter_park(p)
			"deposit":
				p.wait -= dt
				if p.wait <= 0.0:
					p.carried = 0
					p.node.carry_stack = 0
					p.node.queue_redraw()
					_porter_trips += 1
					_pile_flash = 1.0
					_spawn_coin_burst(_vault_drop, 7)
					p.state = "idle"
					p.path=[];p.target=p.pos

func _porter_move(p: Porter,dt: float) -> bool:
	if p.route_job!=null:
		p.node.walking=false;return false
	if p.route_retry>0:
		p.route_retry=maxf(0,p.route_retry-dt);p.node.walking=false
		if p.route_retry==0:_porter_begin_route(p)
		return false
	var remaining:=maxf(dt,0.0)
	# Carry unused time across quarter-tile waypoints. Rounding every segment
	# to whole frames made the same courier slower at lower frame rates.
	for ignored in 16:
		if p.motion_step.is_empty():
			if p.route_cursor>=p.route_steps.size():
				p.node.walking=false;p.node.walk_backwards=false
				return p.pos.distance_to(p.target)<.0001 and p.heading.is_equal_approx(p.dock.heading)
			if not _crowd_traffic.cart_clear(p,p.route_steps[p.route_cursor]):
				p.node.walking=false;p.node.walk_backwards=false;p.pedestrian_wait+=dt
				if p.pedestrian_wait>=1.0:
					p.pedestrian_wait=0.0;_cart_dispatch.replan_blocked(p)
				return false
			if _crowd_traffic.cart_conflict(p,p.route_steps[p.route_cursor]):
				p.node.walking=false;p.node.walk_backwards=false;p.pedestrian_wait+=dt
				if p.pedestrian_wait>=1.0:
					p.pedestrian_wait=0.0;_cart_dispatch.replan_blocked(p)
				return false
			p.pedestrian_wait=0.0
			p.motion_step=p.route_steps[p.route_cursor];p.turn_progress=0.0
		var step: Dictionary=p.motion_step
		if step.turn:
			var used:=minf(remaining,(1.0-p.turn_progress)/3.0)
			remaining-=used;p.turn_progress=minf(1,p.turn_progress+used*3.0)
			p.node.walking=false;p.node.walk_backwards=false;p.node.set_cart_turn(p.heading,step.heading,p.turn_progress)
			if p.turn_progress<1.0-.000001:return false
			p.heading=step.heading
		else:
			var delta: Vector2=step.at-p.pos;var distance:=delta.length()
			var speed:=_porter_speed(p)*(.65 if step.reverse else 1.0)
			var used:=minf(remaining,distance/speed)
			var travel:=minf(distance,speed*used);remaining-=used
			var moved:=delta.normalized()*travel
			p.pos=step.at if distance-travel<.000001 else p.pos+moved
			_place(p.node,p.pos)
			p.node.walk_backwards=step.reverse;p.node.record_motion(moved,used,p.heading);p.node.walking=travel>0
			if p.pos.distance_to(step.at)>.00001:return false
		p.motion_step={};p.route_cursor+=1
		if p.replan_after_step:_porter_begin_route(p);return false
		if remaining<=.000001:return false
	return false

func _update_reactive_doors(dt: float) -> void:
	for entry in _reactive_doors:
		var trigger: Vector2 = entry.get("trigger", Vector2.ZERO) as Vector2
		var active := false
		match str(entry.get("id", "")):
			"entrance":
				for visitor in _visitors + _rejected:
					if visitor.pos.distance_to(trigger) <= 1.35:
						active = true
						break
			"exit":
				for visitor in _visitors:
					if visitor.pos.distance_to(trigger) <= 1.35:
						active = true
						break
			"vault":
				for porter in _porters:
					if porter.pos.distance_to(trigger) <= 1.45:
						active = true
						break
		var state: Dictionary = entry.get("state", {}) as Dictionary
		var before := float(state.get("open", 0.0))
		var speed := 4.8 if active else 2.8
		var after := move_toward(before, 1.0 if active else 0.0, dt * speed)
		if is_equal_approx(before, after):
			continue
		state["open"] = after
		var node: Node2D = entry.get("node") as Node2D
		if is_instance_valid(node):
			node.queue_redraw()

# --- Money bags ---------------------------------------------------------------
##
## Drawn, not a Control: a Control would need its own input plumbing and would sit
## outside the Y-sort, so a bag would float over a visitor standing in front of it.
## As a Node2D in the cast's own band it occludes and is occluded correctly, and
## the floor routes taps to it before the room underneath.

## Radius, in canvas px, of the tap disc around a bag's anchor. Generous on
## purpose: the sprite is ~18px and a thumb is not, and this is the one thing on
## the floor a player is meant to hit reliably while it is ticking away.
const BAG_TAP_R := 34.0

func _drop_bag(g: Vector2, value_mult: float = 1.0) -> void:
	var value: BigNumber = Economy.bag_value(GameState.current_venue).scale(value_mult)
	if value.is_zero():
		return
	var node := Node2D.new()
	node.z_index = 1                      # above the cast, below the room plaques
	_canvas.add_child(node)
	_place(node, g)
	var bag := {"node": node, "value": value, "pos": g, "t": 0.0}
	_bags.append(bag)
	_bag_drop_history.append(g)
	if _bag_drop_history.size() > 24:
		_bag_drop_history.pop_front()
	node.draw.connect(func() -> void: _draw_bag(node))
	# Land with a hop, then breathe, so the eye catches it arriving.
	node.scale = Vector2(0.4, 0.4)
	var tw := node.create_tween()
	tw.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(node, "scale", node.scale / 0.4 * 1.0, 0.26)
	EventBus.money_bag_dropped.emit(GameState.current_venue)

func _draw_bag(ci: CanvasItem) -> void:
	var body := PackedVector2Array([
		Vector2(-9, -2), Vector2(-6, -13), Vector2(6, -13), Vector2(9, -2),
		Vector2(6, 4), Vector2(-6, 4)])
	var shadow := PackedVector2Array()
	for i in 14:
		var a: float = TAU * float(i) / 14.0
		shadow.append(Vector2(cos(a) * 11.0, 5.0 + sin(a) * 4.0))
	Iso.fill(ci, shadow, Color(0.10, 0.06, 0.18, 0.28))
	Iso.fill(ci, body, UI.SAGE.darkened(0.10))
	var ring := body.duplicate()
	ring.append(body[0])
	ci.draw_polyline(ring, Color("#14532D"), 2.0)
	# Neck tie and a coin spilling out, so it reads as money and not a sack of post.
	ci.draw_line(Vector2(-6, -12), Vector2(6, -12), Color("#14532D"), 3.0)
	ci.draw_circle(Vector2(0, -2), 4.2, UI.BRASS)
	ci.draw_circle(Vector2(-1, -3), 2.0, UI.BRASS.lightened(0.35))

func _update_bags(dt: float) -> void:
	var life: float = Economy.bag_lifetime()
	var dead: Array = []
	for bag in _bags:
		bag["t"] = float(bag["t"]) + dt
		var node: Node2D = bag["node"]
		if not is_instance_valid(node):
			dead.append(bag)
			continue
		var t: float = float(bag["t"])
		if t >= life:
			dead.append(bag)
			node.queue_free()
			continue
		# Fade the last two seconds so expiry is legible rather than a vanish.
		node.modulate.a = clampf((life - t) / 2.0, 0.0, 1.0)
	for b in dead:
		_bags.erase(b)

## Tap a bag if one is under the point. Returns true when it consumed the tap, so
## the room beneath does NOT also open its upgrade sheet — a bag sitting inside a
## room would otherwise fire both.
func _try_tap_bag(canvas_pos: Vector2) -> bool:
	var best: Dictionary = {}
	var best_d: float = BAG_TAP_R
	for bag in _bags:
		var node: Node2D = bag["node"]
		if not is_instance_valid(node):
			continue
		var d: float = node.position.distance_to(canvas_pos)
		if d <= best_d:
			best_d = d
			best = bag
	if best.is_empty():
		return false
	var amount: BigNumber = best["value"]
	Economy.collect_bag(GameState.current_venue, amount)
	_spawn_float("+$" + amount.to_notation(), best["pos"] + Vector2(0.0, -0.4))
	_spawn_coin_burst(best["pos"], 6)
	var node2: Node2D = best["node"]
	_bags.erase(best)
	if is_instance_valid(node2):
		node2.queue_free()
	return true

# --- Feedback -----------------------------------------------------------------

## Routine service stays at the counter; explicit collection shows its amount.
func _spawn_float(text: String, g: Vector2, automatic: bool = false) -> void:
	# Preserve the historical RNG draw here: visitor intent uses the same stream
	# immediately after service. Cosmetic changes must not change crowd routes.
	var drift: float = randf_range(-14.0, 14.0)
	var receipt := IncomeFeedback.new()
	receipt.amount=text
	receipt.automatic=automatic
	receipt.drift=drift
	receipt.z_index=_theme.level_at(g)*Iso.LEVEL_Z+1
	receipt.position=_lifted(g)+Vector2(0,4 if automatic else -8)
	_canvas.add_child(receipt)

## Coin burst when a porter banks a load into the vault.
func _spawn_coin_burst(g: Vector2, count: int = 6) -> void:
	var pos: Vector2 = Iso.to_screen(g)
	for i in count:
		var coin := Node2D.new()
		coin.position = pos
		coin.z_index = 1
		_canvas.add_child(coin)
		var a: float = TAU * float(i) / float(count) + randf_range(-0.2, 0.2)
		var reach: float = randf_range(18.0, 34.0)
		coin.draw.connect(func() -> void:
			Iso.pip(coin, Vector2.ZERO, 4.4, UI.BRASS.darkened(0.25))
			Iso.pip(coin, Vector2(-0.6, -0.6), 3.2, UI.BRASS.lightened(0.25)))
		var tw := coin.create_tween()
		tw.set_parallel(true)
		tw.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tw.tween_property(coin, "position", pos + Vector2(cos(a), sin(a) * 0.6) * reach, 0.42)
		tw.tween_property(coin, "scale", Vector2(0.4, 0.4), 0.5)
		tw.tween_property(coin, "modulate:a", 0.0, 0.5)
		tw.chain().tween_callback(coin.queue_free)

# --- Ground: floors, walls and every decal -------------------------------------
##
## All of the dressing lives in this one canvas item on purpose. A decal can
## never occlude an actor, so it needs neither a node nor a Y-sort slot, and
## Iso.fill submits simple convex faces as batchable drawing primitives; larger
## polygons keep their original triangulation. Each storey retains its own draw
## order, so batching does not flatten the museum or change actor occlusion.

## One node per STOREY above the ground. Each is offset by the storey's rise and
## claims its own z band, so an upper floor wins over the one below outright
## rather than depending on where its projected y happens to land.
func _build_upper_grounds() -> void:
	for lv in _theme.levels():
		var level := int(lv)
		if level == 0 or _upper_grounds.has(level):
			continue
		var n := Node2D.new()
		n.name = "Ground%d" % level
		n.position = Vector2(0.0, Iso.level_lift(level))
		n.z_index = level * Iso.LEVEL_Z
		_canvas.add_child(n)
		n.draw.connect(func() -> void:
			_draw_storey(n, level)
			# Tread geometry uses absolute heights. Cancel this node's lift while
			# painting flights after their own storey's slab, retaining its z band.
			n.draw_set_transform(Vector2(0.0, -Iso.level_lift(level)))
			_draw_stairs(n, Exhibits.c(_theme.shell.get("col"), UI.WALL_BROWN.darkened(0.15)), level)
			n.draw_set_transform(Vector2.ZERO))
		_upper_grounds[level] = n

func _clear_upper_grounds() -> void:
	for n in _upper_grounds.values():
		if is_instance_valid(n):
			(n as Node2D).queue_free()
	_upper_grounds.clear()

func _draw_ground() -> void:
	# The storey masses come first and belong to the GROUND node, not to the
	# storey they hold up: Iso.box extrudes UP from the grid plane, so a box of
	# height level*LEVEL_H drawn here lands its top face exactly where that
	# storey's floor patch is drawn. Without them an upper floor is a slab
	# hanging in the air.
	var shell_col: Color = Exhibits.c(_theme.shell.get("col"), UI.WALL_BROWN.darkened(0.15))
	for entry in _theme.rooms:
		var room: Dictionary = entry as Dictionary
		var level: int = int(room.get("level", 0))
		var top: int = maxi(level, int(room.get("rise_to", level)))
		if top <= 0:
			continue
		# Stair treads provide their own stepped supporting mass. Drawing the
		# stair room as a full-height storey box as well leaves a pale slab
		# cutting through the middle of the staircase.
		if int(room.get("rise_to", level)) != level:
			continue
		# Some rooms exist only to close navigation shortcuts around a stair.
		# They must participate in pathfinding without becoming visible tiles.
		if not bool(room.get("visible", true)):
			continue
		var r: Rect2 = room["rect"]
		if str(room.get("support_style", "solid")) == "bridge":
			MuseumArchitecture.bridge_support(_ground, r, -Iso.level_lift(top))
			continue
		Iso.box(_ground, r.position, r.size, -Iso.level_lift(top),
			shell_col.darkened(0.10), Color(0, 0, 0, 0.22))
		MuseumArchitecture.support_details(_ground, _theme.id, r, -Iso.level_lift(top))
	_draw_storey(_ground, 0)
	# After the storey, not before: a stair room owns a floor patch like any
	# other room, and drawing the treads first just meant painting over them.
	_draw_stairs(_ground, shell_col)

## Treads for every stair room.
##
## The lift already ramps across a stair so a walker climbs it smoothly, but a
## ramped floor with nothing drawn on it reads as a slope, not as a staircase —
## and a visible staircase is the clearest single signal that a venue has more
## than one floor. Each flight belongs to its starting storey and paints after
## that storey's slab. Heights remain absolute; raised callers cancel their lift.
func _draw_stairs(ci: CanvasItem, shell_col: Color, drawing_level: int = 0) -> void:
	const TREADS := Iso.STAIR_TREADS
	for entry in _theme.rooms:
		var room: Dictionary = entry as Dictionary
		var from_level: int = int(room.get("level", 0))
		var to_level: int = int(room.get("rise_to", from_level))
		if to_level == from_level or from_level != drawing_level:
			continue
		var r: Rect2 = room["rect"]
		var stair_axis: String = str(room.get(
			"stair_axis", "x" if r.size.x >= r.size.y else "y"))
		var along_x: bool = stair_axis == "x"
		var reverse: bool = bool(room.get("rise_reverse", false))
		var bottom: float = -Iso.level_lift(from_level)
		var top: float = -Iso.level_lift(to_level)
		if mini(from_level,to_level) > 0:
			MuseumArchitecture.raised_stair_flight(ci,r,bottom,top,along_x,reverse,
				shell_col.lightened(.16),_theme.accent("gallery").darkened(.22))
			continue
		for i in TREADS:
			# Height of the tread's FAR edge, so each step's top face is flat and
			# the riser between it and the next one is what the eye reads as a step.
			var t: float = float(i + 1) / float(TREADS)
			if reverse:
				t = 1.0 - float(i) / float(TREADS)
			var pos: Vector2
			var size: Vector2
			if along_x:
				pos = Vector2(r.position.x + r.size.x * float(i) / float(TREADS), r.position.y)
				size = Vector2(r.size.x / float(TREADS), r.size.y)
			else:
				pos = Vector2(r.position.x, r.position.y + r.size.y * float(i) / float(TREADS))
				size = Vector2(r.size.x, r.size.y / float(TREADS))
			Iso.box(ci, pos, size, lerpf(bottom, top, t),
				shell_col.lightened(0.16 + 0.014 * float(i)), Color(0, 0, 0, 0.20))
			# A broad, deliberately shortened runner visually joins the flight
			# without painting another strip across either landing.
			if i > 0 and i < TREADS - 1:
				var runner_pos := pos
				var runner_size := size
				if along_x:
					runner_pos.y += size.y * 0.20
					runner_size.y *= 0.60
				else:
					runner_pos.x += size.x * 0.20
					runner_size.x *= 0.60
				Iso.box(ci, runner_pos, runner_size,
					lerpf(bottom, top, t) + 1.2,
					_theme.accent("gallery").darkened(0.22), Color(0, 0, 0, 0.12))


		MuseumArchitecture.stair_handrails(ci,r,bottom,top,along_x,reverse,shell_col.lightened(.35))

## Everything that belongs to one storey: its plinth, its floors, its walls and
## its flat dressing. Split by level so an upper floor draws into its own lifted
## node instead of every room being painted onto one plane.
func _draw_storey(ci: CanvasItem, level: int) -> void:
	var rooms: Array = _rooms_on(level)
	# Outer slab, slightly proud of the rooms — reads as the building shell.
	var inset: float = Exhibits.f(_theme.shell.get("inset"), 0.35)
	var shell_col: Color = Exhibits.c(_theme.shell.get("col"), UI.WALL_BROWN.darkened(0.15))
	# One slab per room rather than one rectangle over the whole grid. Adjacent
	# rooms merge into a continuous plinth, but a venue that does NOT tile a
	# rectangle keeps its real silhouette — an L, a T, a courtyard, or detached
	# wings joined by a link room. Drawing the grid rectangle instead was the
	# single reason every venue read as the same square building.
	for entry in rooms:
		var rr: Rect2 = (entry as Dictionary)["rect"]
		Iso.floor_patch(ci, rr.position - Vector2(inset, inset),
			rr.size + Vector2(inset, inset) * 2.0, shell_col)

	for entry in rooms:
		var room: Dictionary = entry as Dictionary
		var r: Rect2 = room["rect"]
		var col: Color = room["floor"]
		MuseumSurfaces.paint(ci, r, _theme.id, room)
		_draw_floor_gloss(ci, r, col)
		if str(room.get("dept", "")) != "" and _choke == str(room["dept"]):
			# Bottleneck room: hot rim on the floor edge, readable at a glance.
			var ring := Iso.quad(r.position, r.size)
			ring.append(ring[0])
			ci.draw_polyline(ring, UI.DANGER, 3.0)

	_paint_band(ci, level, 0)          # entrance runner
	if level == _level_of_role("queue"):
		_draw_queue_paint(ci)
	_paint_band(ci, level, 1)          # rugs, thresholds, mats

	for entry in _theme.walls:
		var w: Dictionary = entry as Dictionary
		if bool(w.get("occludes", false)):
			continue
		var at: Vector2 = Exhibits.v2(w.get("at"))
		# Prefer the storey the wall was DERIVED for. Sampling the room just inside
		# the corner works for a north or west face, whose `at` is the room's own
		# origin, but a south or east face is anchored on the room's far edge and
		# samples the space BEYOND it — so a parapet on a raised room would be
		# assigned to the ground and drawn unlifted. Sampling stays as the fallback
		# for wall data authored before the key existed.
		var wall_level: int = int(w.get("level", -1))
		if wall_level < 0:
			wall_level = _theme.level_at(at + Vector2(0.25, 0.25))
		if wall_level != level:
			continue
		if _theme.id == "celestial_conservatory" and bool(w.get("glass",false)):
			MuseumArchitecture.glasshouse(ci,at,Exhibits.f(w.get("len"),1.0),
				str(w.get("axis","x")),Exhibits.f(w.get("h"),Iso.WALL_H))
			continue
		var draw_wall: Callable = Iso.glass_wall if bool(w.get("glass", false)) \
			else Iso.wall
		draw_wall.call(ci, at, Exhibits.f(w.get("len"), 1.0),
			str(w.get("axis", "x")), Exhibits.c(w.get("col"), UI.WALL_BROWN),
			Exhibits.f(w.get("h"), Iso.WALL_H))
		MuseumArchitecture.wall_details(ci, _theme.id, at, Exhibits.f(w.get("len"), 1.0),
			str(w.get("axis", "x")), Exhibits.f(w.get("h"), Iso.WALL_H), bool(w.get("glass", false)))

	_paint_band(ci, level, 2)          # wall art, signage, wall-mounted exhibits
	_paint_band(ci, level, 3)          # bunting, strung above the tallest wall

## Restrained reflected-light bands make sealed stone floors read as polished
## without placing a full-screen effect over visitors and furniture.
func _draw_floor_gloss(ci: CanvasItem, room: Rect2, floor_col: Color) -> void:
	if room.size.x < 2.0 or room.size.y < 2.0:
		return
	var inset_x := minf(0.70, room.size.x * 0.12)
	var strip_h := clampf(room.size.y * 0.055, 0.12, 0.30)
	var highlight := floor_col.lightened(0.72)
	highlight.a = 0.15
	for fraction in [0.24, 0.66]:
		var y := room.position.y + room.size.y * float(fraction)
		Iso.floor_patch(ci, Vector2(room.position.x + inset_x, y),
			Vector2(room.size.x - inset_x * 2.0, strip_h), highlight)
	# A thin cool reflection keeps pale floors from reading as a flat white fill.
	var cool := Color(0.72, 0.91, 1.0, 0.09)
	Iso.floor_patch(ci, room.position + Vector2(inset_x * 1.5, room.size.y * 0.46),
		Vector2(maxf(0.3, room.size.x * 0.42), strip_h * 0.55), cool)

## Rooms standing on a storey. A stair belongs to its LOWER end so its ramp is
## drawn once, on the floor it climbs away from.
func _rooms_on(level: int) -> Array:
	var out: Array = []
	for entry in _theme.rooms:
		var room: Dictionary = entry as Dictionary
		if int(room.get("level", 0)) != level:
			continue
		# A stair is drawn as treads by _draw_stairs; a flat patch under them
		# would be a floor at the bottom of a staircase, which is a hole.
		if int(room.get("rise_to", level)) != level:
			continue
		if not bool(room.get("visible", true)):
			continue
		out.append(room)
	return out

func _level_of_role(role_name: String) -> int:
	var room: Dictionary = _theme.role(role_name)
	return 0 if room.is_empty() else int(room.get("level", 0))

## Painted queue lanes, one strip per window. Floor markings are how the
## reference tells the player where a line forms before anyone is standing in it,
## and deriving them here rather than listing them in the theme is what
## guarantees they land under the queue instead of beside it.
func _draw_queue_paint(ci: CanvasItem) -> void:
	var room: Dictionary = _theme.role("queue")
	if room.is_empty() or _slot_gy.is_empty():
		return
	var col: Color = (room["floor"] as Color).darkened(0.07)
	for w in _max_windows:
		var rect: Rect2 = _admissions.queue_bounds(w)
		Iso.rug(ci,rect.position,rect.size,col)

# --- Props: individual Y-sorted furniture nodes --------------------------------

## Adds one static prop. Each is its own node positioned at its grid anchor so
## Y-sort can interleave it with the moving cast; the painter works in absolute
## canvas coordinates and cancels the node offset with a draw transform.
func _add_prop(g: Vector2, painter: Callable, blocks_navigation: bool = true) -> Node2D:
	if blocks_navigation:
		_prop_g.append(g)
	var n := Node2D.new()
	n.set_meta("floor_anchor", g)
	var screen_anchor := Iso.to_screen(g)
	n.position = screen_anchor + Vector2(0.0, _theme.lift_at(g))
	n.z_index = _theme.level_at(g) * Iso.LEVEL_Z
	_canvas.add_child(n)
	n.draw.connect(func() -> void:
		# Keep the node's storey lift. Canceling n.position here canceled both
		# its grid anchor AND its elevation, leaving upper-floor props downstairs.
		n.draw_set_transform(-screen_anchor)
		painter.call(n))
	_props.append(n)
	return n

func _track_reactive_door(id: String, kind: String, spec: Dictionary,
		trigger: Vector2) -> Node2D:
	var dynamic_spec: Dictionary = spec.duplicate(true)
	var state := {"open": 0.0}
	dynamic_spec["_door_state"] = state
	var node := _add_prop(Exhibits.anchor(dynamic_spec),
		Exhibits.guarded(kind, dynamic_spec), false) # The animated doorway is passable.
	_reactive_doors.append({
		"id": id, "node": node, "state": state, "trigger": trigger,
	})
	return node

func _clear_props() -> void:
	for p in _props:
		if is_instance_valid(p):
			p.queue_free()
	_props.clear()
	_animated_exhibits.clear()
	_prop_g.clear()
	_reactive_doors.clear()

func _rebuild_props() -> void:
	var decor_key: String = ""
	if GameState.ready_flag:
		var placed: Dictionary = GameState.venue_state(GameState.current_venue).get("decor", {})
		var slots: Array = placed.keys()
		slots.sort_custom(func(a: String, b: String) -> bool: return int(a) < int(b))
		for slot in slots:
			decor_key += "/%s" % str(placed[slot])
	var evolution_key := ""
	for dept in ["gallery", "ticket", "promotions", "archive"]:
		evolution_key += "/%d" % _dept_visual_tier(dept)
	var key: String = "%s/%d%s%s" % [_theme.id, _windows_active, decor_key, evolution_key]
	if key == _props_key and not _props.is_empty():
		return
	_props_key = key
	_clear_props()
	# Seats come from the furniture, so they are rebuilt with it — decor purchases
	# and station upgrades both re-key the props, and a stale seat list would send
	# visitors to sit on furniture that is no longer there.
	_rebuild_seats()
	_build_queue_fixtures()
	for entry in _theme.exhibits:
		var e: Dictionary = entry as Dictionary
		if str(e.get("layer", "floor")) != "floor":
			continue
		var art_spec: Dictionary = e.duplicate()
		art_spec["museum_venue"] = _theme.id
		var motion: Dictionary = {}
		if _theme.id == "aurora_world" and str(e.get("id","")) == "orrery":
			motion = {"elapsed":0.0, "frame":0}
			art_spec["_motion"] = motion
		elif _theme.id == "ironwood_citadel" and str(e.get("id","")) == "siege_engine":
			motion = {"elapsed":0.0,"frame":0,"fps":8.0,"frame_count":48}
			art_spec["_motion"] = motion
		elif _theme.id == "pelagic_crown" and str(e.get("id","")) == "crown_lagoon":
			motion = {"elapsed":0.0,"frame":0,"fps":8.0,"frame_count":32}
			art_spec["_motion"] = motion
		elif _theme.id == "chronos_spire" and str(e.get("id","")) == "age_engine":
			motion = {"elapsed":0.0,"frame":0,"fps":8.0,"frame_count":32}
			art_spec["_motion"] = motion
		elif _theme.id == "empyrean_palace" and str(e.get("id","")) == "petal_fountain":
			motion = {"elapsed":0.0,"frame":0,"fps":8.0,"frame_count":32}
			art_spec["_motion"] = motion
		elif _theme.id == "infinite_museum" and str(e.get("id","")) == "orrery_of_worlds":
			motion = {"elapsed":0.0,"frame":0,"fps":8.0,"frame_count":48}
			art_spec["_motion"] = motion
		var exhibit_painter: Callable = Exhibits.guarded(str(e.get("kind", "plinth")), art_spec)
		var exhibit_node := _add_prop(Exhibits.anchor(e), _staged_exhibit(e, exhibit_painter))
		if not motion.is_empty():
			_animated_exhibits.append({"node":exhibit_node, "state":motion})
	for entry in _theme.props:
		var p: Dictionary = entry as Dictionary
		var kind := str(p.get("kind", "plinth"))
		if kind == "vault_door":
			var along := Vector2(1.0, 0.0) if str(p.get("axis", "y")) == "x" \
				else Vector2(0.0, 1.0)
			var trigger := Exhibits.v2(p.get("at")) \
				+ along * (Exhibits.f(p.get("len"), 1.4) * 0.5)
			_track_reactive_door("vault", kind, p, trigger)
		elif kind == "facade":
			_track_reactive_door("entrance", kind, p, _door_g)
		else:
			var furnished: Dictionary = p.duplicate()
			furnished["museum_venue"] = _theme.id
			_add_prop(Exhibits.anchor(p), Exhibits.guarded(kind, furnished))
	_build_section_evolution()
	_build_owned_decor()
	if not _theme.role("lobby").is_empty():
		# The canopy belongs to the surround but stands in FRONT of the facade,
		# and the surround draws behind the whole museum — so it comes across as
		# a Y-sorted prop and City only supplies the painter.
		var surround: String = _theme.surround
		var shift: Vector2 = _city.canopy_offset()
		_add_prop(_city.canopy_point(),
			func(ci: CanvasItem) -> void: City.draw_canopy(ci, surround, shift), false) # Walk under the canopy.
		var exit_spec := {
			"at": [_exit_wall_g.x - 0.72, _exit_wall_g.y],
			"len": 1.44,
			"door_at": 0.18,
			"leaf": 0.54,
			"height": 44.0,
			"col": _theme.accent("lobby").darkened(0.30),
			"door_a": Color("#47705D"),
			"door_b": Color("#3D6251"),
			"fanlight": Color("#B7D8B6"),
		}
		var exit_state := {"open": 0.0}
		exit_spec["_door_state"] = exit_state
		var exit_painter: Callable = Exhibits.guarded("facade", exit_spec)
		var exit_wall: Vector2 = _exit_wall_g
		var exit_node := _add_prop(_exit_wall_g, func(ci: CanvasItem) -> void:
			exit_painter.call(ci)
			var sign := Iso.to_screen(exit_wall) + Vector2(0.0, -54.0)
			ci.draw_rect(Rect2(sign + Vector2(-19.0, -12.0), Vector2(38.0, 15.0)),
				Color("#315F4B"))
			ci.draw_string(ThemeDB.fallback_font, sign + Vector2(-15.0, 0.0), "EXIT",
				HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color("#E7F4DA"))
		, false)
		_reactive_doors.append({
			"id": "exit", "node": exit_node, "state": exit_state,
			"trigger": _exit_door_g,
		})
	_rebuild_navigation()
	_rebuild_porter_staging()

## Bought decor must change the museum itself, not only a card in the Decor
## screen. Slots are distributed along the lobby/gallery edges so they remain
## visible without invading the authored queue and egress routes.
func _build_owned_decor() -> void:
	_decor_anchor_by_id.clear()
	_decor_spec_by_id.clear()
	if not GameState.ready_flag:
		return
	var placed: Dictionary = GameState.venue_state(GameState.current_venue).get("decor", {})
	if placed.is_empty():
		return
	var room: Dictionary = _theme.role("lobby")
	var r: Rect2 = room.get("rect", _theme.bounds) as Rect2
	# The venue's OWN anchor list wins, one entry per decor slot.
	#
	# Codex authors these per venue, sized exactly to decor_slots and spread
	# deliberately across the building's rooms and storeys — they are the
	# intended destinations, and the handoff assigns decor anchors to venue
	# ownership. Deriving positions from room rects instead meant every venue
	# ignored its own authored placement, and because the derived lists hold only
	# three or four points indexed by `slot % size`, a venue with 8 or 20 slots
	# stacked pieces on top of one another. Both together are what reads on
	# screen as "most decor is missing or in the wrong place".
	var authored: Array[Vector2] = _on_camera(_theme.decor_anchors)
	var anchors: Array[Vector2] = _theme.decor_anchors.duplicate()
	if anchors.is_empty():
		anchors = [
		r.position + Vector2(2.0, 0.85),
		r.position + Vector2(4.2, 0.80),
		r.position + Vector2(6.4, 0.85),
		r.position + Vector2(2.4, r.size.y - 0.85),
		r.position + Vector2(5.0, r.size.y - 0.80),
		r.position + Vector2(7.6, r.size.y - 0.85),
		r.position + Vector2(9.6, 0.85),
		r.position + Vector2(10.2, r.size.y - 0.85),
		]
	var slots: Array = placed.keys()
	slots.sort_custom(func(a: String, b: String) -> bool: return int(a) < int(b))
	var used_anchors: Dictionary = {}
	var occupied: Array[Rect2] = []
	for fixed in _theme.props + _theme.exhibits:
		if str(fixed.get("kind", "")) in ["rug", "patch", "banner", "hanging", "bunting", "mural", "picture", "poster"]:
			continue
		var footprint := Exhibits.solid_rect(fixed)
		if footprint.size != Vector2.ZERO:
			occupied.append(footprint.grow(0.30))
	for point in _prop_g:
		occupied.append(Rect2(point - Vector2.ONE * 0.55, Vector2.ONE * 1.1))
	for point in [_door_g, _exit_door_g, _vault_entry, _vault_drop, _porter_home]:
		occupied.append(Rect2(point - Vector2.ONE, Vector2.ONE * 2.0))
	# Keep the final approach to seats/exhibits usable as the hall fills.
	var visitor_targets: Array = _gallery_egress.duplicate()
	visitor_targets.append_array(_seats)
	visitor_targets.append_array(_seat_approaches.values())
	for spots in _browse.values():
		visitor_targets.append_array(spots)
	for station in _admissions.stations:
		visitor_targets.append(station.porter)
	for point in visitor_targets:
		occupied.append(Rect2(point - Vector2.ONE * 0.30, Vector2.ONE * 0.60))
	for w in _max_windows:
		var a: Vector2 = _admissions.point(w, Vector2(-1.1, -1.2))
		var b: Vector2 = _admissions.point(w, Vector2(1.1, _admissions.slot_lead + (_slots_per_window - 1) * _admissions.slot_gap + 0.9))
		occupied.append(Rect2(a.min(b), (b - a).abs()))
	for slot_key in slots:
		var slot: int = int(slot_key)
		var decor_id: String = str(placed[slot_key])
		var def: Dictionary = DataLoader.get_decor(decor_id)
		if def.is_empty():
			continue
		var slot_theme: String = str(def.get("slot_theme", "hall"))
		# One authored anchor per slot — never `slot % size`, so two pieces can
		# never be handed the same spot.
		var at: Vector2
		if slot < authored.size():
			at = authored[slot]
		else:
			var themed: Array[Vector2] = _decor_room_anchors(slot_theme)
			at = themed[slot % themed.size()] if not themed.is_empty() \
				else anchors[slot % anchors.size()]
		# Final collision guard, applied across BOTH sources. The authored list
		# de-duplicates internally, but a slot that overflows it falls through to
		# a derived anchor that knows nothing about what the authored ones took,
		# and two pieces sharing a tile means one is invisible behind the other.
		at = _free_anchor(at, used_anchors)
		used_anchors[_anchor_key(at)] = true
		var kind: String = _decor_kind(decor_id, slot_theme)
		var spec: Dictionary = _decor_spec(decor_id, kind, at, slot)
		at = _clear_decor_site(at, spec, occupied)
		spec = _decor_spec(decor_id, kind, at, slot)
		var footprint := Exhibits.footprint(spec)
		if footprint == Vector2.ZERO:
			footprint = Vector2(0.9, 0.7)
		occupied.append(Rect2(at, footprint).grow(0.25))
		# Remembered so a purchase reveal can find the piece that just landed
		# without recomputing the anchor chain, and so tests can assert that an
		# owned piece really did take a position on this floor.
		_decor_anchor_by_id[decor_id] = Exhibits.anchor(spec)
		spec["kind"] = kind
		spec["solid_footprint"] = _decor_blocks_nav(decor_id, kind)
		_decor_spec_by_id[decor_id] = spec
		# A purchased piece is a real part of the room. It gets a lit ownership
		# pad and participates in navigation instead of becoming a ghost prop.
		_add_prop(Exhibits.anchor(spec), _owned_decor_painter(
			decor_id, spec, Exhibits.guarded(kind, spec)),
			_decor_blocks_nav(decor_id, kind))

## Authored anchors are preferences, not permission to overlap a cabinet or
## planter. Reserve complete footprints and choose nearby real room floor.
## Ticket queues, archive work lanes, stairs and narrow entrances stay clear.
func _clear_decor_site(preferred: Vector2, spec: Dictionary, occupied: Array[Rect2]) -> Vector2:
	var footprint := Exhibits.footprint(spec)
	if footprint == Vector2.ZERO:
		footprint = Vector2(0.9, 0.7)
	var best := preferred
	var best_score := INF
	for entry in _theme.rooms:
		var room: Dictionary = entry
		if str(room.get("role", "")) in ["stairs", "elevator"] or str(room.get("dept", "")) in ["ticket", "archive"]:
			continue
		if int(room.get("rise_to", room.get("level", 0))) != int(room.get("level", 0)):
			continue
		var room_rect: Rect2 = room["rect"]
		if minf(room_rect.size.x, room_rect.size.y) < 2.5 or (str(room.get("role", "")) == "lobby" and minf(room_rect.size.x, room_rect.size.y) < 3.5):
			continue
		var bounds: Rect2 = room_rect.grow(-0.35)
		var candidates: Array[Vector2] = [preferred]
		for y in range(ceili(bounds.position.y * 2), floori((bounds.end.y - footprint.y) * 2) + 1):
			for x in range(ceili(bounds.position.x * 2), floori((bounds.end.x - footprint.x) * 2) + 1):
				candidates.append(Vector2(x, y) * 0.5)
		for at in candidates:
			var score := at.distance_squared_to(preferred)
			if score >= best_score:
				continue
			var rect := Rect2(at, footprint)
			if not bounds.encloses(rect):
				continue
			var clear := true
			for taken in occupied:
				if rect.intersects(taken):
					clear = false
					break
			if not clear:
				continue
			if score < best_score:
				best = at
				best_score = score
				if is_zero_approx(score):
					return best
	if best_score == INF:
		push_warning("No clear decor footprint in %s at %s" % [_theme.id, preferred])
	return best

## IBT's readable strength is that decorations belong to an area. Keep our
## authored venue anchors as a fallback, but distribute hall, entrance and
## garden purchases into visibly different parts of each unique floor plan.
func _decor_room_anchors(slot_theme: String) -> Array[Vector2]:
	# Candidate roles come from DecorSystem so the Decor screen's "this goes in
	# the Grand Gallery" promise and the anchor actually chosen here are read off
	# one list. They used to be two copies of the same fallback chain.
	var room: Dictionary = {}
	for want in DecorSystem.destination_roles(slot_theme):
		room = _theme.role(str(want))
		if not room.is_empty():
			break
	if room.is_empty():
		return []
	var r: Rect2 = room.get("rect", _theme.bounds) as Rect2
	var pad_x := minf(0.85, r.size.x * 0.16)
	var pad_y := minf(0.80, r.size.y * 0.18)
	# Decor belongs on the visitor-facing edge, where its silhouette and upgrade
	# plaque cannot disappear behind a back wall. Derived from the room rect for
	# EVERY venue: a per-venue table of literal coordinates here is both the
	# thing the handoff forbids and how Whispering Pines ended up with two
	# anchors off the left edge of the screen (canvas x -30 and -57), where a
	# bought piece renders nothing at all.
	if slot_theme == "garden":
		return _on_camera([
			r.position + Vector2(pad_x, r.size.y - pad_y),
			r.position + Vector2(r.size.x - pad_x, r.size.y - pad_y),
			r.position + Vector2(r.size.x * 0.5, r.size.y - pad_y),
		])
	return _on_camera([
		r.position + Vector2(pad_x, pad_y),
		r.position + Vector2(r.size.x - pad_x, pad_y),
		r.position + Vector2(pad_x, r.size.y - pad_y),
		r.position + Vector2(r.size.x - pad_x, r.size.y - pad_y),
	])

## Pull decor anchors inside the projected canvas.
##
## The projection shears x by -gy, so the visible gx window slides one tile right
## for every tile of depth: a point comfortably inside a room rect can still fall
## off the left edge of the screen. A prop out there does not warn and does not
## error — it simply never draws, which is indistinguishable to the player from a
## purchase that silently failed. This is the same class of defect the geometry
## suite was written for after the archive's vault door shipped at canvas x 750.
##
## Clamping is a floor, not a placement strategy: a venue that authors sensible
## anchors never notices it, and tests/venue/test_decor_visuals.gd fails the
## build if anything still projects outside the margin.
## Clamping is also DE-DUPLICATING, because two anchors that were off the same
## edge both clamp to that edge and would then stand inside one another — one
## piece hidden behind the other, which looks exactly like the piece that never
## spawned. A collided point is walked back along the row until it is clear.
func _on_camera(points: Array) -> Array[Vector2]:
	var out: Array[Vector2] = []
	var used: Dictionary = {}
	for entry in points:
		var p: Vector2 = entry as Vector2
		var win: Vector2 = Iso.gx_window(p.y, DECOR_EDGE_INSET)
		var g := Vector2(clampf(p.x, win.x, win.y), p.y)
		var guard: int = 0
		while used.has(_anchor_key(g)) and guard < 24:
			# Half a tile is a whole figure's width, so this separates them
			# visibly rather than nudging them into a shared silhouette.
			g.x = clampf(g.x + 0.5, win.x, win.y)
			if g.x >= win.y - 0.01:
				# Row is full at this depth; step one row forward instead.
				g = Vector2(clampf(p.x, win.x, win.y), g.y + 0.5)
				win = Iso.gx_window(g.y, DECOR_EDGE_INSET)
			guard += 1
		used[_anchor_key(g)] = true
		out.append(g)
	return out

func _anchor_key(g: Vector2) -> String:
	return "%.2f,%.2f" % [g.x, g.y]

## Nearest free tile to `g` that nothing has claimed yet, kept on camera.
## Half a tile is a whole figure's width, so a nudged piece separates visibly
## instead of merging into its neighbour's silhouette.
func _free_anchor(g: Vector2, used: Dictionary) -> Vector2:
	var out := g
	var guard: int = 0
	while used.has(_anchor_key(out)) and guard < 32:
		var win: Vector2 = Iso.gx_window(out.y, DECOR_EDGE_INSET)
		out.x += 0.5
		if out.x > win.y:
			out = Vector2(clampf(g.x, win.x, win.y), out.y + 0.5)
			var next: Vector2 = Iso.gx_window(out.y, DECOR_EDGE_INSET)
			out.x = clampf(out.x, next.x, next.y)
		guard += 1
	return out

## Short placement reveal over a piece that has just landed.
##
## Without one, a purchase in a busy room is invisible: the floor rebuilds
## between two frames and nothing tells the player WHICH of thirty props is the
## thing they just paid for. An expanding brass ring and a few rising sparks
## read instantly at gameplay zoom and are gone in under a second, so they
## cannot turn into visual noise on a floor holding a dozen pieces.
##
## A throwaway node rather than an extra pass inside the prop painter: props
## draw once and are not on a redraw clock, so animating one would mean
## invalidating the entire prop layer every frame.
func _spawn_decor_reveal(g: Vector2, installed_name: String = "") -> void:
	if _canvas == null:
		return
	var node := Node2D.new()
	node.position = Iso.to_screen(g) + Vector2(0.0, _theme.lift_at(g))
	# One band above the storey it belongs to, so the ring reads over the piece
	# without punching through the floor above it.
	node.z_index = _theme.level_at(g) * Iso.LEVEL_Z + Iso.LEVEL_Z - 1
	node.set_meta("u", 0.0)
	_canvas.add_child(node)
	node.draw.connect(func() -> void:
		var u: float = float(node.get_meta("u"))
		var fade: float = 1.0 - u
		node.draw_arc(Vector2.ZERO, lerpf(6.0, 46.0, u), 0.0, TAU, 28,
			Color(1.0, 0.85, 0.36, 0.70 * fade), 3.0, true)
		node.draw_arc(Vector2.ZERO, lerpf(2.0, 30.0, u), 0.0, TAU, 24,
			Color(1.0, 0.97, 0.80, 0.42 * fade), 1.6, true)
		for k in 5:
			var a: float = TAU * float(k) / 5.0 - PI * 0.5
			var rr: float = lerpf(4.0, 34.0, u)
			node.draw_circle(Vector2(cos(a), sin(a) * 0.55) * rr
				+ Vector2(0.0, -20.0 * u), 2.4 * fade,
				Color(1.0, 0.93, 0.62, fade)))
	if not installed_name.is_empty():
		var label := Label.new()
		label.text = installed_name + " installed"
		label.add_theme_font_size_override("font_size", 18)
		label.add_theme_color_override("font_color", Color("#FFF0BA"))
		label.add_theme_color_override("font_outline_color", Color("#242033"))
		label.add_theme_constant_override("outline_size", 8)
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		node.add_child(label)
		label.position = Vector2(-label.get_minimum_size().x * 0.5, -76)
	var tw := create_tween()
	tw.tween_method(func(u: float) -> void:
		if is_instance_valid(node):
			node.set_meta("u", u)
			node.queue_redraw(), 0.0, 1.0, 0.75)
	if not installed_name.is_empty():
		tw.tween_interval(3.0)
		tw.tween_property(node, "modulate:a", 0.0, 0.4)
	tw.tween_callback(func() -> void:
		if is_instance_valid(node):
			node.queue_free())

func _owned_decor_painter(decor_id: String, spec: Dictionary, body: Callable) -> Callable:
	var at: Vector2 = Exhibits.v2(spec.get("at"))
	var size: Vector2 = Exhibits.footprint(spec)
	if size == Vector2.ZERO:
		size = Vector2(0.9, 0.7)
	return func(ci: CanvasItem) -> void:
		Iso.rug(ci, at - Vector2(0.18, 0.16), size + Vector2(0.36, 0.32),
			Color(1.0, 0.77, 0.18, 0.24))
		body.call(ci)
		var gleam := Iso.to_screen(at + Vector2(size.x * 0.5, size.y * 0.15))
		ci.draw_circle(gleam, 2.2, Color(1.0, 0.92, 0.55, 0.78))

func _dept_visual_tier(dept: String) -> int:
	if not GameState.ready_flag:
		return 0
	var cap: int = maxi(int(DataLoader.get_venue(GameState.current_venue)
		.get("track_level_cap", 15)), 1)
	var peak: int = 0
	for track in ["speed", "value", "staff"]:
		peak = maxi(peak, GameState.dept_level(GameState.current_venue, dept, track))
	return clampi(int(floor(float(peak) / float(cap) * 4.0)), 0, 4)

## Each functional section gains authored-looking finishing layers as its
## equipment advances. These are shared rules applied to every venue's unique
## room rectangles, so progression changes the building rather than only a bar.
func _build_section_evolution() -> void:
	for dept in ["gallery", "ticket", "promotions", "archive"]:
		var tier := _dept_visual_tier(dept)
		if tier <= 0:
			continue
		var room: Dictionary = _theme.by_dept.get(dept, {})
		if room.is_empty():
			continue
		var r: Rect2 = room["rect"]
		var accent: Color = _theme.accent(dept)
		# Overhead banners add height and colour without becoming obstacles.
		_add_prop(r.position + Vector2(r.size.x * 0.5, 0.35),
			Exhibits.painter("banner", {
				"from": r.position + Vector2(r.size.x * 0.30, 0.35),
				"to": r.position + Vector2(r.size.x * 0.70, 0.35),
				"col": accent.lightened(0.12),
			}), false)
		if tier >= 2:
			var plant_at := _section_planter_site(r)
			if plant_at.is_finite():
				_add_prop(plant_at, Exhibits.painter("planter", {
					"at": plant_at, "size": Vector2(0.72, 0.60), "museum_venue": _theme.id,
					"col": accent.darkened(0.22), "leaf": Color("#64B96A"),
				}))
		if tier >= 3:
			var glow_at := r.position + Vector2(r.size.x * 0.5 - 0.8, r.size.y - 0.55)
			_add_prop(glow_at, Exhibits.painter("rug", {
				"at": glow_at, "size": Vector2(1.6, 0.55),
				"col": accent.darkened(0.10),
			}), false)

## Section upgrades must never grow a planter into an operational docking
## point. This also protects already upgraded saves when decor is rebuilt.
func _section_planter_site(r: Rect2) -> Vector2:
	var required: Array[Vector2] = [_door_g, _exit_door_g, _vault_entry, _vault_drop, _porter_home]
	for station in _admissions.stations:
		required.append(station.porter)
	for w in _max_windows:
		for slot in _slots_per_window:
			required.append(_admissions.slot(w, slot))
	for offset in [Vector2(r.size.x - 0.72, r.size.y - 0.72), Vector2(0.72, r.size.y - 0.72), Vector2(r.size.x - 0.72, 0.72), Vector2(0.72, 0.72)]:
		var at: Vector2 = r.position + offset
		var clear := true
		for point in required:
			if point.distance_to(at) < 0.90:
				clear = false
				break
		if clear:
			return at
	return Vector2(INF, INF)

## The authored visual block for a piece, or {} for one that predates the per-id
## visual pass. Single lookup shared by kind, spec and navigation, so those three
## can never disagree about what a piece is.
func _decor_visual(decor_id: String) -> Dictionary:
	var v: Variant = DataLoader.get_decor(decor_id).get("visual", {})
	return (v as Dictionary) if v is Dictionary else {}

## Does this piece occupy floor a walker has to route around?
##
## Flat and overhead kinds do not: a rug, a hung chandelier and a walk-through
## gate are things the crowd passes over or under. This is not cosmetic — a
## blocking prop dropped across a corridor can strand the queue.
func _decor_blocks_nav(decor_id: String, kind: String) -> bool:
	var v: Dictionary = _decor_visual(decor_id)
	if v.has("blocks_nav"):
		return bool(v["blocks_nav"])
	return kind not in ["banner", "rug", "patch", "hanging", "bunting",
		"picture", "poster", "notice", "mural", "porthole"]

func _decor_kind(decor_id: String, theme: String) -> String:
	# An authored kind always wins. Every sellable id has one, and
	# tests/meta/test_decor_visuals.gd fails the build if one stops having it —
	# falling through to the substring guesswork below is what made five
	# different products render as the identical default bench.
	var v: Dictionary = _decor_visual(decor_id)
	if v.has("kind"):
		return str(v["kind"])
	if "bench" in decor_id or "lounge" in decor_id or "nook" in decor_id or "terrace" in decor_id:
		return "bench"
	if "banner" in decor_id or "totem" in decor_id:
		return "banner"
	if "planter" in decor_id or "topiary" in decor_id or "lawn" in decor_id:
		return "planter"
	if "rope" in decor_id:
		return "rope_line"
	if "mosaic" in decor_id:
		return "rug"
	if "case" in decor_id or "mask" in decor_id:
		return "vitrine"
	if "statue" in decor_id or "bust" in decor_id or "obelisk" in decor_id or "fountain" in decor_id:
		return "statue"
	return "planter" if theme == "garden" else "plinth"

## Kind defaults, then the piece's own authored fields on top.
##
## The defaults exist only as a floor for an unauthored id. What makes a Sphinx
## look like a Sphinx and not like a Marble Bust is the `visual` block in
## data/decor.json, written in each painter's real field vocabulary — the old
## code handed `_bench` a `size` and a `wood` colour, neither of which `_bench`
## reads, so every bench in the game drew with stock length and stock timber.
func _decor_spec(decor_id: String, kind: String, at: Vector2, slot: int) -> Dictionary:
	var spec: Dictionary = _decor_kind_defaults(kind, at, slot)
	var visual: Dictionary = _decor_visual(decor_id)
	for key in visual.keys():
		# `kind` selects the painter, `span` is consumed below, `blocks_nav` is
		# navigation rather than paint. Everything else is a painter field and
		# goes through the theme resolver, so a piece may tint itself to the
		# building with an "@trim" token instead of a literal colour.
		if key in ["kind", "span", "blocks_nav"]:
			continue
		spec[key] = _theme.resolve(visual[key])
	spec["at"] = at
	# Path kinds are positioned relative to their anchor, so endpoints are
	# derived here rather than authored as absolute grid coordinates that would
	# be wrong in every venue but the one they were measured in.
	if kind == "rope_line" and not spec.has("points"):
		var span: float = float(visual.get("span", 1.8))
		spec["from"] = at - Vector2(span * 0.5, 0.0)
		spec["to"] = at + Vector2(span * 0.5, 0.0)
	return spec

func _decor_kind_defaults(kind: String, at: Vector2, slot: int) -> Dictionary:
	var accent: Color = _theme.col("trim", UI.BRASS)
	var spec: Dictionary = {"at": at, "col": accent, "stone": accent.lightened(0.35)}
	match kind:
		"bench":
			spec["size"] = Vector2(1.7, 0.55)
			spec["wood"] = Color("#8A5B38")
		"planter":
			spec["size"] = Vector2(0.8, 0.65)
			spec["leaf"] = Color("#4F8A5B").lightened(float(slot % 3) * 0.06)
		"rope_line":
			spec["from"] = at - Vector2(0.9, 0.0)
			spec["to"] = at + Vector2(0.9, 0.0)
		"rug":
			spec["size"] = Vector2(1.8, 1.1)
			spec["col"] = _theme.accent("gallery").darkened(0.12)
		"vitrine":
			spec["size"] = Vector2(1.0, 0.75)
			spec["glass"] = Color(0.65, 0.88, 0.94, 0.48)
		"statue":
			spec["size"] = Vector2(0.9, 0.7)
			spec["figure"] = accent.lightened(0.55)
		"banner":
			spec["from"] = at - Vector2(0.7, 0.0)
			spec["to"] = at + Vector2(0.7, 0.0)
			spec["col"] = _theme.accent("promotions").darkened(0.12)
		_:
			spec["size"] = Vector2(0.9, 0.7)
	return spec

## Presentation shell shared by floor exhibits: a lit footprint, focused key
## light and a real museum label. The underlying exhibit kinds still own their
## silhouettes; this makes them read as curated displays rather than loose props.
func _staged_exhibit(raw: Dictionary, body: Callable) -> Callable:
	var spec: Dictionary = raw.duplicate(true)
	var at: Vector2 = Exhibits.v2(spec.get("at"))
	var size: Vector2 = Exhibits.v2(spec.get("size"), Vector2.ONE)
	var anchor: Vector2 = Exhibits.anchor(spec)
	var label: String = str(spec.get("id", "EXHIBIT")).replace("_", " ").to_upper()
	if label.length() > 13:
		label = label.left(13)
	var accent: Color = _theme.accent("gallery")
	var hero: bool = str(spec.get("kind", "")) in ["skeleton", "casket", "statue"]
	return func(ci: CanvasItem) -> void:
		# Low illuminated stage inset: enough separation to read from the game
		# camera without turning every display into another bulky plinth.
		Iso.rug(ci, at - Vector2(0.12, 0.12), size + Vector2(0.24, 0.24),
			Color(accent.r, accent.g, accent.b, 0.10 if hero else 0.065))
		var focus := Iso.to_screen(anchor)
		var beam_top := focus + Vector2(-16.0, -88.0 if hero else -70.0)
		Iso.fill(ci, PackedVector2Array([
			beam_top, beam_top + Vector2(32.0, 0.0),
			focus + Vector2(28.0, 8.0), focus + Vector2(-28.0, 8.0)]),
			Color(1.0, 0.82, 0.46, 0.045 if hero else 0.028))
		body.call(ci)
		# Unboxed accession caption at the visitor-facing corner. A dark offset
		# keeps it readable on every floor hue without filling the gallery with
		# speech-bubble-shaped cards.
		var plaque := Iso.to_screen(at + Vector2(size.x + 0.10, size.y + 0.08))
		# The small brass tick reads as a museum accession marker without adding
		# another line of text over the crowd.
		ci.draw_line(plaque + Vector2(-5.0, 0.0), plaque + Vector2(5.0, 0.0),
			Color("#E8B83F"), 2.0, true)

## Quarter-tile navigation is intentionally presentation-only. The economic FSM
## still decides where a visitor goes; this layer decides how they get there
## without walking through a desk, exhibit or vending machine.
## True inside a room that RAMPS between storeys — the only legal way to change
## level. lift_at() interpolates height across these, so a walker on one climbs
## rather than teleports.
## Seats standing on cells navigation has sealed.
##
## A seat inside a solid cell cannot be walked to, so every visitor that claims it
## walks at it, never arrives, and stacks up with the ones behind — while the
## bench looks perfectly empty. Reported rather than assumed, because the first
## fix for that symptom addressed the wrong cause.
func _blocked_seats() -> Array[Vector2]:
	var bad: Array[Vector2] = []
	for s in _seats:
		var id: Vector2i = _nav_id(s)
		if _nav.is_in_boundsv(id) and _nav.is_point_solid(id):
			bad.append(s)
	return bad

func _is_stair_at(g: Vector2) -> bool:
	var room: Dictionary = _theme.room_at(g)
	if room.is_empty():
		return false
	var level: int = int(room.get("level", 0))
	return int(room.get("rise_to", level)) != level

func _rebuild_navigation() -> void:
	_lobby_standing_geometry.clear()
	_nav = AStarGrid2D.new()
	# Forecourt seats are on the museum plinth, not necessarily inside the room
	# union. Excluding that apron stranded their target cells and caused the
	# empty-path fallback to cut directly through raised-room cliffs.
	var apron: float = Exhibits.f(_theme.shell.get("inset"), 0.35) + 0.6
	var b: Rect2 = _theme.bounds.grow(apron)
	var lo := Vector2i(floori(b.position.x * 4.0) - 6, floori(b.position.y * 4.0) - 6)
	var hi := Vector2i(ceili(b.end.x * 4.0) + 6, ceili(b.end.y * 4.0) + 6)
	_nav.region = Rect2i(lo, hi - lo + Vector2i.ONE)
	_nav.cell_size = Vector2(0.25, 0.25)
	_nav.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	_nav.update()

	# Keep routes inside the venue's bounding mass. Individual room partitions
	# are visual shells with authored openings, but their raster union is not a
	# watertight navmesh (half-tile rounding can close a valid doorway). Props
	# are the collision bodies this grid is responsible for.
	for y in range(lo.y, hi.y + 1):
		for x in range(lo.x, hi.x + 1):
			var g := Vector2(float(x) * 0.25, float(y) * 0.25)
			if not b.has_point(g):
				_nav.set_point_solid(Vector2i(x, y), true)
			else:
				var room: Dictionary = _theme.room_at(g)
				if bool(room.get("nav_blocked", false)):
					_nav.set_point_solid(Vector2i(x, y), true)

	# --- storey edges -------------------------------------------------------
	#
	# The grid is FLAT. Storeys are a rendering concept — lift_at() raises a
	# figure and level_at() picks its depth band — and A* knows nothing about
	# them. So without this pass a walker routes straight from a ground-floor
	# room into a raised one and is silently lifted mid-stride: it reads as
	# people walking up the outside of a wall, ignoring the staircase standing
	# right next to them, and as porters stepping onto the vault platform
	# instead of climbing to it.
	#
	# This used to be handled by one hardcoded Whispering Pines special case
	# sealing that venue's gallery edge, which is why the problem was invisible
	# there and present everywhere else — most obviously in the multi-storey
	# late venues.
	#
	# The general rule: a cell may not be walked into from a cell on a DIFFERENT
	# storey unless one of the two is inside a stair room (a room whose rise_to
	# differs from its level — the ramp lift_at() interpolates across). Sealing
	# the higher side turns every unmanaged level change into a cliff, leaving
	# authored stairs as the only legal transition.
	# SAFETY: only seal a storey that a stair can actually reach. A raised room
	# with no authored stair is a venue-geometry gap, and sealing it would strand
	# whoever has business up there — the porters' vault run is exactly that
	# case. A walker who levitates is a visual bug; a walker who can never arrive
	# is a broken economy, so an unreachable level is left open and reported.
	var stair_levels: Dictionary = {}
	for entry in _theme.rooms:
		var rm: Dictionary = entry as Dictionary
		var lv: int = int(rm.get("level", 0))
		var to: int = int(rm.get("rise_to", lv))
		if to != lv:
			stair_levels[lv] = true
			stair_levels[to] = true
	for entry in _theme.rooms:
		var rm2: Dictionary = entry as Dictionary
		var lv2: int = int(rm2.get("level", 0))
		if lv2 > 0 and not stair_levels.has(lv2):
			push_warning("VenueFloor '%s': room '%s' sits on storey %d with no stair reaching it; leaving its edges open so nobody is stranded."
				% [_theme.id, str(rm2.get("id", rm2.get("role", "?"))), lv2])

	for y in range(lo.y, hi.y + 1):
		for x in range(lo.x, hi.x + 1):
			var cell := Vector2i(x, y)
			if _nav.is_point_solid(cell):
				continue
			var g := Vector2(float(x) * 0.25, float(y) * 0.25)
			if _is_stair_at(g):
				continue  # the stair itself is the legal ramp
			if not stair_levels.has(_theme.level_at(g)):
				continue  # unreachable by stair: do not wall it off
			var here: int = _theme.level_at(g)
			for step in [Vector2(0.25, 0.0), Vector2(-0.25, 0.0),
					Vector2(0.0, 0.25), Vector2(0.0, -0.25)]:
				var n: Vector2 = g + step
				if not b.has_point(n) or _is_stair_at(n):
					continue
				if _theme.level_at(n) < here:
					# `here` is the raised side of an unmanaged drop. Seal it.
					_nav.set_point_solid(cell, true)
					break

	# A stair is not a doorway along its entire side. Allow only transitions
	# whose elevation difference fits one grid step of that stair's slope.
	# Otherwise a route can enter halfway up and lift a visitor in one frame.
	for entry in _theme.rooms:
		var stair: Dictionary = entry
		var from_level := int(stair.get("level", 0))
		var to_level := int(stair.get("rise_to", from_level))
		if from_level == to_level:
			continue
		var rect: Rect2 = stair["rect"]
		var along_x := str(stair.get("stair_axis", "x" if rect.size.x >= rect.size.y else "y")) == "x"
		var run := rect.size.x if along_x else rect.size.y
		var step_lift := absf(Iso.level_lift(to_level) - Iso.level_lift(from_level)) * .25 / maxf(run, .25) + .5
		for y in range(floori(rect.position.y * 4), ceili(rect.end.y * 4)):
			for x in range(floori(rect.position.x * 4), ceili(rect.end.x * 4)):
				var g := Vector2(x, y) * .25
				if not rect.has_point(g):
					continue
				for step in [Vector2(.25, 0), Vector2(-.25, 0), Vector2(0, .25), Vector2(0, -.25)]:
					var neighbor: Vector2 = g + step
					var along_flight: bool = (along_x and is_zero_approx(step.y)) or (not along_x and is_zero_approx(step.x))
					var allowed := step_lift if along_flight else .5
					if not rect.has_point(neighbor) and absf(_theme.lift_at(g) - _theme.lift_at(neighbor)) > allowed:
						_nav.set_point_solid(Vector2i(x, y), true)
						break

	# Every museum respects its visible walls and authored door gaps.
	for wall_entry in _theme.walls:
		var wall: Dictionary = wall_entry as Dictionary
		var at := Exhibits.v2(wall.get("at"))
		var axis := str(wall.get("axis", "x"))
		var length := Exhibits.f(wall.get("len"), 0.0)
		var steps := ceili(length * 4.0)
		for step in range(steps + 1):
			var along := minf(float(step) * 0.25, length)
			var wall_g := at + (
				Vector2(along, 0.0) if axis == "x" else Vector2(0.0, along))
			# Platform support walls below a raised walking surface do not
			# block that surface. Rails and partitions at foot height do.
			var base := float(wall.get("level",0)) * Iso.LEVEL_H
			var foot := -_theme.lift_at(wall_g)
			if foot >= base + Exhibits.f(wall.get("h"),Iso.WALL_H) - .5 or foot + 40 < base:
				continue
			var wall_id := _nav_id(wall_g)
			# One cell of perpendicular clearance keeps a character's body
			# and not just its centre point from clipping the partition.
			for offset in range(-1, 2):
				var id := wall_id + (
					Vector2i(0, offset) if axis == "x" else Vector2i(offset, 0))
				if _nav.region.has_point(id):
					_nav.set_point_solid(id, true)

	# Remember structurally legal access before furniture blocks its footprint.
	# A short bench's central seat otherwise becomes one isolated open cell.
	var seat_access: Array[Vector2i] = []
	for seat in _seats:
		var approach: Vector2 = _seat_approaches.get(seat, seat)
		for step in range(5):
			var id := _nav_id(seat.lerp(approach, float(step) / 4.0))
			if _nav.is_in_boundsv(id) and not _nav.is_point_solid(id):
				seat_access.append(id)

	# Reserve a roughly half-tile body around each structure. Quarter-tile cells
	# retain viable paths through the authored doorways that a coarser expanded
	# grid accidentally sealed.
	for prop in _prop_g:
		var center := _nav_id(prop)
		for y in range(center.y - 2, center.y + 3):
			for x in range(center.x - 2, center.x + 3):
				var id := Vector2i(x, y)
				var g := Vector2(id) * 0.25
				if _nav.region.has_point(id) and g.distance_to(prop) < 0.5:
					_nav.set_point_solid(id, true)

	# A bench's sorting anchor is deliberately near one end of its backrest.
	# Its anchor disc cannot stand in for the full bench: walkers otherwise
	# cross the empty second seat. Preserve only the authored seat approaches
	# below, so sitting remains possible without opening a through-route.
	for spec in _theme.props:
		if str(spec.get("kind",""))!="bench":continue
		var occupied:=Exhibits.solid_rect(spec).grow(.20)
		for y in range(floori(occupied.position.y*4),ceili(occupied.end.y*4)+1):
			for x in range(floori(occupied.position.x*4),ceili(occupied.end.x*4)+1):
				var id:=Vector2i(x,y)
				if _nav.region.has_point(id) and occupied.has_point(Vector2(id)*.25):_nav.set_point_solid(id,true)

	# Authored furnishings and ground exhibits can reserve complete footprints.
	# Seat approaches may open their bench, never a neighboring desk or tank.
	var solid_furniture_cells: Dictionary = {}
	for spec in _theme.props+_theme.exhibits+_decor_spec_by_id.values():
		if not bool(spec.get("solid_footprint",false)):continue
		var occupied := Exhibits.solid_rect(spec).grow(.20)
		for y in range(floori(occupied.position.y*4),ceili(occupied.end.y*4)+1):
			for x in range(floori(occupied.position.x*4),ceili(occupied.end.x*4)+1):
				var id := Vector2i(x,y)
				if _nav.region.has_point(id) and occupied.has_point(Vector2(id)*.25):
					_nav.set_point_solid(id,true)
					solid_furniture_cells[id]=true

	# Rope banks block their visible runs, not a phantom body at the Y-sort
	# anchor half a tile beyond them. Leave the open head and tail walkable.
	for w in _windows_active:
		for side in [-_lane_offset, _lane_offset]:
			var a := _nav_id(_admissions.rope(w,float(side),0))
			var b_ := _nav_id(_admissions.rope(w,float(side),_slots_per_window-1))
			var steps := maxi(absi(b_.x-a.x),absi(b_.y-a.y))
			for k in steps+1:
				var id := Vector2i(Vector2(a).lerp(Vector2(b_),float(k)/maxi(steps,1)).round())
				if _nav.region.has_point(id):_nav.set_point_solid(id, true)

	# Open only the approaches that were legal before furniture placement.
	# Never reopen a platform cliff or a wall merely because a seat is nearby.
	for sid in seat_access:
		if not solid_furniture_cells.has(sid):_nav.set_point_solid(sid, false)
	# Structural solidity changed in place (same grid object): drop memoized
	# porter fits built against the old walls/furniture. (Grid replacement is
	# caught separately by the layout's nav-identity pin.)
	_porter_layout.clear_fit_cache()
	if OS.has_environment("GRAND_EXHIBIT_SEAT_DEBUG"):
		print("[SEATDBG] seats=%d blocked_before_reopen=%d"
			% [_seats.size(), _blocked_seats().size()])

## Where the cast has bunched up, and what each of them thinks it is doing.
##
## "They clump at the benches" can mean three unrelated things — visitors queued
## for a seat, the lobby overflow crowd standing near one, or browse spots packed
## too close — and a screenshot cannot tell them apart. This can.
func clump_report(radius: float = 1.2) -> String:
	var out: Array[String] = []
	var seen := {}
	for i in _visitors.size():
		if seen.has(i):
			continue
		var group: Array[int] = [i]
		for j in range(i + 1, _visitors.size()):
			if _visitors[i].pos.distance_to(_visitors[j].pos) <= radius:
				group.append(j)
		if group.size() < 3:
			continue
		var states := {}
		for k in group:
			seen[k] = true
			var st: String = _visitors[k].state
			states[st] = int(states.get(st, 0)) + 1
		out.append("%d at %.1f,%.1f %s" % [group.size(),
			_visitors[i].pos.x, _visitors[i].pos.y, str(states)])
	return "; ".join(out) if not out.is_empty() else "(no clumps)"

func _nav_id(g: Vector2) -> Vector2i:
	return Vector2i(roundi(g.x * 4.0), roundi(g.y * 4.0))

## Long indoor segments must have a route. An empty A* result must never
## become permission to walk straight through a wall or off a raised floor.
## Quarter-tile waypoints already supplied by A* need no second search.
func _prepare_indoor_segment(from: Vector2, to: Vector2, path: Array) -> bool:
	if from.distance_to(to) <= .5 or _nav == null:
		return true
	var apron := Exhibits.f(_theme.shell.get("inset"), .35) + .6
	var walk_bounds: Rect2 = _theme.bounds.grow(apron)
	if not walk_bounds.has_point(from) or not walk_bounds.has_point(to):
		return true # Street/crosswalk approaches have their own authored routes.
	var route := _nav_path(from, to)
	if route.is_empty():
		if not _nav_ids(from, to).is_empty():return true # Adjacent cells need no intermediate waypoint.
		var key := str(_nav_id(to))
		if not _unreachable_targets.has(key):
			_unreachable_targets[key] = true
			push_warning("Venue %s has no indoor route from %s to %s" % [_theme.id,from,to])
		return false
	for i in range(route.size()-1, -1, -1):path.push_front(route[i])
	return true

## Intermediate waypoints only; the caller retains the exact authored target.
func _nav_ids(from: Vector2, to: Vector2) -> Array[Vector2i]:
	if _nav == null:
		return []
	var a := _nav_id(from)
	var b := _nav_id(to)
	if not _nav.region.has_point(a) or not _nav.region.has_point(b):
		return []
	var a_solid: bool = _nav.is_point_solid(a)
	var b_solid: bool = _nav.is_point_solid(b)
	_nav.set_point_solid(a, false)
	_nav.set_point_solid(b, false)
	var ids: Array[Vector2i] = _nav.get_id_path(a, b)
	_nav.set_point_solid(a, a_solid)
	_nav.set_point_solid(b, b_solid)
	return ids

func _nav_path(from: Vector2, to: Vector2) -> Array:
	var ids := _nav_ids(from, to)
	var out: Array = []
	for i in range(1, maxi(ids.size() - 1, 1)):
		out.append(Vector2(ids[i]) * 0.25)
	return out

## Browse points are suggestions, not permission to stand inside a display.
## Snap them to the nearest free quarter-tile whenever authored furniture,
## purchased decor, or an evolution tier occupies the original point.
func _safe_nav_spot(target: Vector2) -> Vector2:
	if _nav == null:
		return target
	var center := _nav_id(target)
	if _nav.region.has_point(center) and not _nav.is_point_solid(center):
		return target
	for radius in range(1, 7):
		for y in range(center.y - radius, center.y + radius + 1):
			for x in range(center.x - radius, center.x + radius + 1):
				if abs(x - center.x) != radius and abs(y - center.y) != radius:
					continue
				var id := Vector2i(x, y)
				if _nav.region.has_point(id) and not _nav.is_point_solid(id):
					return Vector2(id) * 0.25
	return target

## Counters and rope lanes for the queue room, built from the same numbers the
## FSM walks. One counter per STAFFED window, so upgrading the department opens a
## window that is visibly there.
func _build_queue_fixtures() -> void:
	var room: Dictionary = _theme.role("queue")
	if room.is_empty():
		return
	var q: Dictionary = room.get("queue", {}) as Dictionary
	var size: Vector2 = Exhibits.v2(q.get("counter_size"), Vector2(1.7, 0.6))
	var accent: Color = _theme.accent(str(room.get("dept", "")))
	for w in _windows_active:
		var center: Vector2 = _admissions.point(w)
		_add_prop(center, Exhibits.painter("counter", {
			"at": center-size*.5, "size": size, "rot":_admissions.rotation_degrees(w),
			"height": Exhibits.f(q.get("counter_h"), 21.0),
			"col": accent.darkened(0.06), "trim": _theme.col("trim", UI.BRASS),
			"label": str(w + 1), "museum_venue": _theme.id,
		}))
		_add_queue_lane(w, -_lane_offset)
		_add_queue_lane(w, _lane_offset)

## One rope line as ONE node, instead of one node per post.
##
## The queues used to build forty separate stanchion nodes, which was about a
## sixth of the whole floor's draw-call budget spent on posts. Merging a lane
## into a single canvas item only stays honest if the merged node sorts correctly
## against the people standing in it, and here it does exactly: the far lane
## belongs BEHIND every visitor at that window, so it anchors at the back of the
## queue, and the near lane belongs in front of all of them, so it anchors at the
## front. There is no depth at which a lane and its queue interleave.
func _add_queue_lane(w: int, side: float) -> void:
	var first := _admissions.rope(w,side,0)
	var last := _admissions.rope(w,side,_slots_per_window-1)
	var anchor: Vector2 = first-_admissions.stations[w].front*.45
	if side > 0.0:anchor = last+_admissions.stations[w].front*.45
	# Which rail is nearer changes when the counter turns. Use projected depth.
	var side_depth: float = (_admissions.stations[w].right.x+_admissions.stations[w].right.y)*side
	if side_depth > 0.0:anchor = last+_admissions.stations[w].front*.45
	else:anchor = first-_admissions.stations[w].front*.45
	var pts: Array = []
	for j in _slots_per_window:pts.append(_admissions.rope(w,side,j))
	_add_prop(anchor, Exhibits.painter("rope_line", {
		"points": pts, "post_h": 26.0, "rope_h": 25.0, "sag": 6.0, "segments": 9,
		"width": 2.0, "gloss": true,
		"rope": _theme.col("rope", UI.ROPE_RED), "post": _theme.col("shell", UI.WALL_BROWN),
		"knob": _theme.col("trim", UI.BRASS),
	}), false) # Its sort anchor is not a physical obstacle; rasterize the ropes below.

# --- Dynamic layers -------------------------------------------------------------

func _draw_stacks() -> void:
	# Ticket-stub bundles piling beside each counter; an archive choke lets them
	# overflow, which is the visual tell that transport is the bottleneck.
	var cap: int = MAX_STACK_VIS * 2 if _choke == "archive" else MAX_STACK_VIS
	for w in _windows_active:
		var n: int = mini(_stacks[w], cap)
		var anchor: Vector2 = _lifted(_admissions.point(w,Vector2(1,0))) \
			- _stacks_layer.position
		for i in n:
			var y: float = anchor.y - 18.0 - float(i) * 3.2
			Iso.fill(_stacks_layer, PackedVector2Array([
				Vector2(anchor.x - 9, y), Vector2(anchor.x, y - 4.5),
				Vector2(anchor.x + 9, y), Vector2(anchor.x, y + 4.5)]),
				UI.PANEL if i % 2 == 0 else UI.FLOOR_CREAM)

func _draw_pile() -> void:
	# Vault hoard: stacked coin discs whose height tracks lifetime earnings.
	var rows: int = clampi(int(_pile_height / 7.0), 1, 11)
	var flash: Color = UI.BRASS.lightened(_pile_flash * 0.45)
	for i in rows:
		var wobble: float = float(i % 2) * 3.0
		var y: float = -float(i) * 6.0
		var rad: float = 22.0 - float(i) * 1.4
		Iso.fill(_pile_layer, PackedVector2Array([
			Vector2(-rad + wobble, y), Vector2(wobble, y - rad * 0.5),
			Vector2(rad + wobble, y), Vector2(wobble, y + rad * 0.5)]),
			flash.darkened(0.10 if i % 2 == 0 else 0.0))
	# A porter delivery produces a short, contained coin glint—not a dialogue
	# bubble—so the player can see that transport reached the vault.
	if _pile_flash > 0.02:
		var sparkle: Color = UI.BRASS.lightened(0.42)
		sparkle.a = _pile_flash
		for i in 6:
			var angle := -PI * 0.92 + float(i) * PI * 0.37
			var inner := Vector2(cos(angle) * 27.0, sin(angle) * 15.0 - float(rows) * 3.0)
			var outer := inner + Vector2(cos(angle) * 9.0, sin(angle) * 6.0)
			_pile_layer.draw_line(inner, outer, sparkle, 2.0)

func _draw_labels() -> void:
	# Section identity now comes from architecture, floor colour and the upgrade
	# sheet. Floating room names duplicated that information over NPC faces.
	pass

## Room name on a floating plaque, on its own layer: an earlier pass drew labels
## onto the floor, where the cast walked through them.
##
## Plaque points are theme data, placed by hand over a piece of FURNITURE — a
## plinth, a shelf bank, a desk, a counter — because furniture is the only floor
## the cast never stands on. The old rule (16% / 84% of each room) put the ticket
## plaque in the queue and the archive plaque on the porters' home tile.
func _draw_plaque(center: Vector2, title: String, accent: Color) -> void:
	var w: float = float(_font.get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x)
	var pos := Vector2(center.x - w * 0.5, center.y + 4.0)
	_labels_layer.draw_string(_font, pos + Vector2(1.4, 1.6), title,
		HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.04, 0.025, 0.08, 0.94))
	_labels_layer.draw_string(_font, pos, title,
		HORIZONTAL_ALIGNMENT_LEFT, -1, 11, accent.lightened(0.62))
