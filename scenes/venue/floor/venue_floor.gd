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
const DOOR_G := Vector2(12.9, 16.3)  # just inside the entrance facade
const COUNTER_GY := 10.1
const WINDOW_GX: Array[float] = [1.5, 4.2, 6.9, 9.6, 12.3]
const SLOT_GY: Array[float] = [11.4, 12.2, 13.0, 13.8]
const MAX_WINDOWS := 5
const SLOTS_PER_WINDOW := 4
const MAX_ALIVE := 28
const MAX_CROWD := 6
const MAX_STACK_VIS := 10
const PORTER_HOME := Vector2(10.6, 4.2)
const VAULT_DROP := Vector2(12.4, 1.4)
const PILE_G := Vector2(13.4, 1.2)
const MARKETER_G := Vector2(11.3, 16.2)  # touting beside the entrance
const BROWSE_SPOTS := {
	"dino": [Vector2(2.2, 4.2), Vector2(4.4, 4.4), Vector2(3.2, 5.0)],
	"painting": [Vector2(5.4, 1.4), Vector2(6.6, 1.6)],
	"sarcophagus": [Vector2(6.4, 6.2), Vector2(7.6, 5.4)],
}
const EXHIBIT_KEYS: Array[String] = ["dino", "painting", "sarcophagus"]

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
	_marketer.set_uniform(UI.ROOM_PROMO)
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
		c.set_uniform(UI.ROOM_TICKET)
		c.facing = 1
		_canvas.add_child(c)
		_place(c, Vector2(WINDOW_GX[i], COUNTER_GY - 0.7))
		_staff_nodes.append(c)
	while _staff_nodes.size() > _windows_active:
		_staff_nodes.pop_back().queue_free()

	var docents: int = clampi(_staff_level("gallery"), 0, 2)
	while _docent_nodes.size() < docents:
		var c: Character = Character.new()
		c.set_uniform(UI.ROOM_GALLERY.darkened(0.2))
		_canvas.add_child(c)
		_place(c, [Vector2(1.2, 2.6), Vector2(7.4, 3.2)][_docent_nodes.size()])
		_docent_nodes.append(c)
	while _docent_nodes.size() > docents:
		_docent_nodes.pop_back().queue_free()

	var clerks: int = clampi(_staff_level("promotions"), 1, 2)
	while _promo_nodes.size() < clerks:
		var c: Character = Character.new()
		c.set_uniform(UI.ROOM_PROMO)
		_canvas.add_child(c)
		_place(c, [Vector2(10.4, 7.2), Vector2(12.0, 7.6)][_promo_nodes.size()])
		_promo_nodes.append(c)
	while _promo_nodes.size() > clerks:
		_promo_nodes.pop_back().queue_free()

	var porters: int = clampi(_staff_level("archive"), 1, 3)
	while _porters.size() < porters:
		var p := Porter.new()
		var c: Character = Character.new()
		c.set_uniform(UI.ROOM_VAULT)
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
	var interval: float = clampf(1.0 / clampf(_arrival, 0.2, 3.0), 1.2, 6.0)
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
	c.randomize_look(randi())
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

func _crowd_slot(i: int) -> Vector2:
	return Vector2(6.4 + float(i % 3) * 1.1, 15.0 + float(i / 3) * 0.9)

func _assign_to_window(v: Visitor, w: int) -> void:
	if v.state == "crowd":
		_crowd.erase(v)
	v.state = "to_queue"
	v.window = w
	_queues[w].append(v)
	v.target = _slot_pos(w, _queues[w].size() - 1)

func _slot_pos(w: int, idx: int) -> Vector2:
	return Vector2(WINDOW_GX[w], SLOT_GY[clampi(idx, 0, SLOTS_PER_WINDOW - 1)])

