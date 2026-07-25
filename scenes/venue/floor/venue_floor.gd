extends Control
## VenueFloor — the living museum, as an isometric diorama.
##
## The simulation runs entirely in GRID space (see iso.gd); nothing here knows
## about canvas pixels except at draw time and at tap time. That separation is
## what let the visitor/porter FSM come across from the old flat-plan version
## unchanged — only the waypoint constants changed units, from pixels to tiles.
##
## Layout (15 x 17 tiles), arranged so the eye enters at the lobby in the near
## corner and travels back through the ticket hall into the exhibits:
##
##        +-----------------+--------+
##        |  GRAND GALLERY  | ARCHIVE|      (back, top of screen)
##        |                 +--------+
##        |                 | PROMO  |
##        +-----------------+--------+
##        |      TICKET HALL         |
##        +--------------------------+
##        |         LOBBY            |      (front, bottom of screen)
##        +--------------------------+
##
## Props are individual Y-sorted nodes rather than one flat static layer, so a
## visitor can stand behind a counter and in front of a bench in the same frame.

signal dept_selected(dept_id: String)

const UI := preload("res://scripts/ui/ui_kit.gd")
const Character := preload("res://scenes/venue/floor/character.gd")
const Iso := preload("res://scenes/venue/floor/iso.gd")

const FLOOR := Vector2(720, 760)      # logical canvas the diorama is fitted into

# --- Rooms, in grid space -----------------------------------------------------
const R_GALLERY := Rect2(0, 0, 9, 8)
const R_VAULT := Rect2(9, 0, 6, 5)
const R_PROMO := Rect2(9, 5, 6, 4)
const R_TICKET := Rect2(0, 9, 15, 5)
const R_LOBBY := Rect2(0, 14, 15, 3)
const R_CORRIDOR := Rect2(0, 8, 9, 1)
const TAP_ZONES := {  # checked in order (first hit wins)
	"archive": R_VAULT, "promotions": R_PROMO, "gallery": R_GALLERY, "ticket": R_TICKET,
}

# --- Waypoints, in grid space -------------------------------------------------
##
## Every constant here is inside Iso.gx_window() for its own depth row, with at
## least half a tile of margin. That was not true before: the vault drop sat
## exactly on the clip edge and the porters banked their loads off screen.
const DOOR_G := Vector2(12.9, 16.3)  # just inside the entrance facade
const COUNTER_GY := 10.1
## Shifted +0.8 tiles east of the original row. The projection shears x by -gy,
## so a queue that runs 3 tiles deeper also runs 90px further left; window 1's
## outer rope line used to end up at x = -9 once the queues got longer.
const WINDOW_GX: Array[float] = [2.3, 4.8, 7.3, 9.8, 12.3]
## Six slots at 0.55 tiles instead of four at 0.8. The reference queues are
## packed shoulder to shoulder; ours were a dotted line of people.
const SLOT_GY: Array[float] = [11.10, 11.65, 12.20, 12.75, 13.30, 13.85]
const MAX_WINDOWS := 5
const SLOTS_PER_WINDOW := 6
const MAX_ALIVE := 34
const MAX_CROWD := 14
const MAX_STACK_VIS := 10
const PORTER_HOME := Vector2(10.4, 4.4)
const VAULT_DROP := Vector2(12.2, 4.2)
const PILE_G := Vector2(12.7, 4.3)
const MARKETER_G := Vector2(11.3, 16.2)  # touting beside the entrance
## Six exhibits rather than three, each with several viewing spots. Browsers
## used to pile onto the same three tiles, which read as a queue for the dinosaur
## rather than as a gallery being looked at.
const BROWSE_SPOTS := {
	"dino": [Vector2(2.0, 4.4), Vector2(3.4, 4.6), Vector2(4.8, 4.3), Vector2(1.3, 3.7)],
	"painting": [Vector2(2.6, 0.9), Vector2(5.0, 0.9), Vector2(7.4, 1.0)],
	"sarcophagus": [Vector2(6.0, 6.4), Vector2(7.5, 6.0), Vector2(5.3, 5.7)],
	"statue": [Vector2(5.0, 2.7), Vector2(6.3, 2.9)],
	"vitrine": [Vector2(6.6, 3.4), Vector2(8.0, 3.2)],
	"minerals": [Vector2(1.1, 2.2), Vector2(2.3, 2.0)],
}
const EXHIBIT_KEYS: Array[String] = [
	"dino", "painting", "sarcophagus", "statue", "vitrine", "minerals"]
## Where a visitor stands for a moment on the way out. Without this the lobby was
## a corridor: everyone walked it in a straight line to the door, so the largest
## room on the floor was the only one with nobody standing in it. Each spot is
## clear of the lobby furniture and inside Iso.gx_window for its own depth.
const LOBBY_SPOTS: Array[Vector2] = [
	Vector2(8.0, 15.2), Vector2(9.3, 15.7), Vector2(10.6, 16.1),
	Vector2(8.6, 16.4), Vector2(7.6, 15.8), Vector2(11.5, 15.4),
	Vector2(9.9, 14.8), Vector2(11.0, 16.8), Vector2(7.2, 16.9),
]
## Room plaques, placed by hand on floor the cast and the props do not use. The
## old rule (16% / 84% of each room) dropped the ticket plaque into the queue and
## the archive plaque onto the porters' home tile.
## Room plaques. Every one of these sits over a piece of FURNITURE — the dino
## plinth, a shelf bank, a promotions desk, a ticket counter — because furniture
## is the only floor the cast never stands on. The old rule (16% / 84% of each
## room) put the ticket plaque in the queue and the archive plaque on the
## porters' home tile, and once the rooms were furnished it covered a face in
## three rooms out of four.
const PLAQUE_G := {
	"gallery": Vector2(6.1, 7.1), "archive": Vector2(10.6, 3.8),
	"promotions": Vector2(10.5, 6.7), "ticket": Vector2(1.1, 9.6),
}

# --- Depth --------------------------------------------------------------------
## Actors shrink slightly toward the back of the hall. Subtle on top of a real
## iso projection — the projection already carries most of the depth read.
const DEPTH_SCALE_BACK := 0.88
const DEPTH_SCALE_FRONT := 1.06

var time_scale: float = 1.0    # test hook: accelerate the visual sim

var _canvas: Node2D
var _ground: Node2D            # floors + walls, always behind everything
var _stacks_layer: Node2D      # window ticket-stub stacks
var _pile_layer: Node2D        # vault pile
var _labels_layer: Node2D      # room plaques, always above the cast
var _props: Array = []         # Y-sorted static furniture nodes
var _prop_g: Array[Vector2] = []   # their grid anchors, for the geometry suite
var _font: Font

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
	var spots: Array = []
	var wait: float = 0.0
	var speed: float = 2.1                # tiles/second

class Porter:
	var node: Character
	var pos: Vector2 = PORTER_HOME
	var state: String = "idle"            # idle | to_window | to_vault
	var target: Vector2 = PORTER_HOME
	var window: int = -1
	var carried: int = 0

