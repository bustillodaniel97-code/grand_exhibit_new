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

const UI := preload("res://scripts/ui/ui_kit.gd")
const Character := preload("res://scenes/venue/floor/character.gd")
const Iso := preload("res://scenes/venue/floor/iso.gd")
const City := preload("res://scenes/venue/floor/city.gd")
const Exhibits := preload("res://scenes/venue/floor/exhibits.gd")

const FLOOR := Vector2(720, 760)      # logical canvas the diorama is fitted into

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
		walls = resolve(raw.get("walls", [])) as Array
		exhibits = resolve(raw.get("exhibits", [])) as Array
		props = resolve(raw.get("props", [])) as Array
		dressing = resolve(raw.get("dressing", {})) as Dictionary

	func _build_rooms(raw_rooms: Array) -> void:
		var cream: Color = palette.get("floor", UI.FLOOR_CREAM)
		for entry in raw_rooms:
			if not (entry is Dictionary):
				continue
			var room: Dictionary = (entry as Dictionary).duplicate(true)
			var r: Array = room.get("rect", [0, 0, 1, 1]) as Array
			room["rect"] = Rect2(float(r[0]), float(r[1]), float(r[2]), float(r[3]))
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
var _canvas: Node2D
var _city: Node2D              # the block outside the museum, behind the ground
var _ground: Node2D            # floors + walls, always behind everything
var _stacks_layer: Node2D      # window ticket-stub stacks
var _pile_layer: Node2D        # vault pile
var _labels_layer: Node2D      # room plaques, always above the cast
var _props: Array = []         # Y-sorted static furniture nodes
var _prop_g: Array[Vector2] = []   # their grid anchors, for the geometry suite
var _ground_paint: Array = []      # cached dressing painters, banded by draw order
var _font: Font

# --- Layout, derived from the theme's room rects -------------------------------
var _tap_zones: Dictionary = {}          # dept id -> Rect2
var _door_g := Vector2.ZERO              # just inside the entrance facade
## The far end of the entrance approach, out on the forecourt by the kerb. Every
## visitor is born here and dies here, so arrivals walk in off the street under
## the canopy instead of materialising in the doorway. City owns the constant
## because City owns the pavement it stands on.
var _street_g: Vector2 = City.STREET_G
var _marketer_g := Vector2.ZERO
var _porter_home := Vector2.ZERO
var _porter_step: float = 0.7
var _vault_drop := Vector2.ZERO
var _pile_g := Vector2.ZERO
var _counter_gy: float = 0.0
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

class Visitor:
	var node: Character
	var pos: Vector2 = Vector2.ZERO       # grid space
	var state: String = "to_queue"        # to_queue | queue | crowd | browse | exit
	var window: int = -1
	var target: Vector2 = Vector2.ZERO    # grid space
	## Waypoints to clear before `target`. Only the entrance approach uses it:
	## an arrival walks street -> door -> queue as one continuous move, so the
	## FSM never has to learn that the museum has an outside. Untyped to match
	## `spots` below — a typed Array here rejects a plain [door] literal.
	var path: Array = []
	var spots: Array = []
	var wait: float = 0.0
	var speed: float = 2.1                # tiles/second