func _serve_time() -> float:
	var per_window: float = clampf(_serve, 0.25, 3.0) / float(maxi(_windows_active, 1))
	return clampf(1.0 / per_window, 0.6, 8.0)

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
	for k in keys.slice(0, randi_range(1, 2)):
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
							v.state = "exit"
							v.target = DOOR_G
						else:
							v.target = v.spots.pop_front()
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
			coin.draw_circle(Vector2.ZERO, 4.4, UI.BRASS.darkened(0.25))
			coin.draw_circle(Vector2(-0.6, -0.6), 3.2, UI.BRASS.lightened(0.25)))
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

	# Back walls along the two far edges, per room.
	Iso.wall(_ground, Vector2(0, 0), 9.0, "x", UI.ROOM_GALLERY.darkened(0.10))
	Iso.wall(_ground, Vector2(9, 0), 6.0, "x", UI.ROOM_VAULT.darkened(0.10))
	Iso.wall(_ground, Vector2(0, 0), 8.0, "y", UI.ROOM_GALLERY.darkened(0.22))
	Iso.wall(_ground, Vector2(0, 8), 6.0, "y", UI.ROOM_TICKET.darkened(0.22))
	Iso.wall(_ground, Vector2(0, 14), 3.0, "y", UI.ROOM_TICKET.darkened(0.30))
	# Low interior dividers.
	Iso.wall(_ground, Vector2(0, 9), 15.0, "x", UI.ROOM_TICKET.darkened(0.05), 16.0)
	Iso.wall(_ground, Vector2(9, 5), 6.0, "x", UI.ROOM_PROMO.darkened(0.05), 16.0)
	Iso.wall(_ground, Vector2(9, 0), 5.0, "y", UI.ROOM_VAULT.darkened(0.18), 30.0)

	_draw_wall_art()

## Framed pieces and signage hung on the two back walls.
func _draw_wall_art() -> void:
	var f := Vector2(4.6, 0.0)
	Iso.panel(_ground, f, 2.2, "x", 16.0, 44.0, UI.BRASS.darkened(0.28))
	Iso.panel(_ground, f + Vector2(0.16, 0.0), 1.88, "x", 19.0, 41.0, Color("#BFDCF2"))
	Iso.panel(_ground, f + Vector2(0.16, 0.0), 1.88, "x", 19.0, 27.0, Color("#7E9E78"),
		Color(0, 0, 0, 0))
	_ground.draw_circle(Iso.to_screen(f + Vector2(1.5, 0.0)) + Vector2(0, -35.0), 5.0,
		Color("#F7DE93"))
	for gx in [1.4, 7.0]:
		Iso.panel(_ground, Vector2(gx, 0.0), 0.9, "x", 22.0, 38.0, UI.BRASS.darkened(0.34))
		Iso.panel(_ground, Vector2(gx + 0.1, 0.0), 0.7, "x", 24.0, 36.0,
			UI.PANEL_SOFT, Color(0, 0, 0, 0))
	# Archive vault door, set into its back wall.
	var vc: Vector2 = Iso.to_screen(Vector2(12.0, 0.0)) + Vector2(0, -26.0)
	_ground.draw_circle(vc, 25.0, Color("#3C5068"))
	_ground.draw_circle(vc, 21.0, Color("#5B7896"))
	_ground.draw_circle(vc, 18.0, Color("#8FA9C8"))
	for i in 8:
		var a: float = TAU * float(i) / 8.0
		_ground.draw_line(vc + Vector2(cos(a), sin(a)) * 6.0,
			vc + Vector2(cos(a), sin(a)) * 16.0, Color("#4A627E"), 2.4)
	_ground.draw_circle(vc, 6.0, Color("#3C5068"))
	_ground.draw_circle(vc, 3.4, UI.BRASS)
	# Promotions poster board.
	Iso.panel(_ground, Vector2(9.4, 5.0), 1.8, "x", 4.0, 24.0, UI.PANEL)
	_ground.draw_circle(Iso.to_screen(Vector2(9.9, 5.0)) + Vector2(0, -16.0), 4.0, UI.ROOM_PROMO)