func _ready() -> void:
	name = "VenueFloor"
	clip_contents = true
	custom_minimum_size = Vector2(360, 380)
	_font = ThemeDB.fallback_font

	_canvas = Node2D.new()
	# Y-sorting is what makes the diorama hold together: actors and props are
	# ordered by projected depth every frame, so a visitor can pass behind a
	# counter and in front of a bench without any manual layering.
	_canvas.y_sort_enabled = true
	add_child(_canvas)

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
	_stacks_layer.position = Iso.to_screen(Vector2(0.0, COUNTER_GY))
	_canvas.add_child(_stacks_layer)
	_stacks_layer.draw.connect(_draw_stacks)

	_pile_layer = Node2D.new()
	_pile_layer.name = "VaultPile"
	_pile_layer.position = Iso.to_screen(PILE_G)
	_canvas.add_child(_pile_layer)
	_pile_layer.draw.connect(_draw_pile)

	_labels_layer = Node2D.new()
	_labels_layer.name = "Labels"
	_labels_layer.z_index = 2      # above the cast (0) and the cash floats (1)
	_canvas.add_child(_labels_layer)
	_labels_layer.draw.connect(_draw_labels)

	for i in MAX_WINDOWS:
		_queues.append([])
		_stacks.append(0)
		_serve_t.append(0.0)

	_marketer = Character.new()
	# Variant 2: the promotions room seats at most two clerks, so this keeps the
	# roaming marketer from being a copy of whoever is standing at the desk.
	_marketer.set_uniform(UI.ROOM_PROMO, 2)
	_marketer.holding_sign = true
	_marketer.visible = false
	_canvas.add_child(_marketer)
	_place(_marketer, MARKETER_G)

	resized.connect(_fit_canvas)
	_fit_canvas()
	_rebuild_props()
	_refresh_cast()
	if EventBus.has_signal("department_upgraded"):
		EventBus.department_upgraded.connect(
			func(_v: String, _d: String, _t: String, _l: int) -> void: _refresh_cast())

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
	var out: Array[Vector2] = [DOOR_G, MARKETER_G, PORTER_HOME, VAULT_DROP, PILE_G]
	for w in MAX_WINDOWS:
		out.append(Vector2(WINDOW_GX[w], COUNTER_GY - 0.7))
		out.append(Vector2(WINDOW_GX[w] + 0.8, COUNTER_GY + 0.5))
		for j in SLOTS_PER_WINDOW:
			out.append(_slot_pos(w, j))
	for i in MAX_CROWD:
		out.append(_crowd_slot(i))
	for spot in LOBBY_SPOTS:
		out.append(spot)
	for key in BROWSE_SPOTS.keys():
		for spot in BROWSE_SPOTS[key]:
			out.append(spot)
	return out

## Dept id for a canvas-space position, or "" if no room hit.
func tap_zone_at(canvas_pos: Vector2) -> String:
	var g: Vector2 = Iso.to_grid(canvas_pos)
	for dept_id in TAP_ZONES.keys():
		if (TAP_ZONES[dept_id] as Rect2).has_point(g):
			return dept_id
	return ""

## Canvas-space centre of a department's room. Tests aim with this instead of
## hardcoding pixel coordinates, so the layout stays free to move.
func room_center(dept_id: String) -> Vector2:
	var r: Rect2 = TAP_ZONES.get(dept_id, R_TICKET)
	return Iso.to_screen(r.position + r.size * 0.5)

## A canvas point inside the diorama but outside every room (the lobby floor),
## for asserting that dead taps do nothing.
func dead_zone_point() -> Vector2:
	return Iso.to_screen(R_LOBBY.position + R_LOBBY.size * 0.5)

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

# --- Placement ----------------------------------------------------------------

## Move a node to a grid position: project, then scale for depth.
func _place(n: Node2D, g: Vector2) -> void:
	n.position = Iso.to_screen(g)
	var t: float = clampf((g.x + g.y) / (Iso.GRID.x + Iso.GRID.y), 0.0, 1.0)
	n.scale = Vector2.ONE * lerpf(DEPTH_SCALE_BACK, DEPTH_SCALE_FRONT, t)

# --- Cast (staffing visuals follow real dept levels) --------------------------

func _staff_level(dept_id: String) -> int:
	if not GameState.ready_flag:
		return 1
	return GameState.dept_level(GameState.current_venue, dept_id, "staff")

func _refresh_cast() -> void:
	if not GameState.ready_flag:
		return
	var key: String = "%d/%d/%d/%d" % [
		_staff_level("ticket"), _staff_level("gallery"),
		_staff_level("promotions"), _staff_level("archive")]
	if key == _cast_key:
		return
	_cast_key = key

	_windows_active = clampi(_staff_level("ticket"), 1, MAX_WINDOWS)
	while _staff_nodes.size() < _windows_active:
		var i: int = _staff_nodes.size()
		var c: Character = Character.new()
		c.set_uniform(UI.ROOM_TICKET, i)
		c.facing = 1
		_canvas.add_child(c)
		_place(c, Vector2(WINDOW_GX[i], COUNTER_GY - 0.7))
		_staff_nodes.append(c)
	while _staff_nodes.size() > _windows_active:
		_staff_nodes.pop_back().queue_free()

	var docents: int = clampi(_staff_level("gallery"), 0, 2)
	while _docent_nodes.size() < docents:
		var c: Character = Character.new()
		c.set_uniform(UI.ROOM_GALLERY.darkened(0.2), _docent_nodes.size())
		_canvas.add_child(c)
		_place(c, [Vector2(1.0, 3.5), Vector2(8.2, 3.9)][_docent_nodes.size()])
		_docent_nodes.append(c)
	while _docent_nodes.size() > docents:
		_docent_nodes.pop_back().queue_free()

	var clerks: int = clampi(_staff_level("promotions"), 1, 2)
	while _promo_nodes.size() < clerks:
		var c: Character = Character.new()
		c.set_uniform(UI.ROOM_PROMO, _promo_nodes.size())
		_canvas.add_child(c)
		_place(c, [Vector2(10.5, 6.15), Vector2(13.2, 6.65)][_promo_nodes.size()])
		_promo_nodes.append(c)
	while _promo_nodes.size() > clerks:
		_promo_nodes.pop_back().queue_free()

	var porters: int = clampi(_staff_level("archive"), 1, 3)
	while _porters.size() < porters:
		var p := Porter.new()
		var c: Character = Character.new()
		c.set_uniform(UI.ROOM_VAULT, _porters.size())
		c.with_cart = true
		_canvas.add_child(c)
		p.pos = PORTER_HOME + Vector2(float(_porters.size()) * 0.7, 0.0)
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
		if _queues[w].size() < SLOTS_PER_WINDOW and (best == -1 or _queues[w].size() < _queues[best].size()):
			best = w
	if best == -1 and _crowd.size() >= MAX_CROWD:
		return  # turn away — floor is packed
	var v := Visitor.new()
	var c: Character = Character.new()
	c.set_look_slot(_next_look_slot())
	_canvas.add_child(c)
	v.node = c
	v.pos = DOOR_G
	v.speed = randf_range(1.8, 2.5)
	_place(c, v.pos)
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
## carpet. Rows are offset +0.5 tiles east as they come forward so the block
## stays inside the visible wedge (gx >= gy - 12) all the way to the front row.
func _crowd_slot(i: int) -> Vector2:
	var col: int = i % 5
	var row: int = i / 5
	return Vector2(8.2 + float(col) * 0.95 + float(row) * 0.5, 15.1 + float(row) * 0.8)

func _assign_to_window(v: Visitor, w: int) -> void:
	if v.state == "crowd":
		_crowd.erase(v)
	v.state = "to_queue"
	v.window = w
	_queues[w].append(v)
	v.target = _slot_pos(w, _queues[w].size() - 1)

func _slot_pos(w: int, idx: int) -> Vector2:
	return Vector2(WINDOW_GX[w], SLOT_GY[clampi(idx, 0, SLOTS_PER_WINDOW - 1)])

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
	_spawn_float("+$" + _value_text, Vector2(WINDOW_GX[w], COUNTER_GY - 1.0))
	for i in _queues[w].size():
		(_queues[w][i] as Visitor).target = _slot_pos(w, i)
	var keys: Array = EXHIBIT_KEYS.duplicate()
	keys.shuffle()
	var spots: Array = []
	# Two or three exhibits each, not one or two: a served visitor now spends long
	# enough in the gallery for the room to hold a standing audience.
	for k in keys.slice(0, randi_range(1, 3)):
		var opts: Array = BROWSE_SPOTS[k]
		spots.append(opts[randi() % opts.size()])
	v.spots = spots
	v.state = "browse"
	v.window = -1
	v.target = v.spots.pop_front()
	for w2 in _windows_active:
		if _crowd.is_empty():
			break
		if _queues[w2].size() < SLOTS_PER_WINDOW:
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
							v.target = LOBBY_SPOTS[randi() % LOBBY_SPOTS.size()]
						else:
							v.target = v.spots.pop_front()
			"linger":
				if arrived:
					if v.wait <= 0.0:
						v.wait = randf_range(1.0, 2.6)
					v.wait -= dt
					if v.wait <= 0.0:
						v.state = "exit"
						v.target = DOOR_G
			"exit":
				if arrived:
					done.append(v)
	for v in done:
		_visitors.erase(v)
		v.node.queue_free()