class Porter:
	var node: Character
	var pos: Vector2 = Vector2.ZERO
	var state: String = "idle"            # idle | to_window | to_vault
	var target: Vector2 = Vector2.ZERO
	var window: int = -1
	var carried: int = 0

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

	# The city surround goes in FIRST and sits a pixel above the canvas origin,
	# so Y-sort puts the whole block behind Ground and therefore behind every
	# room, prop and actor. It draws nothing inside the footprint and takes no
	# input, so it can never occlude gameplay or eat a tap.
	_city = City.new()
	_city.style = _theme.surround
	_canvas.add_child(_city)

	# Ground sits at the canvas origin, which projects above every prop and
	# actor, so Y-sorting alone keeps it behind. Do NOT force it with a negative
	# z_index: z_index is global within the canvas layer, not parent-scoped, and
	# a negative value drops the whole diorama behind the app background.
	_ground = Node2D.new()
	_ground.name = "Ground"
	_canvas.add_child(_ground)
	_ground.draw.connect(_draw_ground)

	_stacks_layer = Node2D.new()
	_stacks_layer.name = "Stacks"
	_stacks_layer.position = Iso.to_screen(Vector2(0.0, _counter_gy))
	_canvas.add_child(_stacks_layer)
	_stacks_layer.draw.connect(_draw_stacks)

	_pile_layer = Node2D.new()
	_pile_layer.name = "VaultPile"
	_pile_layer.position = Iso.to_screen(_pile_g)
	_canvas.add_child(_pile_layer)
	_pile_layer.draw.connect(_draw_pile)

	_labels_layer = Node2D.new()
	_labels_layer.name = "Labels"
	_labels_layer.z_index = 2      # above the cast (0) and the cash floats (1)
	_canvas.add_child(_labels_layer)
	_labels_layer.draw.connect(_draw_labels)

	for i in _max_windows:
		_queues.append([])
		_stacks.append(0)
		_serve_t.append(0.0)

	_marketer = Character.new()
	# Variant 2: the promotions room seats at most two clerks, so this keeps the
	# roaming marketer from being a copy of whoever is standing at the desk.
	_marketer.set_uniform(_theme.accent("promotions"), 2)
	_marketer.holding_sign = true
	_marketer.visible = false
	_canvas.add_child(_marketer)
	_place(_marketer, _marketer_g)

	resized.connect(_fit_canvas)
	_fit_canvas()
	_rebuild_props()
	_refresh_cast()
	if EventBus.has_signal("department_upgraded"):
		EventBus.department_upgraded.connect(
			func(_v: String, _d: String, _t: String, _l: int) -> void: _refresh_cast())
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
	_window_gx.clear()
	for w in _max_windows:
		_window_gx.append(q_rect.position.x + Exhibits.f(q.get("first_gx"), 2.3)
			+ float(w) * Exhibits.f(q.get("gx_step"), 2.5))
	_slot_gy.clear()
	for j in _slots_per_window:
		_slot_gy.append(_counter_gy + Exhibits.f(q.get("slot_lead"), 1.0)
			+ float(j) * Exhibits.f(q.get("slot_gap"), 0.55))

	var store_room: Dictionary = _theme.role("store")
	var s_at: Vector2 = (store_room.get("rect", Rect2()) as Rect2).position
	var s: Dictionary = store_room.get("store", {}) as Dictionary
	_porter_home = s_at + Exhibits.v2(s.get("home"), Vector2(1.4, 4.4))
	_porter_step = Exhibits.f(s.get("home_step"), 0.7)
	_vault_drop = s_at + Exhibits.v2(s.get("drop"), Vector2(3.2, 4.2))
	_pile_g = s_at + Exhibits.v2(s.get("pile"), Vector2(3.7, 4.3))

	var lobby: Dictionary = _theme.role("lobby")
	var l_at: Vector2 = (lobby.get("rect", Rect2()) as Rect2).position
	_door_g = l_at + Exhibits.v2(lobby.get("door"), Vector2(12.9, 2.3))
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
	_ground_paint.append([index, Exhibits.painter(str(spec.get("kind", fallback)), spec)])

func _paint_band(index: int) -> void:
	for entry in _ground_paint:
		if int(entry[0]) == index:
			(entry[1] as Callable).call(_ground)

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
	for v in _visitors:
		v.node.queue_free()
	_visitors.clear()
	_crowd.clear()
	for c in _staff_nodes + _docent_nodes + _promo_nodes:
		(c as Node).queue_free()
	_staff_nodes.clear()
	_docent_nodes.clear()
	_promo_nodes.clear()
	for p in _porters:
		p.node.queue_free()
	_porters.clear()

	_load_theme(venue_id)
	_city.style = _theme.surround
	_city.queue_redraw()

	_queues.clear()
	_stacks.clear()
	_serve_t.clear()
	for i in _max_windows:
		_queues.append([])
		_stacks.append(0)
		_serve_t.append(0.0)
	_windows_active = 1
	_stacks_layer.position = Iso.to_screen(Vector2(0.0, _counter_gy))
	_pile_layer.position = Iso.to_screen(_pile_g)
	_marketer.set_uniform(_theme.accent("promotions"), 2)
	_place(_marketer, _marketer_g)

	_cast_key = ""
	_props_key = ""
	_rebuild_props()
	_refresh_cast()
	_ground.queue_redraw()
	_labels_layer.queue_redraw()
	_stacks_dirty = true