# --- Props: individual Y-sorted furniture nodes --------------------------------

## Adds one static prop. Each is its own node positioned at its grid anchor so
## Y-sort can interleave it with the moving cast; the painter works in absolute
## canvas coordinates and cancels the node offset with a draw transform.
func _add_prop(g: Vector2, painter: Callable) -> void:
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
			var label: Vector2 = Iso.to_screen(Vector2(gx, COUNTER_GY - 0.02)) + Vector2(-4, -6)
			ci.draw_string(_font, label, str(idx + 1), HORIZONTAL_ALIGNMENT_LEFT, -1, 13,
				UI.FLOOR_CREAM))
		for side in [-0.62, 0.62]:
			for j in SLOTS_PER_WINDOW:
				var sg := Vector2(gx + side, SLOT_GY[j])
				var prev_gy: float = SLOT_GY[j - 1] if j > 0 else -1.0
				_add_prop(sg, func(ci: CanvasItem) -> void:
					var base: Vector2 = Iso.to_screen(sg)
					Iso.shadow(ci, sg - Vector2(0.1, 0.1), Vector2(0.2, 0.2), 0.20)
					ci.draw_line(base, base + Vector2(0, -26.0), UI.WALL_BROWN, 2.6)
					ci.draw_circle(base + Vector2(0, -28.0), 3.6, UI.BRASS)
					ci.draw_circle(base + Vector2(-1, -29.0), 1.6, UI.BRASS.lightened(0.4))
					if prev_gy >= 0.0:
						var prev: Vector2 = Iso.to_screen(Vector2(sg.x, prev_gy))
						var rope := PackedVector2Array()
						for k in 9:
							var t: float = float(k) / 8.0
							var p: Vector2 = (prev + Vector2(0, -25.0)).lerp(
								base + Vector2(0, -25.0), t)
							p.y += sin(t * PI) * 6.0
							rope.append(p)
						ci.draw_polyline(rope, UI.ROPE_RED.darkened(0.3), 3.6)
						ci.draw_polyline(rope, UI.ROPE_RED, 2.0))

func _build_gallery_props() -> void:
	_add_prop(Vector2(3.2, 3.4), func(ci: CanvasItem) -> void:
		var g := Vector2(1.6, 2.6)
		Iso.shadow(ci, g + Vector2(0.08, 0.12), Vector2(3.2, 1.3), 0.22)
		Iso.box(ci, g, Vector2(3.2, 1.2), 14.0, Color("#C9B896"))
		_draw_skeleton(ci, Iso.to_screen(g + Vector2(1.6, 0.6)) + Vector2(0, -14.0)))
	_add_prop(Vector2(7.0, 5.6), func(ci: CanvasItem) -> void:
		var g := Vector2(6.5, 5.1)
		Iso.shadow(ci, g + Vector2(0.06, 0.10), Vector2(1.1, 1.1), 0.22)
		Iso.box(ci, g, Vector2(1.0, 1.0), 12.0, Color("#C9B896"))
		_draw_sarcophagus(ci, Iso.to_screen(g + Vector2(0.5, 0.5)) + Vector2(0, -12.0)))
	for spec in [[Vector2(1.4, 6.6), 1.8], [Vector2(5.2, 6.9), 1.8]]:
		var bg: Vector2 = spec[0]
		var bl: float = spec[1]
		_add_prop(bg + Vector2(bl * 0.5, 0.2), func(ci: CanvasItem) -> void:
			Iso.shadow(ci, bg + Vector2(0.05, 0.08), Vector2(bl, 0.5), 0.18)
			Iso.box(ci, bg, Vector2(bl, 0.42), 9.0, Color("#A9793F"))
			Iso.box(ci, bg + Vector2(0.0, 0.06), Vector2(bl, 0.10), 22.0, Color("#8A6033")))
	for pg in [Vector2(0.5, 7.4), Vector2(8.3, 0.6), Vector2(8.3, 7.4)]:
		_add_prop(pg, _planter_painter(pg))