## Grid-space movement. Facing flips on the projected x direction so characters
## turn the way they visually travel, not the way the grid axis points.
func _move(v: Visitor, dt: float) -> bool:
	var d: Vector2 = v.target - v.pos
	var dist: float = d.length()
	if dist < 0.06:
		v.node.walking = false
		return true
	var step: float = minf(v.speed * dt, dist)
	var before: float = v.node.position.x
	v.pos += d / dist * step
	_place(v.node, v.pos)
	v.node.facing = 1 if v.node.position.x >= before else -1
	v.node.walking = true
	return false

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
					p.target = Vector2(WINDOW_GX[best] + 0.8, COUNTER_GY + 0.5)
			"to_window":
				if _porter_move(p, dt):
					var take: int = mini(_stacks[p.window], 6)
					_stacks[p.window] -= take
					_stacks_dirty = true
					p.carried = take
					p.node.carry_stack = clampi(take, 1, 4)
					p.node.queue_redraw()
					p.state = "to_vault"
					p.target = VAULT_DROP
			"to_vault":
				if _porter_move(p, dt):
					p.carried = 0
					p.node.carry_stack = 0
					p.node.queue_redraw()
					_porter_trips += 1
					_pile_flash = 1.0
					_spawn_coin_burst(VAULT_DROP, 7)
					p.state = "idle"
					p.target = PORTER_HOME + Vector2(float(_porters.find(p)) * 0.7, 0.0)

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

# --- Ground: floors and walls --------------------------------------------------

func _room_floor(r: Rect2) -> Color:
	if r == R_GALLERY:
		return UI.ROOM_GALLERY.lerp(UI.FLOOR_CREAM, 0.40)
	if r == R_VAULT:
		return UI.ROOM_VAULT.lerp(UI.FLOOR_CREAM, 0.44)
	if r == R_PROMO:
		return UI.ROOM_PROMO.lerp(UI.FLOOR_CREAM, 0.44)
	if r == R_TICKET:
		return UI.ROOM_TICKET.lerp(UI.FLOOR_CREAM, 0.42)
	return UI.FLOOR_CREAM

func _draw_ground() -> void:
	# Outer slab, slightly proud of the rooms — reads as the building shell.
	Iso.floor_patch(_ground, Vector2(-0.35, -0.35), Iso.GRID + Vector2(0.7, 0.7),
		UI.WALL_BROWN.darkened(0.15))

	for spec in [[R_GALLERY, "gallery"], [R_VAULT, "archive"], [R_PROMO, "promotions"],
			[R_TICKET, "ticket"], [R_LOBBY, ""], [R_CORRIDOR, ""]]:
		var r: Rect2 = spec[0]
		var col: Color = _room_floor(r)
		Iso.floor_patch(_ground, r.position, r.size, col)
		Iso.floor_tiles(_ground, r.position, r.size, col.darkened(0.10))
		if str(spec[1]) != "" and _choke == str(spec[1]):
			# Bottleneck room: hot rim on the floor edge, readable at a glance.
			var ring := Iso.quad(r.position, r.size)
			ring.append(ring[0])
			_ground.draw_polyline(ring, UI.DANGER, 3.0)

	# Red carpet runner from the doors up through the lobby.
	Iso.floor_patch(_ground, Vector2(12.1, 10.2), Vector2(1.6, 6.8), UI.CARPET_RED)
	Iso.floor_patch(_ground, Vector2(12.25, 10.2), Vector2(1.3, 6.8), UI.CARPET_RED.lightened(0.14))

	_draw_floor_dressing()

	# Back walls along the two far edges, per room.
	Iso.wall(_ground, Vector2(0, 0), 9.0, "x", UI.ROOM_GALLERY.darkened(0.10))
	Iso.wall(_ground, Vector2(9, 0), 6.0, "x", UI.ROOM_VAULT.darkened(0.10))
	Iso.wall(_ground, Vector2(0, 0), 8.0, "y", UI.ROOM_GALLERY.darkened(0.22))
	Iso.wall(_ground, Vector2(0, 8), 6.0, "y", UI.ROOM_TICKET.darkened(0.22))
	Iso.wall(_ground, Vector2(0, 14), 3.0, "y", UI.ROOM_TICKET.darkened(0.30))
	# Low interior dividers.
	Iso.wall(_ground, Vector2(0, 9), 15.0, "x", UI.ROOM_TICKET.darkened(0.05), 16.0)
	Iso.wall(_ground, Vector2(9, 5), 6.0, "x", UI.ROOM_PROMO.darkened(0.05), 16.0)
	# Raised from 30 to 44 so the archive's vault door has a wall to hang on.
	Iso.wall(_ground, Vector2(9, 0), 5.0, "y", UI.ROOM_VAULT.darkened(0.18), 44.0)

	_draw_wall_art()
	_draw_ceiling_dressing()

## Painted floor: exhibit medallions, queue lanes, thresholds, doormat.
##
## All of it lives in the ground canvas item on purpose. A decal can never
## occlude an actor, so it needs neither a node nor a Y-sort slot, and drawing a
## run of polygons back to back inside one canvas item batches into a handful of
## draw calls. That is the whole trick behind this density pass: detail goes into
## existing canvas items, not into new ones.
func _draw_floor_dressing() -> void:
	var gal: Color = UI.ROOM_GALLERY.lerp(UI.FLOOR_CREAM, 0.40)
	Iso.rug(_ground, Vector2(1.1, 2.1), Vector2(4.3, 2.6), gal.darkened(0.12),
		UI.BRASS.darkened(0.20))
	Iso.rug(_ground, Vector2(6.0, 4.7), Vector2(2.0, 1.9), gal.darkened(0.12),
		UI.BRASS.darkened(0.20))
	Iso.rug(_ground, Vector2(0.2, 0.2), Vector2(8.6, 0.55), gal.darkened(0.06))
	# Queue lanes, one painted strip per window: floor markings are how the
	# reference tells the player where a line forms before anyone is standing in it.
	var tick: Color = UI.ROOM_TICKET.lerp(UI.FLOOR_CREAM, 0.42)
	for w in MAX_WINDOWS:
		Iso.rug(_ground, Vector2(WINDOW_GX[w] - 0.5, SLOT_GY[0] - 0.5),
			Vector2(1.0, SLOT_GY[SLOTS_PER_WINDOW - 1] - SLOT_GY[0] + 1.0),
			tick.darkened(0.07))
	Iso.rug(_ground, Vector2(0.4, 9.3), Vector2(14.2, 0.5), tick.darkened(0.13))
	# Threshold band through the corridor, so the cream gap between the gallery
	# and the ticket hall reads as a doorway rather than as a hole in the floor.
	Iso.rug(_ground, Vector2(0.3, 8.15), Vector2(8.4, 0.7), UI.FLOOR_CREAM.darkened(0.08),
		UI.WALL_BROWN.lightened(0.35))
	Iso.rug(_ground, Vector2(11.9, 16.1), Vector2(2.0, 0.8), UI.WALL_BROWN.darkened(0.05))
	Iso.rug(_ground, Vector2(3.4, 14.9), Vector2(4.2, 1.9), UI.FLOOR_CREAM.darkened(0.07))