func get_alive_visitor_count() -> int:
	return _visitors.size()

func get_queue_occupancy() -> int:
	var n: int = 0
	for q in _queues:
		n += q.size()
	return n

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
		"slots": _slots_per_window,
	}

## Population by FSM state. The density pass is tuned against this: a floor whose
## whole crowd is parked in one room reads worse than a thinner one spread over
## four, and that is invisible from any single screenshot.
func state_census() -> Dictionary:
	var out := {"to_queue": 0, "queue": 0, "crowd": 0, "browse": 0, "linger": 0, "exit": 0}
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

## Every grid point a character is ever asked to stand on. Same reason: a
## waypoint outside the canvas walks somebody off screen, and one inside a prop
## footprint stands them in the furniture.
func standing_spots() -> Array[Vector2]:
	var out: Array[Vector2] = [
		_door_g, _street_g, _marketer_g, _porter_home, _vault_drop, _pile_g]
	for w in _max_windows:
		out.append(Vector2(_window_gx[w], _counter_gy - 0.7))
		out.append(Vector2(_window_gx[w] + 0.8, _counter_gy + 0.5))
		for j in _slots_per_window:
			out.append(_slot_pos(w, j))
	for i in MAX_CROWD:
		out.append(_crowd_slot(i))
	for spot in _lobby_spots:
		out.append(spot)
	for key in _browse.keys():
		for spot in _browse[key]:
			out.append(spot)
	return out

## Dept id for a canvas-space position, or "" if no room hit.
func tap_zone_at(canvas_pos: Vector2) -> String:
	var g: Vector2 = Iso.to_grid(canvas_pos)
	for dept_id in _tap_zones.keys():
		if (_tap_zones[dept_id] as Rect2).has_point(g):
			return dept_id
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

## Same code path as a real click (tests call this directly).
func simulate_tap(canvas_pos: Vector2) -> void:
	var dept: String = tap_zone_at(canvas_pos)
	if dept != "":
		dept_selected.emit(dept)

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		simulate_tap(_to_canvas(event.position))

func _to_canvas(p: Vector2) -> Vector2:
	var s: float = maxf(_canvas.scale.x, 0.0001)
	return (p - _canvas.position) / s

func _fit_canvas() -> void:
	var s: float = minf(size.x / FLOOR.x, size.y / FLOOR.y)
	if s <= 0.0:
		s = 1.0
	_canvas.scale = Vector2(s, s)
	_canvas.position = (size - FLOOR * s) * 0.5
	# Tell the surround where the picture actually ends. The canvas is letterboxed
	# inside this Control, so the visible area in canvas coordinates is wider and
	# taller than FLOOR — and the city has to reach those edges or the shell shows
	# through above and below it.
	if _city != null:
		_city.set_visible_band(Rect2(-_canvas.position / s, size / s))

# --- Placement ----------------------------------------------------------------