func _build_vault_props() -> void:
	for row in [1.9, 3.1]:
		var gy: float = row
		_add_prop(Vector2(12.0, gy), func(ci: CanvasItem) -> void:
			var g := Vector2(9.5, gy)
			Iso.shadow(ci, g + Vector2(0.06, 0.10), Vector2(5.0, 0.6), 0.20)
			Iso.box(ci, g, Vector2(5.0, 0.55), 30.0, Color("#5D7B96"))
			for i in 9:
				var bx: float = g.x + 0.25 + float(i) * 0.52
				var top: Vector2 = Iso.to_screen(Vector2(bx, g.y + 0.28)) + Vector2(0, -30.0)
				ci.draw_colored_polygon(PackedVector2Array([
					top + Vector2(-7, -3), top + Vector2(2, -7),
					top + Vector2(9, -3), top + Vector2(0, 1)]), Color("#4ADE80"))
				ci.draw_line(top + Vector2(-4, -3), top + Vector2(5, -6),
					Color("#22A45A"), 1.4))
	_add_prop(Vector2(10.3, 4.3), _planter_painter(Vector2(10.3, 4.3)))

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
	_add_prop(Vector2(14.3, 8.4), _planter_painter(Vector2(14.3, 8.4)))

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
		ci.draw_circle(mid + Vector2(-4, -18), 2.6, UI.BRASS)
		ci.draw_circle(mid + Vector2(4, -16), 2.6, UI.BRASS)
		# Daylight spilling across the threshold.
		Iso.floor_patch(ci, d0 - Vector2(0.0, 0.85), Vector2(leaf * 2.0, 0.85),
			Color(1.0, 0.95, 0.75, 0.14)))
	_add_prop(Vector2(4.6, 15.4), func(ci: CanvasItem) -> void:
		var g := Vector2(3.6, 15.1)
		Iso.shadow(ci, g + Vector2(0.06, 0.10), Vector2(2.1, 0.7), 0.20)
		Iso.box(ci, g, Vector2(2.0, 0.65), 20.0, UI.ROOM_TICKET.darkened(0.18))
		Iso.box(ci, g + Vector2(-0.05, -0.05), Vector2(2.1, 0.75), 23.0, UI.BRASS,
			Color(0, 0, 0, 0.22)))
	for pg in [Vector2(0.6, 14.6), Vector2(14.4, 14.6), Vector2(8.6, 16.6)]:
		_add_prop(pg, _planter_painter(pg))

## Potted plant: terracotta pot plus leaf blades. Cheap, and the single most
## effective thing for making a floor look furnished rather than empty.
func _planter_painter(g: Vector2) -> Callable:
	return func(ci: CanvasItem) -> void:
		var base: Vector2 = Iso.to_screen(g)
		Iso.shadow(ci, g - Vector2(0.28, 0.28), Vector2(0.56, 0.56), 0.20)
		Iso.box(ci, g - Vector2(0.24, 0.24), Vector2(0.48, 0.48), 13.0, Color("#B4653C"))
		var top: Vector2 = base + Vector2(0, -13.0)
		for i in 6:
			var a: float = -PI * 0.5 + lerpf(-1.0, 1.0, float(i) / 5.0)
			var tip: Vector2 = top + Vector2(cos(a), sin(a)) * 17.0
			ci.draw_line(top, tip, Color("#2F8F52"), 3.2)
			ci.draw_line(top, tip.lerp(top, 0.35), Color("#46B86A"), 2.0)