## Framed pieces and signage hung on the two back walls.
func _draw_wall_art() -> void:
	var f := Vector2(4.6, 0.0)
	Iso.panel(_ground, f, 2.2, "x", 16.0, 44.0, UI.BRASS.darkened(0.28))
	Iso.panel(_ground, f + Vector2(0.16, 0.0), 1.88, "x", 19.0, 41.0, Color("#BFDCF2"))
	Iso.panel(_ground, f + Vector2(0.16, 0.0), 1.88, "x", 19.0, 27.0, Color("#7E9E78"),
		Color(0, 0, 0, 0))
	Iso.pip(_ground, Iso.to_screen(f + Vector2(1.5, 0.0)) + Vector2(0, -35.0), 5.0,
		Color("#F7DE93"))
	# A hung gallery, not three lonely rectangles: the north wall carries a row of
	# framed work and the west wall its own, all of them `panel` calls in a row so
	# the whole hang costs about what the three originals did.
	for spec in [[1.2, 0.9, 22.0, 38.0, "#8E6BB0"], [2.4, 0.7, 26.0, 36.0, "#3E7E8C"],
			[3.4, 0.8, 21.0, 34.0, "#B4653C"], [7.1, 1.0, 22.0, 40.0, "#4E7FB5"],
			[8.2, 0.6, 25.0, 35.0, "#C85A5A"]]:
		Iso.picture(_ground, Vector2(float(spec[0]), 0.0), float(spec[1]), "x",
			float(spec[2]), float(spec[3]), Color(str(spec[4])))
	for spec in [[0.9, 0.9, 21.0, 37.0, "#5FA86E"], [2.2, 0.7, 24.0, 35.0, "#D19A3E"],
			[3.6, 0.9, 20.0, 36.0, "#7A6BB5"], [5.2, 0.8, 23.0, 38.0, "#4FA3A5"],
			[6.6, 0.7, 25.0, 35.0, "#C77BA6"]]:
		Iso.picture(_ground, Vector2(0.0, float(spec[0])), float(spec[1]), "y",
			float(spec[2]), float(spec[3]), Color(str(spec[4])))
	# Ticket-hall notices along the low divider, and one on the lobby's west wall.
	for gx in [0.7, 3.3, 5.9, 8.5, 11.1]:
		Iso.panel(_ground, Vector2(gx, 9.0), 0.8, "x", 3.0, 13.0, UI.PANEL)
		Iso.panel(_ground, Vector2(gx + 0.12, 9.0), 0.56, "x", 5.0, 8.0,
			UI.ROOM_TICKET.darkened(0.10), Color(0, 0, 0, 0))
	# Promotions poster board.
	Iso.panel(_ground, Vector2(9.4, 5.0), 1.8, "x", 4.0, 24.0, UI.PANEL)
	Iso.panel(_ground, Vector2(11.6, 5.0), 1.4, "x", 4.0, 20.0, UI.PANEL_SOFT)
	Iso.pip(_ground, Iso.to_screen(Vector2(9.9, 5.0)) + Vector2(0, -16.0), 4.0, UI.ROOM_PROMO)
	Iso.pip(_ground, Iso.to_screen(Vector2(12.3, 5.0)) + Vector2(0, -13.0), 3.4, UI.BRASS)

## Bunting strung under the ceiling. Drawn last into the ground item, which is
## also the only layer it can live in for free: the strings hang above the top of
## the tallest wall, where nothing on the floor ever reaches them.
func _draw_ceiling_dressing() -> void:
	var flags: Array = [UI.ROOM_TICKET, UI.ROOM_GALLERY, UI.SAGE, UI.SLATE, UI.PLUM]
	Iso.bunting(_ground, Vector2(2.4, 0.0), Vector2(0.0, 2.4), 46.0, 9.0, flags, 5)
	Iso.bunting(_ground, Vector2(5.8, 0.0), Vector2(0.0, 5.4), 45.0, 15.0, flags, 8)
	Iso.bunting(_ground, Vector2(8.7, 0.0), Vector2(0.0, 7.8), 43.0, 22.0, flags, 11)
	Iso.bunting(_ground, Vector2(11.4, 17.0), Vector2(14.4, 17.0), 50.0, 7.0, flags, 5)

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
	var key: String = "%d" % _windows_active
	if key == _props_key and not _props.is_empty():
		return
	_props_key = key
	_clear_props()
	_build_ticket_props()
	_build_gallery_props()
	_build_vault_props()
	_build_promo_props()
	_build_lobby_props()

func _build_ticket_props() -> void:
	for w in _windows_active:
		var gx: float = WINDOW_GX[w]
		var idx: int = w
		_add_prop(Vector2(gx, COUNTER_GY), func(ci: CanvasItem) -> void:
			var g := Vector2(gx - 0.85, COUNTER_GY - 0.30)
			Iso.shadow(ci, g + Vector2(0.05, 0.10), Vector2(1.7, 0.62), 0.20)
			Iso.box(ci, g, Vector2(1.7, 0.6), 21.0, UI.ROOM_TICKET.darkened(0.06))
			Iso.box(ci, g + Vector2(-0.05, -0.05), Vector2(1.8, 0.7), 24.0,
				UI.BRASS, Color(0, 0, 0, 0.22))
			# Till, monitor and a paper tray. Adding detail INSIDE an existing prop
			# node is close to free: consecutive polygons in one canvas item batch,
			# where a second node would have cost its own draw calls.
			var mon: Vector2 = Iso.to_screen(Vector2(gx + 0.52, COUNTER_GY - 0.02)) \
				+ Vector2(0, -24.0)
			ci.draw_colored_polygon(PackedVector2Array([
				mon + Vector2(-8, -17), mon + Vector2(8, -17),
				mon + Vector2(8, -4), mon + Vector2(-8, -4)]), Color("#2B2245"))
			ci.draw_colored_polygon(PackedVector2Array([
				mon + Vector2(-6, -15), mon + Vector2(6, -15),
				mon + Vector2(6, -6), mon + Vector2(-6, -6)]), UI.SLATE.lightened(0.25))
			var tray: Vector2 = Iso.to_screen(Vector2(gx - 0.55, COUNTER_GY - 0.02)) \
				+ Vector2(0, -24.0)
			for k in 3:
				var ty: float = -float(k) * 2.6
				ci.draw_colored_polygon(PackedVector2Array([
					tray + Vector2(-8, ty), tray + Vector2(0, ty - 4),
					tray + Vector2(8, ty), tray + Vector2(0, ty + 4)]),
					UI.PANEL if k % 2 == 0 else UI.FLOOR_CREAM)
			# Glass screen across the customer face of the counter.
			Iso.panel(ci, g + Vector2(0.06, 0.62), 1.58, "x", 24.0, 43.0,
				Color(0.76, 0.92, 1.0, 0.28), Color(1, 1, 1, 0.34))
			var label: Vector2 = Iso.to_screen(Vector2(gx, COUNTER_GY - 0.02)) + Vector2(-4, -6)
			ci.draw_string(_font, label, str(idx + 1), HORIZONTAL_ALIGNMENT_LEFT, -1, 13,
				UI.FLOOR_CREAM))
		_add_queue_lane(gx, -0.62)
		_add_queue_lane(gx, 0.62)
	_add_prop(Vector2(14.2, 10.4), _bin_painter(Vector2(14.2, 10.4)))
	_add_prop(Vector2(3.55, 13.95), _planter_painter(Vector2(3.55, 13.95)))
	_add_prop(Vector2(14.6, 13.4), _planter_painter(Vector2(14.6, 13.4)))

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
	var anchor_gy: float = SLOT_GY[0] - 0.45
	if side > 0.0:
		anchor_gy = SLOT_GY[SLOTS_PER_WINDOW - 1] + 0.45
	_add_prop(Vector2(lane_gx, anchor_gy), func(ci: CanvasItem) -> void:
		# Grouped BY PRIMITIVE, not by post. The GL Compatibility batcher only
		# merges consecutive commands of the same kind, so shadow/rope/post/knob
		# per post made one lane cost about thirty draw calls; issuing all the
		# shadows, then all the ropes, then all the posts costs five, and the
		# painted order is the same because the groups never overlap each other.
		var pts: Array[Vector2] = []
		for j in SLOTS_PER_WINDOW:
			pts.append(Iso.to_screen(Vector2(lane_gx, SLOT_GY[j])))
		var ropes: Array = []
		for j in range(1, SLOTS_PER_WINDOW):
			var rope := PackedVector2Array()
			for k in 9:
				var t: float = float(k) / 8.0
				var p: Vector2 = (pts[j - 1] + Vector2(0, -25.0)).lerp(
					pts[j] + Vector2(0, -25.0), t)
				p.y += sin(t * PI) * 6.0
				rope.append(p)
			ropes.append(rope)
		for rope in ropes:
			Iso.stroke(ci, rope, UI.ROPE_RED.darkened(0.3), 3.6)
		for rope in ropes:
			Iso.stroke(ci, rope, UI.ROPE_RED, 2.0)
		for p in pts:
			ci.draw_line(p, p + Vector2(0, -26.0), UI.WALL_BROWN, 2.6)
		for p in pts:
			Iso.pip(ci, p + Vector2(0, -28.0), 3.6, UI.BRASS)
		for p in pts:
			Iso.pip(ci, p + Vector2(-1, -29.0), 1.6, UI.BRASS.lightened(0.4)))