## Move a node to a grid position: project, then scale for depth.
func _place(n: Node2D, g: Vector2) -> void:
	n.position = Iso.to_screen(g)
	# Normalise depth against THIS venue's footprint, not a global grid, or a
	# tall narrow venue would compress its whole depth range into a fraction of
	# the scale curve and its cast would barely change size front to back.
	var span: float = _theme.bounds.size.x + _theme.bounds.size.y
	if span <= 0.0:
		span = Iso.GRID.x + Iso.GRID.y
	var t: float = clampf((g.x + g.y - _theme.bounds.position.x - _theme.bounds.position.y) / span, 0.0, 1.0)
	n.scale = Vector2.ONE * lerpf(DEPTH_SCALE_BACK, DEPTH_SCALE_FRONT, t)

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
	var key: String = "%d/%d/%d/%d" % [
		_staff_level("ticket"), _staff_level("gallery"),
		_staff_level("promotions"), _staff_level("archive")]
	if key == _cast_key:
		return
	_cast_key = key

	_windows_active = clampi(_staff_level("ticket"), 1, _max_windows)
	while _staff_nodes.size() < _windows_active:
		var i: int = _staff_nodes.size()
		var c: Character = Character.new()
		c.set_uniform(_theme.accent("ticket"), i)
		c.facing = 1
		_canvas.add_child(c)
		_place(c, Vector2(_window_gx[i], _counter_gy - 0.7))
		_staff_nodes.append(c)
	while _staff_nodes.size() > _windows_active:
		_staff_nodes.pop_back().queue_free()

	var gallery_posts: Array[Vector2] = _stations("gallery")
	var docents: int = clampi(_staff_level("gallery"), 0, gallery_posts.size())
	while _docent_nodes.size() < docents:
		var c: Character = Character.new()
		c.set_uniform(_theme.accent("gallery").darkened(0.2), _docent_nodes.size())
		_canvas.add_child(c)
		_place(c, gallery_posts[_docent_nodes.size()])
		_docent_nodes.append(c)
	while _docent_nodes.size() > docents:
		_docent_nodes.pop_back().queue_free()

	var promo_posts: Array[Vector2] = _stations("promotions")
	var clerks: int = clampi(_staff_level("promotions"), 1, promo_posts.size())
	while _promo_nodes.size() < clerks:
		var c: Character = Character.new()
		c.set_uniform(_theme.accent("promotions"), _promo_nodes.size())
		_canvas.add_child(c)
		_place(c, promo_posts[_promo_nodes.size()])
		_promo_nodes.append(c)
	while _promo_nodes.size() > clerks:
		_promo_nodes.pop_back().queue_free()

	var porters: int = clampi(_staff_level("archive"), 1, 3)
	while _porters.size() < porters:
		var p := Porter.new()
		var c: Character = Character.new()
		c.set_uniform(_theme.accent("archive"), _porters.size())
		c.with_cart = true
		_canvas.add_child(c)
		p.pos = _porter_home + Vector2(float(_porters.size()) * _porter_step, 0.0)
		p.target = p.pos
		p.node = c
		_place(c, p.pos)
		_porters.append(p)
	while _porters.size() > porters:
		var dead: Porter = _porters.pop_back()
		dead.node.queue_free()

	_rebuild_props()
	_ground.queue_redraw()

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

func _process(delta: float) -> void:
	if not GameState.ready_flag:
		return
	var dt: float = delta * time_scale
	_city.advance(dt)
	_spawn_t += dt
	_try_spawn()
	_update_serve(dt)
	_update_visitors(dt)
	_update_porters(dt)
	if _pile_flash > 0.0:
		_pile_flash = maxf(_pile_flash - dt * 2.0, 0.0)
		_pile_layer.queue_redraw()
	if _stacks_dirty:
		_stacks_dirty = false
		_stacks_layer.queue_redraw()

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
		return
	var best: int = -1
	for w in _windows_active:
		if _queues[w].size() < _slots_per_window \
				and (best == -1 or _queues[w].size() < _queues[best].size()):
			best = w
	if best == -1 and _crowd.size() >= MAX_CROWD:
		return  # turn away — floor is packed
	var v := Visitor.new()
	var c: Character = Character.new()
	c.set_look_slot(_next_look_slot())
	_canvas.add_child(c)
	v.node = c
	v.pos = _street_g
	v.path = [_door_g]
	v.speed = randf_range(1.8, 2.5)
	_place(c, v.pos)
	_fade_outdoors(v)
	_visitors.append(v)
	if best == -1:
		v.state = "crowd"
		_crowd.append(v)
		v.target = _crowd_slot(_crowd.size() - 1)
	else:
		_assign_to_window(v, best)

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
	for v in _visitors:
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

func _assign_to_window(v: Visitor, w: int) -> void:
	if v.state == "crowd":
		_crowd.erase(v)
	v.state = "to_queue"
	v.window = w
	_queues[w].append(v)
	v.target = _slot_pos(w, _queues[w].size() - 1)