func _draw_skeleton(ci: CanvasItem, at: Vector2) -> void:
	var bone := Color("#F3EAD6")
	var edge := Color("#6E5C3C")
	var spine := PackedVector2Array()
	for i in 13:
		var t: float = float(i) / 12.0
		spine.append(at + Vector2(lerpf(-52.0, 52.0, t), -26.0 - sin(t * PI) * 20.0))
	ci.draw_polyline(spine, edge, 8.0)
	ci.draw_polyline(spine, bone, 4.6)
	for p in spine:
		ci.draw_circle(p, 3.0, edge)
		ci.draw_circle(p, 1.8, bone)
	for i in range(3, 10, 2):
		ci.draw_arc(spine[i] + Vector2(0, 2), 13.0, 0.10 * PI, 0.90 * PI, 10, edge, 4.6)
		ci.draw_arc(spine[i] + Vector2(0, 2), 13.0, 0.10 * PI, 0.90 * PI, 10, bone, 2.4)
	var tail := PackedVector2Array([spine[0], spine[0] + Vector2(-16, 4),
		spine[0] + Vector2(-28, -4)])
	ci.draw_polyline(tail, edge, 6.0)
	ci.draw_polyline(tail, bone, 3.0)
	var neck := PackedVector2Array([spine[12], spine[12] + Vector2(12, -12),
		spine[12] + Vector2(20, -26)])
	ci.draw_polyline(neck, edge, 7.0)
	ci.draw_polyline(neck, bone, 3.8)
	var skull: Vector2 = spine[12] + Vector2(24, -30)
	var head := PackedVector2Array([
		skull + Vector2(-8, -6), skull + Vector2(6, -7), skull + Vector2(16, -1),
		skull + Vector2(17, 3), skull + Vector2(4, 5), skull + Vector2(-7, 3)])
	ci.draw_colored_polygon(head, bone)
	var ring := head.duplicate()
	ring.append(head[0])
	ci.draw_polyline(ring, edge, 2.4)
	ci.draw_circle(skull + Vector2(2, -2), 2.2, edge)
	for lx in [-34.0, -12.0, 16.0, 34.0]:
		var top: Vector2 = at + Vector2(lx, -26.0 - sin((lx + 52.0) / 104.0 * PI) * 20.0 + 4.0)
		ci.draw_line(top, at + Vector2(lx - 3, 0), edge, 6.4)
		ci.draw_line(top, at + Vector2(lx - 3, 0), bone, 3.4)

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
	ci.draw_circle(at + Vector2(-5, -34), 2.6, UI.PANEL)
	ci.draw_circle(at + Vector2(5, -34), 2.6, UI.PANEL)
	ci.draw_line(at + Vector2(-10, -20), at + Vector2(10, -20), Color("#3E7E8C"), 3.4)
	ci.draw_line(at + Vector2(-8, -12), at + Vector2(8, -12), Color("#357280"), 2.6)
	var ring := lid.duplicate()
	ring.append(lid[0])
	ci.draw_polyline(ring, Color("#8A6524"), 2.2)

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
		# Front-left of each room, not dead centre: the middle of a room is where
		# the exhibits and the cast are, and a plaque there covers them.
		var at: Vector2 = Iso.to_screen(
			r.position + Vector2(r.size.x * 0.16, r.size.y * 0.84)) + Vector2(0, -8)
		_draw_plaque(at, str(spec[2]), spec[1])

## Room name on a floating plaque at the room's centre, on its own layer: an
## earlier pass drew labels onto the floor, where the cast walked through them.
func _draw_plaque(center: Vector2, title: String, accent: Color) -> void:
	var w: float = float(_font.get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x) + 20.0
	var plate := Rect2(center.x - w * 0.5, center.y - 11.0, w, 22.0)
	_labels_layer.draw_rect(plate, accent.darkened(0.58))
	_labels_layer.draw_rect(plate, accent.lightened(0.25), false, 1.5)
	_labels_layer.draw_string(_font, Vector2(plate.position.x + 10.0, plate.position.y + 16.0),
		title, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, UI.FLOOR_CREAM)