func _build_gallery_props() -> void:
	_add_prop(Vector2(3.2, 3.4), func(ci: CanvasItem) -> void:
		var g := Vector2(1.6, 2.6)
		Iso.shadow(ci, g + Vector2(0.08, 0.12), Vector2(3.2, 1.3), 0.22)
		Iso.box(ci, g, Vector2(3.2, 1.2), 14.0, Color("#C9B896"))
		Iso.box(ci, g + Vector2(0.0, 1.04), Vector2(3.2, 0.16), 16.0, Color("#B3A281"))
		_draw_skeleton(ci, Iso.to_screen(g + Vector2(1.6, 0.6)) + Vector2(0, -14.0))
		_draw_barrier(ci, Vector2(1.4, 3.98), Vector2(5.0, 3.98), 4))
	_add_prop(Vector2(7.0, 5.6), func(ci: CanvasItem) -> void:
		var g := Vector2(6.5, 5.1)
		Iso.shadow(ci, g + Vector2(0.06, 0.10), Vector2(1.1, 1.1), 0.22)
		Iso.box(ci, g, Vector2(1.0, 1.0), 12.0, Color("#C9B896"))
		_draw_sarcophagus(ci, Iso.to_screen(g + Vector2(0.5, 0.5)) + Vector2(0, -12.0))
		_draw_barrier(ci, Vector2(6.3, 6.25), Vector2(7.7, 6.25), 3))
	_add_prop(Vector2(5.5, 2.1), _statue_painter(Vector2(5.0, 1.6), Vector2(1.0, 1.0)))
	_add_prop(Vector2(7.75, 2.75), _vitrine_painter(Vector2(7.0, 2.4), Vector2(1.5, 0.7),
		Color("#7FD4E8")))
	_add_prop(Vector2(1.45, 1.75), _case_painter(Vector2(0.7, 1.4), Vector2(1.5, 0.7)))
	_add_prop(Vector2(4.55, 5.85), _kiosk_painter(Vector2(4.3, 5.6)))
	for spec in [[Vector2(1.4, 6.6), 1.8], [Vector2(5.2, 6.9), 1.8], [Vector2(7.3, 6.4), 1.4]]:
		_add_prop((spec[0] as Vector2) + Vector2(float(spec[1]) * 0.5, 0.2),
			_bench_painter(spec[0], float(spec[1])))
	_add_prop(Vector2(8.5, 4.6), _bin_painter(Vector2(8.5, 4.6)))
	for pg in [Vector2(0.5, 7.4), Vector2(8.3, 0.6), Vector2(8.4, 7.5),
			Vector2(0.4, 4.9), Vector2(4.6, 0.5)]:
		_add_prop(pg, _planter_painter(pg))

## The archive furnishes a WEDGE, not a rectangle. Its east corner projects to
## x = 840 on a 720-wide canvas, so shelving that ran the full room width had its
## far half clipped away and the vault door was never on screen at all. Each rank
## steps one tile forward as it runs east, which is precisely how Iso.gx_window
## opens up with depth, so the room now reads as full to its visible edge.
func _build_vault_props() -> void:
	# Nothing tall in front of the door. A shelf bank at gy 1.9 projects into the
	# same screen wedge as a door on the gx = 9 divider and cut the vault dial in
	# half; the racking starts at gy 2.3 so the door stands clear above it.
	_add_prop(Vector2(9.0, 0.8), _vault_door_painter(Vector2(9.0, 0.1), 1.4))
	for spec in [[Vector2(9.6, 1.6), 1.6, 3], [Vector2(9.4, 2.6), 3.0, 6],
			[Vector2(9.4, 3.6), 4.0, 8], [Vector2(13.2, 4.6), 1.2, 2]]:
		var sg: Vector2 = spec[0]
		var sw: float = spec[1]
		_add_prop(sg + Vector2(sw * 0.5, 0.5),
			_shelf_painter(sg, Vector2(sw, 0.5), int(spec[2])))
	_add_prop(Vector2(11.6, 2.1), _crate_painter(Vector2(11.2, 1.5)))
	_add_prop(Vector2(10.2, 2.15), _trolley_painter(Vector2(10.2, 2.15)))
	_add_prop(Vector2(9.75, 5.1), _cabinet_painter(Vector2(9.4, 4.6), Vector2(0.7, 0.5)))
	_add_prop(Vector2(14.0, 4.7), _planter_painter(Vector2(14.0, 4.7)))

func _build_promo_props() -> void:
	for spec in [[Vector2(9.6, 6.4), 1.9], [Vector2(12.4, 6.9), 1.6]]:
		var dg: Vector2 = spec[0]
		var dl: float = spec[1]
		_add_prop(dg + Vector2(dl * 0.5, 0.3), func(ci: CanvasItem) -> void:
			Iso.shadow(ci, dg + Vector2(0.06, 0.10), Vector2(dl, 0.66), 0.20)
			Iso.box(ci, dg, Vector2(dl, 0.6), 18.0, Color("#9C7550"))
			var mon: Vector2 = Iso.to_screen(dg + Vector2(dl * 0.5, 0.3)) + Vector2(0, -18.0)
			ci.draw_colored_polygon(PackedVector2Array([
				mon + Vector2(-9, -20), mon + Vector2(9, -20),
				mon + Vector2(9, -6), mon + Vector2(-9, -6)]), Color("#2B2245"))
			ci.draw_colored_polygon(PackedVector2Array([
				mon + Vector2(-7, -18), mon + Vector2(7, -18),
				mon + Vector2(7, -8), mon + Vector2(-7, -8)]), UI.SLATE.lightened(0.2)))
	_add_prop(Vector2(13.9, 5.5), _banner_painter(Vector2(13.9, 5.5)))
	_add_prop(Vector2(10.65, 8.8), _bench_painter(Vector2(10.0, 8.3), 1.3))
	_add_prop(Vector2(13.0, 8.9), _rack_painter(Vector2(12.4, 8.4), Vector2(1.2, 0.5)))
	_add_prop(Vector2(14.4, 6.4), _balloon_painter(Vector2(14.4, 6.4)))
	_add_prop(Vector2(14.5, 8.7), _planter_painter(Vector2(14.5, 8.7)))

func _build_lobby_props() -> void:
	# Entrance facade. Two earlier attempts were wrong in instructive ways: the
	# original drew the doors as an axis-aligned screen-space rectangle standing
	# on open floor, so it floated at an angle that disagreed with every other
	# surface; moving it into the west wall then pushed it off the clipped left
	# edge, because at high gy that wall projects far to the left. It belongs in
	# a short facade on the lobby's NEAR edge (gy = 17), which is the only wall
	# plane by the entrance that stays inside the visible canvas.
	var fac := Vector2(11.4, 17.0)      # facade runs +x along the near edge
	var fac_len := 3.0
	var leaf := 0.62                    # each door leaf, in tiles
	_add_prop(Vector2(12.9, 17.0), func(ci: CanvasItem) -> void:
		Iso.wall(ci, fac, fac_len, "x", UI.ROOM_TICKET.darkened(0.34), 46.0)
		var d0: Vector2 = fac + Vector2(0.88, 0.0)
		# Reveal cut into the facade, then the two leaves, all in the wall plane.
		Iso.panel(ci, d0 - Vector2(0.14, 0.0), leaf * 2.0 + 0.28, "x", 0.0, 42.0,
			UI.WALL_BROWN.darkened(0.30))
		Iso.panel(ci, d0, leaf, "x", 2.0, 37.0, Color("#9A7350"))
		Iso.panel(ci, d0 + Vector2(leaf, 0.0), leaf, "x", 2.0, 37.0, Color("#8A6543"))
		# Fanlight over the lintel.
		Iso.panel(ci, d0 + Vector2(0.16, 0.0), leaf * 2.0 - 0.32, "x", 42.0, 52.0,
			UI.BRASS.darkened(0.18))
		var mid: Vector2 = Iso.to_screen(d0 + Vector2(leaf, 0.0))
		Iso.pip(ci, mid + Vector2(-4, -18), 2.6, UI.BRASS)
		Iso.pip(ci, mid + Vector2(4, -16), 2.6, UI.BRASS)
		# Daylight spilling across the threshold.
		Iso.floor_patch(ci, d0 - Vector2(0.0, 0.85), Vector2(leaf * 2.0, 0.85),
			Color(1.0, 0.95, 0.75, 0.14)))
	_add_prop(Vector2(5.5, 15.7), func(ci: CanvasItem) -> void:
		var g := Vector2(4.4, 15.0)
		Iso.shadow(ci, g + Vector2(0.06, 0.10), Vector2(2.3, 0.8), 0.20)
		Iso.box(ci, g, Vector2(2.2, 0.7), 20.0, UI.ROOM_TICKET.darkened(0.18))
		Iso.box(ci, g + Vector2(-0.05, -0.05), Vector2(2.3, 0.8), 23.0, UI.BRASS,
			Color(0, 0, 0, 0.22))
		var sign: Vector2 = Iso.to_screen(g + Vector2(1.1, 0.35)) + Vector2(0, -23.0)
		ci.draw_colored_polygon(PackedVector2Array([
			sign + Vector2(-16, -22), sign + Vector2(16, -22),
			sign + Vector2(16, -10), sign + Vector2(-16, -10)]), UI.PANEL)
		ci.draw_string(_font, sign + Vector2(-13, -13), "INFO",
			HORIZONTAL_ALIGNMENT_LEFT, -1, 11, UI.INK))
	_add_prop(Vector2(6.25, 16.8), _rack_painter(Vector2(5.4, 16.2), Vector2(1.7, 0.6)))
	for mg in [Vector2(6.7, 14.3), Vector2(7.6, 14.3)]:
		_add_prop(mg + Vector2(0.3, 0.45), _machine_painter(mg))
	_add_prop(Vector2(4.4, 14.9), _cabinet_painter(Vector2(3.6, 14.6), Vector2(1.6, 0.6)))
	_add_prop(Vector2(6.6, 16.6), _bench_painter(Vector2(6.0, 16.4), 1.2))
	_add_prop(Vector2(12.6, 14.6), _banner_painter(Vector2(12.6, 14.6)))
	_add_prop(Vector2(14.5, 15.8), _bench_painter(Vector2(14.0, 15.6), 1.0))
	for pg in [Vector2(6.2, 14.3), Vector2(14.6, 14.5), Vector2(5.1, 16.3),
			Vector2(11.6, 16.9), Vector2(4.2, 15.3)]:
		_add_prop(pg, _planter_painter(pg))