func _slot_pos(w: int, idx: int) -> Vector2:
	return Vector2(_window_gx[w], _slot_gy[clampi(idx, 0, _slots_per_window - 1)])

func _serve_time() -> float:
	var per_window: float = clampf(_serve, 0.25, 3.0) / float(maxi(_windows_active, 1))
	return clampf(1.0 / per_window, MIN_SERVE_S, 8.0)

func _update_serve(dt: float) -> void:
	for w in _windows_active:
		if _queues[w].is_empty():
			_serve_t[w] = 0.0
			continue
		var front: Visitor = _queues[w][0]
		if front.state != "queue":
			continue
		_serve_t[w] += dt
		if _serve_t[w] >= _serve_time():
			_serve_t[w] = 0.0
			_serve_visitor(w)

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
	_spawn_float("+$" + _value_text, Vector2(_window_gx[w], _counter_gy - 1.0))
	for i in _queues[w].size():
		(_queues[w][i] as Visitor).target = _slot_pos(w, i)
	var keys: Array = _exhibit_keys.duplicate()
	keys.shuffle()
	var spots: Array = []
	# Two or three exhibits each, not one or two: a served visitor now spends long
	# enough in the gallery for the room to hold a standing audience.
	for k in keys.slice(0, randi_range(1, 3)):
		var opts: Array = _browse[k]
		spots.append(opts[randi() % opts.size()])
	v.spots = spots
	v.state = "browse"
	v.window = -1
	v.target = v.spots.pop_front()
	for w2 in _windows_active:
		if _crowd.is_empty():
			break
		if _queues[w2].size() < _slots_per_window:
			_assign_to_window(_crowd[0], w2)

func _update_visitors(dt: float) -> void:
	var done: Array = []
	for v in _visitors:
		var arrived: bool = _move(v, dt)
		match v.state:
			"to_queue":
				if arrived:
					v.state = "queue"
			"queue", "crowd":
				pass
			"browse":
				if arrived:
					if v.wait <= 0.0:
						v.wait = randf_range(1.2, 2.6)
					v.wait -= dt
					if v.wait <= 0.0:
						if v.spots.is_empty():
							v.state = "linger"
							v.target = _lobby_spots[randi() % _lobby_spots.size()]
						else:
							v.target = v.spots.pop_front()
			"linger":
				if arrived:
					if v.wait <= 0.0:
						v.wait = randf_range(1.0, 2.6)
					v.wait -= dt
					if v.wait <= 0.0:
						v.state = "exit"
						v.path = [_door_g]
						v.target = _street_g
			"exit":
				if arrived:
					done.append(v)
	for v in done:
		_visitors.erase(v)
		v.node.queue_free()

## Grid-space movement. Facing flips on the projected x direction so characters
## turn the way they visually travel, not the way the grid axis points.
func _move(v: Visitor, dt: float) -> bool:
	var goal: Vector2 = v.path[0] if not v.path.is_empty() else v.target
	var d: Vector2 = goal - v.pos
	var dist: float = d.length()
	if dist < 0.06:
		if not v.path.is_empty():
			v.path.remove_at(0)
			return false        # a waypoint is a corner, not an arrival
		v.node.walking = false
		return true
	var step: float = minf(v.speed * dt, dist)
	var before: float = v.node.position.x
	v.pos += d / dist * step
	_place(v.node, v.pos)
	v.node.facing = 1 if v.node.position.x >= before else -1
	v.node.walking = true
	_fade_outdoors(v)
	return false

## Dissolve a figure across the last tile of the approach.
##
## The spawn point has to stay inside the clipped canvas (Iso.on_canvas), so a
## visitor cannot simply walk in from off screen — without this they pop into
## existence on the pavement, which is the exact tell the surround exists to
## remove. Fading over the forecourt costs one clamp per visitor per frame.
func _fade_outdoors(v: Visitor) -> void:
	var a: float = clampf((_street_g.y - v.pos.y) * 1.6, 0.0, 1.0)
	v.node.modulate.a = a

func _porter_speed() -> float:
	return clampf(1.8 + _transport * 0.5, 1.8, 4.2)