# --- Prop painters ------------------------------------------------------------

## Velvet barrier between two floor points — posts plus a swagged rope. Drawn
## inside an exhibit's own node so it sorts with the exhibit it protects.
func _draw_barrier(ci: CanvasItem, a: Vector2, b: Vector2, posts: int = 3) -> void:
	var pts: Array[Vector2] = []
	for i in posts:
		pts.append(Iso.to_screen(a.lerp(b, float(i) / float(maxi(posts - 1, 1)))))
	var ropes: Array = []
	for i in range(1, posts):
		var rope := PackedVector2Array()
		for k in 7:
			var u: float = float(k) / 6.0
			var p: Vector2 = (pts[i - 1] + Vector2(0, -20.0)).lerp(
				pts[i] + Vector2(0, -20.0), u)
			p.y += sin(u * PI) * 5.0
			rope.append(p)
		ropes.append(rope)
	for rope in ropes:
		Iso.stroke(ci, rope, UI.ROPE_RED.darkened(0.3), 3.2)
	for rope in ropes:
		Iso.stroke(ci, rope, UI.ROPE_RED, 1.8)
	for p in pts:
		ci.draw_line(p, p + Vector2(0, -21.0), UI.WALL_BROWN, 2.4)
	for p in pts:
		Iso.pip(ci, p + Vector2(0, -23.0), 3.2, UI.BRASS)

## Potted plant: terracotta pot plus leaf blades. Cheap, and the single most
## effective thing for making a floor look furnished rather than empty.
func _planter_painter(g: Vector2) -> Callable:
	return func(ci: CanvasItem) -> void:
		var base: Vector2 = Iso.to_screen(g)
		Iso.shadow(ci, g - Vector2(0.28, 0.28), Vector2(0.56, 0.56), 0.20)
		Iso.box(ci, g - Vector2(0.24, 0.24), Vector2(0.48, 0.48), 13.0, Color("#B4653C"))
		var top: Vector2 = base + Vector2(0, -13.0)
		var tips: Array[Vector2] = []
		for i in 6:
			var a: float = -PI * 0.5 + lerpf(-1.0, 1.0, float(i) / 5.0)
			tips.append(top + Vector2(cos(a), sin(a)) * 17.0)
		for tip in tips:
			ci.draw_line(top, tip, Color("#2F8F52"), 3.2)
		for tip in tips:
			ci.draw_line(top, tip.lerp(top, 0.35), Color("#46B86A"), 2.0)

## Bench: seat slab plus a back rail.
func _bench_painter(g: Vector2, length: float) -> Callable:
	return func(ci: CanvasItem) -> void:
		Iso.shadow(ci, g + Vector2(0.05, 0.08), Vector2(length, 0.5), 0.18)
		Iso.box(ci, g, Vector2(length, 0.42), 9.0, Color("#A9793F"))
		Iso.box(ci, g + Vector2(0.0, 0.06), Vector2(length, 0.10), 22.0, Color("#8A6033"))

## Waste bin — a lidded drum. The one prop that says "public building".
func _bin_painter(g: Vector2) -> Callable:
	return func(ci: CanvasItem) -> void:
		Iso.shadow(ci, g - Vector2(0.20, 0.20), Vector2(0.40, 0.40), 0.18)
		Iso.cyl(ci, g, 0.18, 20.0, Color("#5C6B8A"))
		Iso.cyl(ci, g, 0.20, 22.0, Color("#46536D"))

## Stone figure on a plinth.
func _statue_painter(g: Vector2, size: Vector2) -> Callable:
	return func(ci: CanvasItem) -> void:
		Iso.shadow(ci, g + Vector2(0.06, 0.10), size + Vector2(0.06, 0.06), 0.22)
		Iso.box(ci, g, size, 26.0, Color("#C9B896"))
		var at: Vector2 = Iso.to_screen(g + size * 0.5) + Vector2(0.0, -26.0)
		var stone := Color("#E6DCC4")
		var edge := Color("#9C8C6E")
		ci.draw_colored_polygon(PackedVector2Array([
			at + Vector2(-7, 0), at + Vector2(7, 0),
			at + Vector2(5, -25), at + Vector2(-5, -25)]), stone)
		ci.draw_line(at + Vector2(-6, -21), at + Vector2(-13, -33), stone, 4.6)
		ci.draw_line(at + Vector2(6, -21), at + Vector2(12, -29), stone, 4.6)
		ci.draw_circle(at + Vector2(0, -32), 6.2, stone)
		ci.draw_arc(at + Vector2(0, -32), 6.2, 0.0, TAU, 16, edge, 1.6)
		ci.draw_line(at + Vector2(-7, -1), at + Vector2(7, -1), edge, 1.8)

## Glass display case with an artefact standing inside it.
func _vitrine_painter(g: Vector2, size: Vector2, art: Color) -> Callable:
	return func(ci: CanvasItem) -> void:
		Iso.shadow(ci, g + Vector2(0.06, 0.10), size + Vector2(0.06, 0.06), 0.20)
		Iso.box(ci, g, size, 15.0, Color("#7E6C52"))
		var c: Vector2 = Iso.to_screen(g + size * 0.5) + Vector2(0.0, -15.0)
		ci.draw_colored_polygon(PackedVector2Array([
			c + Vector2(-9, -10), c + Vector2(0, -21),
			c + Vector2(9, -10), c + Vector2(0, 1)]), art)
		ci.draw_colored_polygon(PackedVector2Array([
			c + Vector2(-4, -12), c + Vector2(0, -18),
			c + Vector2(3, -11), c + Vector2(0, -5)]), art.lightened(0.42))
		ci.draw_line(c + Vector2(-8, -6), c + Vector2(8, -6), art.darkened(0.30), 2.0)
		Iso.box(ci, g + Vector2(0.05, 0.05), size - Vector2(0.10, 0.10), 30.0,
			Color(0.78, 0.92, 1.0, 0.20), Color(1, 1, 1, 0.34))

## Low mineral cabinet with a lit glass top.
func _case_painter(g: Vector2, size: Vector2) -> Callable:
	return func(ci: CanvasItem) -> void:
		Iso.shadow(ci, g + Vector2(0.06, 0.10), size + Vector2(0.06, 0.06), 0.20)
		Iso.box(ci, g, size, 17.0, Color("#7E6C52"))
		var c: Vector2 = Iso.to_screen(g + size * 0.5) + Vector2(0.0, -17.0)
		for spec in [[-10.0, Color("#7ED8F0")], [0.0, Color("#F08CC4")],
				[10.0, Color("#9CE8A8")]]:
			var p: Vector2 = c + Vector2(float(spec[0]), 0.0)
			ci.draw_colored_polygon(PackedVector2Array([
				p + Vector2(-4, -1), p + Vector2(0, -8),
				p + Vector2(4, -1), p + Vector2(0, 3)]), spec[1])
		Iso.box(ci, g + Vector2(0.04, 0.04), size - Vector2(0.08, 0.08), 21.0,
			Color(0.80, 0.93, 1.0, 0.28), Color(1, 1, 1, 0.36))

## Audio-guide pedestal: a stalk with a tilted screen on top.
func _kiosk_painter(g: Vector2) -> Callable:
	return func(ci: CanvasItem) -> void:
		Iso.shadow(ci, g - Vector2(0.02, 0.02), Vector2(0.5, 0.5), 0.18)
		Iso.box(ci, g, Vector2(0.34, 0.34), 30.0, Color("#5C6B8A"))
		var at: Vector2 = Iso.to_screen(g + Vector2(0.17, 0.17)) + Vector2(0, -30.0)
		ci.draw_colored_polygon(PackedVector2Array([
			at + Vector2(-11, -6), at + Vector2(2, -12),
			at + Vector2(11, -5), at + Vector2(-2, 1)]), Color("#2B2245"))
		ci.draw_colored_polygon(PackedVector2Array([
			at + Vector2(-8, -6), at + Vector2(2, -10),
			at + Vector2(8, -5), at + Vector2(-2, -1)]), UI.SAGE.darkened(0.10))

## Shelving bank: uprights carrying cash bundles and ledger boxes.
func _shelf_painter(g: Vector2, size: Vector2, bays: int) -> Callable:
	return func(ci: CanvasItem) -> void:
		Iso.shadow(ci, g + Vector2(0.06, 0.10), size + Vector2(0.06, 0.06), 0.20)
		Iso.box(ci, g, size, 30.0, Color("#5D7B96"))
		var step: float = (size.x - 0.5) / float(maxi(bays - 1, 1))
		var tops: Array[Vector2] = []
		for i in bays:
			tops.append(Iso.to_screen(Vector2(g.x + 0.25 + float(i) * step,
				g.y + size.y * 0.5)) + Vector2(0, -30.0))
		for top in tops:
			ci.draw_colored_polygon(PackedVector2Array([
				top + Vector2(-7, -3), top + Vector2(2, -7),
				top + Vector2(9, -3), top + Vector2(0, 1)]), Color("#4ADE80"))
		for i in bays:
			if i % 2 == 0:
				ci.draw_colored_polygon(PackedVector2Array([
					tops[i] + Vector2(-6, -10), tops[i] + Vector2(1, -14),
					tops[i] + Vector2(7, -10), tops[i] + Vector2(0, -6)]), Color("#C9B896"))
		for top in tops:
			ci.draw_line(top + Vector2(-4, -3), top + Vector2(5, -6), Color("#22A45A"), 1.4)

## Stack of archive crates, tapering as it goes up.
func _crate_painter(g: Vector2) -> Callable:
	return func(ci: CanvasItem) -> void:
		Iso.shadow(ci, g + Vector2(0.06, 0.10), Vector2(0.8, 0.6), 0.20)
		Iso.box(ci, g, Vector2(0.8, 0.6), 15.0, Color("#A9793F"))
		Iso.box(ci, g + Vector2(0.10, 0.08), Vector2(0.58, 0.44), 27.0, Color("#BE8B4E"))
		Iso.box(ci, g + Vector2(0.20, 0.16), Vector2(0.40, 0.30), 36.0, Color("#8A6033"))

## Porter's hand trolley, parked between the racks.
func _trolley_painter(g: Vector2) -> Callable:
	return func(ci: CanvasItem) -> void:
		var base: Vector2 = Iso.to_screen(g)
		Iso.shadow(ci, g - Vector2(0.24, 0.16), Vector2(0.48, 0.32), 0.18)
		ci.draw_line(base + Vector2(-7, 0), base + Vector2(-7, -30), Color("#46536D"), 2.6)
		ci.draw_line(base + Vector2(7, 0), base + Vector2(7, -30), Color("#46536D"), 2.6)
		ci.draw_line(base + Vector2(-8, -30), base + Vector2(8, -30), Color("#46536D"), 2.6)
		Iso.box(ci, g - Vector2(0.20, 0.14), Vector2(0.40, 0.28), 18.0, Color("#BE8B4E"))
		Iso.pip(ci, base + Vector2(-7, -1), 3.0, Color("#2B2245"))
		Iso.pip(ci, base + Vector2(7, -1), 3.0, Color("#2B2245"))

## Filing cabinet with drawer faces.
func _cabinet_painter(g: Vector2, size: Vector2) -> Callable:
	return func(ci: CanvasItem) -> void:
		Iso.shadow(ci, g + Vector2(0.05, 0.08), size + Vector2(0.05, 0.05), 0.20)
		Iso.box(ci, g, size, 34.0, Color("#4E6B84"))
		var f: Vector2 = Iso.to_screen(g + Vector2(size.x * 0.5, size.y))
		for k in 3:
			var y: float = -8.0 - float(k) * 9.0
			ci.draw_line(f + Vector2(-10, y), f + Vector2(10, y - 6),
				Color("#8FA9C8"), 2.0)

## The archive's vault door, hung on the divider wall that faces the gallery.
## It used to be drawn into the ground layer at grid x = 12 on the archive's own
## back wall, which projects to canvas x = 750 — thirty pixels past the clip
## edge, so the museum's signature prop had never rendered a single pixel.
func _vault_door_painter(g: Vector2, length: float) -> Callable:
	return func(ci: CanvasItem) -> void:
		Iso.panel(ci, g, length, "y", 0.0, 40.0, UI.ROOM_VAULT.darkened(0.42))
		var vc: Vector2 = Iso.to_screen(g + Vector2(0.0, length * 0.5)) + Vector2(0, -21.0)
		ci.draw_circle(vc, 19.0, Color("#3C5068"))
		ci.draw_circle(vc, 16.0, Color("#5B7896"))
		ci.draw_circle(vc, 13.5, Color("#8FA9C8"))
		for i in 8:
			var a: float = TAU * float(i) / 8.0
			ci.draw_line(vc + Vector2(cos(a), sin(a)) * 4.5,
				vc + Vector2(cos(a), sin(a)) * 12.0, Color("#4A627E"), 2.2)
		ci.draw_circle(vc, 4.6, Color("#3C5068"))
		ci.draw_circle(vc, 2.8, UI.BRASS)

## Roll-up promotional banner.
func _banner_painter(g: Vector2) -> Callable:
	return func(ci: CanvasItem) -> void:
		Iso.shadow(ci, g - Vector2(0.22, 0.10), Vector2(0.44, 0.20), 0.18)
		var base: Vector2 = Iso.to_screen(g)
		ci.draw_line(base + Vector2(-12, 0), base + Vector2(12, 0), UI.SLATE.darkened(0.4), 3.0)
		ci.draw_colored_polygon(PackedVector2Array([
			base + Vector2(-11, -4), base + Vector2(11, -4),
			base + Vector2(11, -52), base + Vector2(-11, -52)]), UI.ROOM_PROMO)
		ci.draw_colored_polygon(PackedVector2Array([
			base + Vector2(-8, -10), base + Vector2(8, -10),
			base + Vector2(8, -30), base + Vector2(-8, -30)]), UI.PANEL)
		Iso.pip(ci, base + Vector2(0, -40), 6.0, UI.BRASS)

## Leaflet / merchandise rack.
func _rack_painter(g: Vector2, size: Vector2) -> Callable:
	return func(ci: CanvasItem) -> void:
		Iso.shadow(ci, g + Vector2(0.05, 0.08), size + Vector2(0.05, 0.05), 0.20)
		Iso.box(ci, g, size, 16.0, Color("#9C7550"))
		var at: Vector2 = Iso.to_screen(g + size * 0.5) + Vector2(0, -16.0)
		for i in 4:
			var p: Vector2 = at + Vector2(-13.0 + float(i) * 8.5, -float(i % 2) * 2.0)
			ci.draw_colored_polygon(PackedVector2Array([
				p + Vector2(-4, 0), p + Vector2(0, -14),
				p + Vector2(4, -12), p + Vector2(0, 2)]),
				[UI.SAGE, UI.SLATE, UI.PLUM, UI.ACCENT][i])