func _update_porters(dt: float) -> void:
	for p in _porters:
		match p.state:
			"idle":
				var best: int = -1
				for w in _windows_active:
					if _stacks[w] >= 2 and (best == -1 or _stacks[w] > _stacks[best]):
						best = w
				if best != -1:
					p.window = best
					p.state = "to_window"
					p.target = Vector2(_window_gx[best] + 0.8, _counter_gy + 0.5)
			"to_window":
				if _porter_move(p, dt):
					var take: int = mini(_stacks[p.window], 6)
					_stacks[p.window] -= take
					_stacks_dirty = true
					p.carried = take
					p.node.carry_stack = clampi(take, 1, 4)
					p.node.queue_redraw()
					p.state = "to_vault"
					p.target = _vault_drop
			"to_vault":
				if _porter_move(p, dt):
					p.carried = 0
					p.node.carry_stack = 0
					p.node.queue_redraw()
					_porter_trips += 1
					_pile_flash = 1.0
					_spawn_coin_burst(_vault_drop, 7)
					p.state = "idle"
					p.target = _porter_home \
						+ Vector2(float(_porters.find(p)) * _porter_step, 0.0)

func _porter_move(p: Porter, dt: float) -> bool:
	var d: Vector2 = p.target - p.pos
	var dist: float = d.length()
	if dist < 0.08:
		p.node.walking = false
		return true
	var step: float = minf(_porter_speed() * dt, dist)
	var before: float = p.node.position.x
	p.pos += d / dist * step
	_place(p.node, p.pos)
	p.node.facing = 1 if p.node.position.x >= before else -1
	p.node.walking = true
	return false

# --- Feedback -----------------------------------------------------------------

## Cash pops off the counter on an arc, overshoots, then fades as it drifts up.
func _spawn_float(text: String, g: Vector2) -> void:
	var pos: Vector2 = Iso.to_screen(g)
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", UI.font())
	l.add_theme_font_size_override("font_size", 21)
	l.add_theme_color_override("font_color", UI.UPGRADE_GREEN.lightened(0.12))
	l.add_theme_color_override("font_outline_color", Color(0.05, 0.03, 0.12, 0.9))
	l.add_theme_constant_override("outline_size", 5)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.z_index = 1
	l.position = pos + Vector2(-18, -30)
	l.pivot_offset = Vector2(18, 10)
	l.scale = Vector2(0.6, 0.6)
	_canvas.add_child(l)
	var drift: float = randf_range(-14.0, 14.0)
	var tw := l.create_tween()
	tw.set_parallel(true)
	tw.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(l, "scale", Vector2.ONE, 0.22)
	tw.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(l, "position:y", l.position.y - 52.0, 1.1)
	tw.tween_property(l, "position:x", l.position.x + drift, 1.1)
	tw.chain().tween_property(l, "modulate:a", 0.0, 0.34)
	tw.chain().tween_callback(l.queue_free)

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
## drawing a run of polygons back to back inside one canvas item batches into a
## handful of draw calls. That is the whole trick behind the density pass:
## detail goes into existing canvas items, not into new ones.