## Self-service ticket machine.
func _machine_painter(g: Vector2) -> Callable:
	return func(ci: CanvasItem) -> void:
		Iso.shadow(ci, g + Vector2(0.05, 0.08), Vector2(0.7, 0.6), 0.20)
		Iso.box(ci, g, Vector2(0.7, 0.55), 32.0, Color("#46536D"))
		var at: Vector2 = Iso.to_screen(g + Vector2(0.35, 0.55)) + Vector2(0, -32.0)
		# Screen raked toward the customer, card slot and ticket mouth below it.
		ci.draw_colored_polygon(PackedVector2Array([
			at + Vector2(-13, -2), at + Vector2(0, -9),
			at + Vector2(13, -2), at + Vector2(0, 5)]), Color("#2B2245"))
		ci.draw_colored_polygon(PackedVector2Array([
			at + Vector2(-10, -2), at + Vector2(0, -7),
			at + Vector2(10, -2), at + Vector2(0, 3)]), UI.SAGE.darkened(0.10))
		ci.draw_line(at + Vector2(-8, 12), at + Vector2(8, 12), UI.BRASS, 2.6)
		ci.draw_line(at + Vector2(-6, 19), at + Vector2(6, 19), UI.PANEL, 2.2)

## Helium balloon cluster over the promotions desk.
func _balloon_painter(g: Vector2) -> Callable:
	return func(ci: CanvasItem) -> void:
		var base: Vector2 = Iso.to_screen(g)
		var specs: Array = [[-8.0, -46.0, UI.ROOM_PROMO], [4.0, -54.0, UI.ROOM_TICKET],
			[11.0, -42.0, UI.SLATE]]
		for spec in specs:
			ci.draw_line(base + Vector2(0, -6),
				base + Vector2(float(spec[0]), float(spec[1])), Color(1, 1, 1, 0.45), 1.2)
		for spec in specs:
			ci.draw_circle(base + Vector2(float(spec[0]), float(spec[1])), 7.0, spec[2])
		for spec in specs:
			Iso.pip(ci, base + Vector2(float(spec[0]) - 2.0, float(spec[1]) - 2.0),
				2.4, Color(1, 1, 1, 0.55))

func _draw_skeleton(ci: CanvasItem, at: Vector2) -> void:
	var bone := Color("#F3EAD6")
	var edge := Color("#6E5C3C")
	var spine := PackedVector2Array()
	for i in 13:
		var t: float = float(i) / 12.0
		spine.append(at + Vector2(lerpf(-52.0, 52.0, t), -26.0 - sin(t * PI) * 20.0))
	Iso.stroke(ci, spine, edge, 8.0)
	Iso.stroke(ci, spine, bone, 4.6)
	for p in spine:
		Iso.pip(ci, p, 3.0, edge)
	for p in spine:
		Iso.pip(ci, p, 1.8, bone)
	for i in range(3, 10, 2):
		ci.draw_arc(spine[i] + Vector2(0, 2), 13.0, 0.10 * PI, 0.90 * PI, 10, edge, 4.6)
	for i in range(3, 10, 2):
		ci.draw_arc(spine[i] + Vector2(0, 2), 13.0, 0.10 * PI, 0.90 * PI, 10, bone, 2.4)
	var tail := PackedVector2Array([spine[0], spine[0] + Vector2(-16, 4),
		spine[0] + Vector2(-28, -4)])
	Iso.stroke(ci, tail, edge, 6.0)
	Iso.stroke(ci, tail, bone, 3.0)
	var neck := PackedVector2Array([spine[12], spine[12] + Vector2(12, -12),
		spine[12] + Vector2(20, -26)])
	Iso.stroke(ci, neck, edge, 7.0)
	Iso.stroke(ci, neck, bone, 3.8)
	var skull: Vector2 = spine[12] + Vector2(24, -30)
	var head := PackedVector2Array([
		skull + Vector2(-8, -6), skull + Vector2(6, -7), skull + Vector2(16, -1),
		skull + Vector2(17, 3), skull + Vector2(4, 5), skull + Vector2(-7, 3)])
	ci.draw_colored_polygon(head, bone)
	var ring := head.duplicate()
	ring.append(head[0])
	Iso.stroke(ci, ring, edge, 2.4)
	Iso.pip(ci, skull + Vector2(2, -2), 2.2, edge)
	var legs: Array = []
	for lx in [-34.0, -12.0, 16.0, 34.0]:
		legs.append([at + Vector2(lx, -26.0 - sin((lx + 52.0) / 104.0 * PI) * 20.0 + 4.0),
			at + Vector2(lx - 3, 0)])
	for leg in legs:
		ci.draw_line(leg[0], leg[1], edge, 6.4)
	for leg in legs:
		ci.draw_line(leg[0], leg[1], bone, 3.4)

func _draw_sarcophagus(ci: CanvasItem, at: Vector2) -> void:
	var lid := PackedVector2Array()
	for i in 13:
		var a: float = PI + PI * float(i) / 12.0
		lid.append(at + Vector2(0, -30) + Vector2(cos(a) * 17.0, sin(a) * 20.0))
	lid.append(at + Vector2(17, 0))
	lid.append(at + Vector2(-17, 0))
	ci.draw_colored_polygon(lid, Color("#D2A047"))
	ci.draw_line(at + Vector2(-8, -44), at + Vector2(-8, -4), Color(1, 1, 1, 0.22), 5.0)
	ci.draw_colored_polygon(PackedVector2Array([
		at + Vector2(-11, -40), at + Vector2(11, -40),
		at + Vector2(11, -28), at + Vector2(-11, -28)]), Color("#3E7E8C"))
	Iso.pip(ci, at + Vector2(-5, -34), 2.6, UI.PANEL)
	Iso.pip(ci, at + Vector2(5, -34), 2.6, UI.PANEL)
	ci.draw_line(at + Vector2(-10, -20), at + Vector2(10, -20), Color("#3E7E8C"), 3.4)
	ci.draw_line(at + Vector2(-8, -12), at + Vector2(8, -12), Color("#357280"), 2.6)
	var ring := lid.duplicate()
	ring.append(lid[0])
	Iso.stroke(ci, ring, Color("#8A6524"), 2.2)

# --- Dynamic layers -------------------------------------------------------------

func _draw_stacks() -> void:
	# Ticket-stub bundles piling beside each counter; an archive choke lets them
	# overflow, which is the visual tell that transport is the bottleneck.
	var cap: int = MAX_STACK_VIS * 2 if _choke == "archive" else MAX_STACK_VIS
	for w in _windows_active:
		var n: int = mini(_stacks[w], cap)
		var anchor: Vector2 = Iso.to_screen(Vector2(WINDOW_GX[w] + 1.0, COUNTER_GY)) \
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
	for spec in [[R_GALLERY, UI.ROOM_GALLERY, "GRAND GALLERY"],
			[R_VAULT, UI.ROOM_VAULT, "THE ARCHIVE"],
			[R_PROMO, UI.ROOM_PROMO, "PROMOTIONS"],
			[R_TICKET, UI.ROOM_TICKET, "TICKET HALL"]]:
		var r: Rect2 = spec[0]
		var at: Vector2 = Iso.to_screen(
			PLAQUE_G.get(_dept_of(r), r.position + r.size * 0.5)) + Vector2(0, -8)
		_draw_plaque(at, str(spec[2]), spec[1])

func _dept_of(r: Rect2) -> String:
	for dept_id in TAP_ZONES.keys():
		if TAP_ZONES[dept_id] == r:
			return dept_id
	return ""

## Room name on a floating plaque at the room's centre, on its own layer: an
## earlier pass drew labels onto the floor, where the cast walked through them.
func _draw_plaque(center: Vector2, title: String, accent: Color) -> void:
	var w: float = float(_font.get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x) + 16.0
	var plate := Rect2(center.x - w * 0.5, center.y - 10.0, w, 20.0)
	_labels_layer.draw_rect(Rect2(plate.position + Vector2(1.5, 2.0), plate.size),
		Color(0.06, 0.04, 0.14, 0.40))
	_labels_layer.draw_rect(plate, accent.darkened(0.58))
	_labels_layer.draw_rect(plate, accent.lightened(0.25), false, 1.5)
	_labels_layer.draw_string(_font, Vector2(plate.position.x + 8.0, plate.position.y + 15.0),
		title, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, UI.FLOOR_CREAM)