func _draw_ground() -> void:
	# Outer slab, slightly proud of the rooms — reads as the building shell.
	var inset: float = Exhibits.f(_theme.shell.get("inset"), 0.35)
	var shell_col: Color = Exhibits.c(_theme.shell.get("col"), UI.WALL_BROWN.darkened(0.15))
	# One slab per room rather than one rectangle over the whole grid. Adjacent
	# rooms merge into a continuous plinth, but a venue that does NOT tile a
	# rectangle keeps its real silhouette — an L, a T, a courtyard, or detached
	# wings joined by a link room. Drawing the grid rectangle instead was the
	# single reason every venue read as the same square building.
	for entry in _theme.rooms:
		var rr: Rect2 = (entry as Dictionary)["rect"]
		Iso.floor_patch(_ground, rr.position - Vector2(inset, inset),
			rr.size + Vector2(inset, inset) * 2.0, shell_col)

	for entry in _theme.rooms:
		var room: Dictionary = entry as Dictionary
		var r: Rect2 = room["rect"]
		var col: Color = room["floor"]
		Iso.floor_patch(_ground, r.position, r.size, col)
		Iso.floor_tiles(_ground, r.position, r.size, col.darkened(0.10))
		if str(room.get("dept", "")) != "" and _choke == str(room["dept"]):
			# Bottleneck room: hot rim on the floor edge, readable at a glance.
			var ring := Iso.quad(r.position, r.size)
			ring.append(ring[0])
			_ground.draw_polyline(ring, UI.DANGER, 3.0)

	_paint_band(0)          # entrance runner
	_draw_queue_paint()
	_paint_band(1)          # rugs, thresholds, mats

	for entry in _theme.walls:
		var w: Dictionary = entry as Dictionary
		Iso.wall(_ground, Exhibits.v2(w.get("at")), Exhibits.f(w.get("len"), 1.0),
			str(w.get("axis", "x")), Exhibits.c(w.get("col"), UI.WALL_BROWN),
			Exhibits.f(w.get("h"), Iso.WALL_H))

	_paint_band(2)          # wall art, signage, wall-mounted exhibits
	_paint_band(3)          # bunting, strung above the tallest wall

## Painted queue lanes, one strip per window. Floor markings are how the
## reference tells the player where a line forms before anyone is standing in it,
## and deriving them here rather than listing them in the theme is what
## guarantees they land under the queue instead of beside it.
func _draw_queue_paint() -> void:
	var room: Dictionary = _theme.role("queue")
	if room.is_empty() or _slot_gy.is_empty():
		return
	var col: Color = (room["floor"] as Color).darkened(0.07)
	var depth: float = _slot_gy[_slots_per_window - 1] - _slot_gy[0] + 1.0
	for w in _max_windows:
		Iso.rug(_ground, Vector2(_window_gx[w] - 0.5, _slot_gy[0] - 0.5),
			Vector2(1.0, depth), col)

# --- Props: individual Y-sorted furniture nodes --------------------------------

## Adds one static prop. Each is its own node positioned at its grid anchor so
## Y-sort can interleave it with the moving cast; the painter works in absolute
## canvas coordinates and cancels the node offset with a draw transform.
func _add_prop(g: Vector2, painter: Callable) -> void:
	_prop_g.append(g)
	var n := Node2D.new()
	n.position = Iso.to_screen(g)
	_canvas.add_child(n)
	n.draw.connect(func() -> void:
		n.draw_set_transform(-n.position)
		painter.call(n))
	_props.append(n)

func _clear_props() -> void:
	for p in _props:
		if is_instance_valid(p):
			p.queue_free()
	_props.clear()
	_prop_g.clear()

func _rebuild_props() -> void:
	var key: String = "%s/%d" % [_theme.id, _windows_active]
	if key == _props_key and not _props.is_empty():
		return
	_props_key = key
	_clear_props()
	_build_queue_fixtures()
	for entry in _theme.exhibits:
		var e: Dictionary = entry as Dictionary
		if str(e.get("layer", "floor")) != "floor":
			continue
		_add_prop(Exhibits.anchor(e), Exhibits.guarded(str(e.get("kind", "plinth")), e))
	for entry in _theme.props:
		var p: Dictionary = entry as Dictionary
		_add_prop(Exhibits.anchor(p), Exhibits.guarded(str(p.get("kind", "plinth")), p))
	if not _theme.role("lobby").is_empty():
		# The canopy belongs to the surround but stands in FRONT of the facade,
		# and the surround draws behind the whole museum — so it comes across as
		# a Y-sorted prop and City only supplies the painter.
		var surround: String = _theme.surround
		_add_prop(City.CANOPY_G, func(ci: CanvasItem) -> void: City.draw_canopy(ci, surround))

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
		var gx: float = _window_gx[w]
		_add_prop(Vector2(gx, _counter_gy), Exhibits.painter("counter", {
			"at": Vector2(gx - size.x * 0.5, _counter_gy - 0.30), "size": size,
			"height": Exhibits.f(q.get("counter_h"), 21.0),
			"col": accent.darkened(0.06), "trim": _theme.col("trim", UI.BRASS),
			"label": str(w + 1),
		}))
		_add_queue_lane(gx, -_lane_offset)
		_add_queue_lane(gx, _lane_offset)

## One rope line as ONE node, instead of one node per post.
##
## The queues used to build forty separate stanchion nodes, which was about a
## sixth of the whole floor's draw-call budget spent on posts. Merging a lane
## into a single canvas item only stays honest if the merged node sorts correctly
## against the people standing in it, and here it does exactly: the far lane
## belongs BEHIND every visitor at that window, so it anchors at the back of the
## queue, and the near lane belongs in front of all of them, so it anchors at the
## front. There is no depth at which a lane and its queue interleave.
func _add_queue_lane(gx: float, side: float) -> void:
	var lane_gx: float = gx + side
	var anchor_gy: float = _slot_gy[0] - 0.45
	if side > 0.0:
		anchor_gy = _slot_gy[_slots_per_window - 1] + 0.45
	var pts: Array = []
	for j in _slots_per_window:
		pts.append(Vector2(lane_gx, _slot_gy[j]))
	_add_prop(Vector2(lane_gx, anchor_gy), Exhibits.painter("rope_line", {
		"points": pts, "post_h": 26.0, "rope_h": 25.0, "sag": 6.0, "segments": 9,
		"width": 2.0, "gloss": true,
		"rope": _theme.col("rope", UI.ROPE_RED), "post": _theme.col("shell", UI.WALL_BROWN),
		"knob": _theme.col("trim", UI.BRASS),
	}))

# --- Dynamic layers -------------------------------------------------------------

func _draw_stacks() -> void:
	# Ticket-stub bundles piling beside each counter; an archive choke lets them
	# overflow, which is the visual tell that transport is the bottleneck.
	var cap: int = MAX_STACK_VIS * 2 if _choke == "archive" else MAX_STACK_VIS
	for w in _windows_active:
		var n: int = mini(_stacks[w], cap)
		var anchor: Vector2 = Iso.to_screen(Vector2(_window_gx[w] + 1.0, _counter_gy)) \
			- _stacks_layer.position
		for i in n:
			var y: float = anchor.y - 18.0 - float(i) * 3.2
			_stacks_layer.draw_colored_polygon(PackedVector2Array([
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
		_pile_layer.draw_colored_polygon(PackedVector2Array([
			Vector2(-rad + wobble, y), Vector2(wobble, y - rad * 0.5),
			Vector2(rad + wobble, y), Vector2(wobble, y + rad * 0.5)]),
			flash.darkened(0.10 if i % 2 == 0 else 0.0))

func _draw_labels() -> void:
	for entry in _theme.rooms:
		var room: Dictionary = entry as Dictionary
		var title: String = str(room.get("name", ""))
		if title == "" or not room.has("plaque"):
			continue
		var at: Vector2 = Iso.to_screen((room["rect"] as Rect2).position
			+ Exhibits.v2(room["plaque"])) + Vector2(0, -8)
		_draw_plaque(at, title, room["accent"] as Color)

## Room name on a floating plaque, on its own layer: an earlier pass drew labels
## onto the floor, where the cast walked through them.
##
## Plaque points are theme data, placed by hand over a piece of FURNITURE — a
## plinth, a shelf bank, a desk, a counter — because furniture is the only floor
## the cast never stands on. The old rule (16% / 84% of each room) put the ticket
## plaque in the queue and the archive plaque on the porters' home tile.
func _draw_plaque(center: Vector2, title: String, accent: Color) -> void:
	var w: float = float(_font.get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x) + 16.0
	var plate := Rect2(center.x - w * 0.5, center.y - 10.0, w, 20.0)
	_labels_layer.draw_rect(Rect2(plate.position + Vector2(1.5, 2.0), plate.size),
		Color(0.06, 0.04, 0.14, 0.40))
	_labels_layer.draw_rect(plate, accent.darkened(0.58))
	_labels_layer.draw_rect(plate, accent.lightened(0.25), false, 1.5)
	_labels_layer.draw_string(_font, Vector2(plate.position.x + 8.0, plate.position.y + 15.0),
		title, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, UI.FLOOR_CREAM)
