extends Control
## VenueFloor — living museum diorama (720x760 logical canvas, uniformly scaled).
## Original museum-specific layout, all procedural: Grand Gallery exhibits
## (dino skeleton / painting / sarcophagus), Archive vault with growing pile,
## Promotions corner, ticket hall with counters + velvet-rope queue lanes,
## red-carpet entrance. Visual approximation of Economy.venue_rates:
## visitors door -> queue -> served -> browse gallery -> exit; porters cart
## ticket-stub earnings from the busiest window to the vault.
## Emits dept_selected when a room tap zone is hit.

signal dept_selected(dept_id: String)

const UI := preload("res://scripts/ui/ui_kit.gd")
const Character := preload("res://scenes/venue/floor/character.gd")

const FLOOR := Vector2(720, 760)
const R_GALLERY := Rect2(24, 48, 420, 312)
const R_VAULT := Rect2(476, 48, 220, 252)
const R_PROMO := Rect2(476, 320, 220, 152)
const R_TICKET := Rect2(24, 496, 672, 216)
const R_CARPET := Rect2(24, 716, 640, 36)
const TAP_ZONES := {  # checked in order (first hit wins)
	"archive": R_VAULT, "promotions": R_PROMO, "gallery": R_GALLERY, "ticket": R_TICKET,
}
const DOOR_POS := Vector2(52, 734)
const COUNTER_Y := 542.0
const WINDOW_X: Array[float] = [90.0, 220.0, 350.0, 480.0, 610.0]
const SLOT_Y: Array[float] = [600.0, 634.0, 668.0, 702.0]
const MAX_WINDOWS := 5
const SLOTS_PER_WINDOW := 4
const MAX_ALIVE := 28
const MAX_CROWD := 6
const MAX_STACK_VIS := 10      # ticket-stub bundles drawn per window
const PORTER_HOME := Vector2(520, 312)
const VAULT_DROP := Vector2(572, 258)
const PILE_POS := Vector2(614, 284)
const MARKETER_POS := Vector2(122, 700)
const BROWSE_SPOTS := {
	"dino": [Vector2(120, 252), Vector2(172, 258), Vector2(94, 228)],
	"painting": [Vector2(300, 186), Vector2(348, 192)],
	"sarcophagus": [Vector2(316, 336), Vector2(366, 336)],
}
const EXHIBIT_KEYS: Array[String] = ["dino", "painting", "sarcophagus"]

var time_scale: float = 1.0    # test hook: accelerate the visual sim

var _canvas: Node2D
var _statics: Node2D           # rooms, counters, ropes, exhibits (redrawn on cast change)
var _stacks_layer: Node2D      # window ticket-stub stacks
var _pile_layer: Node2D        # vault pile
var _font: Font

var _arrival: float = 0.28
var _serve: float = 0.34
var _transport: float = 0.25
var _choke: String = ""
var _value_text: String = "2"

var _visitors: Array = []
var _porters: Array = []
var _queues: Array = []        # per window: ordered visitor refs (index = slot)
var _crowd: Array = []
var _stacks: Array[int] = []
var _serve_t: Array[float] = []
var _windows_active: int = 1
var _staff_nodes: Array = []   # teller Characters behind counters
var _docent_nodes: Array = []
var _promo_nodes: Array = []
var _marketer: Character
var _spawn_t: float = 0.0
var _porter_trips: int = 0
var _pile_height: float = 12.0
var _pile_flash: float = 0.0
var _stacks_dirty: bool = true
var _cast_key: String = ""

class Visitor:
	var node: Character
	var state: String = "to_queue"   # to_queue | queue | crowd | browse | exit
	var window: int = -1
	var target: Vector2 = Vector2.ZERO
	var spots: Array = []
	var wait: float = 0.0
	var speed: float = 78.0

class Porter:
	var node: Character
	var state: String = "idle"       # idle | to_window | to_vault
	var target: Vector2 = PORTER_HOME
	var window: int = -1
	var carried: int = 0

func _ready() -> void:
	name = "VenueFloor"
	clip_contents = true
	custom_minimum_size = Vector2(360, 380)
	_font = ThemeDB.fallback_font

	_canvas = Node2D.new()
	add_child(_canvas)
	_statics = Node2D.new()
	_statics.name = "Statics"
	_canvas.add_child(_statics)
	_stacks_layer = Node2D.new()
	_stacks_layer.name = "Stacks"
	_canvas.add_child(_stacks_layer)
	_pile_layer = Node2D.new()
	_pile_layer.name = "VaultPile"
	_canvas.add_child(_pile_layer)

	_stacks_layer.draw.connect(_draw_stacks)
	_pile_layer.draw.connect(_draw_pile)
	_statics.draw.connect(_draw_statics)

	for i in MAX_WINDOWS:
		_queues.append([])
		_stacks.append(0)
		_serve_t.append(0.0)

	_marketer = Character.new()
	_marketer.set_uniform(UI.ROOM_PROMO)
	_marketer.holding_sign = true
	_marketer.position = MARKETER_POS
	_marketer.facing = 1
	_marketer.visible = false
	_canvas.add_child(_marketer)

	resized.connect(_fit_canvas)
	_fit_canvas()
	_refresh_cast()
	if EventBus.has_signal("department_upgraded"):
		EventBus.department_upgraded.connect(func(_v: String, _d: String, _t: String, _l: int) -> void: _refresh_cast())

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
		_statics.queue_redraw()
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
	for dept_id in TAP_ZONES.keys():
		if (TAP_ZONES[dept_id] as Rect2).has_point(canvas_pos):
			return dept_id
	return ""

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

	# Ticket windows + tellers.
	_windows_active = clampi(_staff_level("ticket"), 1, MAX_WINDOWS)
	while _staff_nodes.size() < _windows_active:
		var i: int = _staff_nodes.size()
		var c: Character = Character.new()
		c.set_uniform(UI.ROOM_TICKET)
		c.position = Vector2(WINDOW_X[i], COUNTER_Y - 5.0)
		c.facing = 1
		_canvas.add_child(c)
		_staff_nodes.append(c)
	while _staff_nodes.size() > _windows_active:
		_staff_nodes.pop_back().queue_free()

	# Gallery docents near the exhibits.
	var docents: int = clampi(_staff_level("gallery"), 0, 2)
	while _docent_nodes.size() < docents:
		var c: Character = Character.new()
		c.set_uniform(UI.ROOM_GALLERY.darkened(0.2))
		c.position = [Vector2(232, 180), Vector2(398, 214)][_docent_nodes.size()]
		_canvas.add_child(c)
		_docent_nodes.append(c)
	while _docent_nodes.size() > docents:
		_docent_nodes.pop_back().queue_free()

	# Promotions clerks behind the desk.
	var clerks: int = clampi(_staff_level("promotions"), 1, 2)
	while _promo_nodes.size() < clerks:
		var c: Character = Character.new()
		c.set_uniform(UI.ROOM_PROMO)
		c.position = [Vector2(614, 392), Vector2(660, 396)][_promo_nodes.size()]
		_canvas.add_child(c)
		_promo_nodes.append(c)
	while _promo_nodes.size() > clerks:
		_promo_nodes.pop_back().queue_free()

	# Archive porters.
	var porters: int = clampi(_staff_level("archive"), 1, 3)
	while _porters.size() < porters:
		var p := Porter.new()
		var c: Character = Character.new()
		c.set_uniform(UI.ROOM_VAULT)
		c.with_cart = true
		c.position = PORTER_HOME + Vector2(_porters.size() * 26.0, 0)
		_canvas.add_child(c)
		p.node = c
		p.target = c.position
		_porters.append(p)
	while _porters.size() > porters:
		var p: Porter = _porters.pop_back()
		p.node.queue_free()

	_statics.queue_redraw()

func _update_pile_height() -> void:
	if not GameState.ready_flag:
		return
	var earned: BigNumber = BigNumber.from_save(
		GameState.venue_state(GameState.current_venue).get("earned_total", {}))
	var approx: float = 0.0
	if not earned.is_zero():
		approx = float(earned.e) + log(maxf(earned.m, 0.01)) / log(10.0)
	_pile_height = clampf(12.0 + approx * 9.0, 12.0, 112.0)
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
	# Pick the shortest non-full lane; otherwise join the waiting crowd.
	var best: int = -1
	for w in _windows_active:
		if _queues[w].size() < SLOTS_PER_WINDOW and (best == -1 or _queues[w].size() < _queues[best].size()):
			best = w
	if best == -1 and _crowd.size() >= MAX_CROWD:
		return  # turn away — floor is packed
	var v := Visitor.new()
	var c: Character = Character.new()
	c.randomize_look(randi())
	c.position = DOOR_POS
	_canvas.add_child(c)
	v.node = c
	v.speed = randf_range(66.0, 92.0)
	_visitors.append(v)
	if best == -1:
		v.state = "crowd"
		_crowd.append(v)
		v.target = _crowd_slot(_crowd.size() - 1)
	else:
		_assign_to_window(v, best)

func _crowd_slot(i: int) -> Vector2:
	return Vector2(548.0 + float(i % 3) * 40.0, 664.0 + float(i / 3) * 30.0)

func _assign_to_window(v: Visitor, w: int) -> void:
	if v.state == "crowd":
		_crowd.erase(v)
	v.state = "to_queue"
	v.window = w
	_queues[w].append(v)
	v.target = _slot_pos(w, _queues[w].size() - 1)

func _slot_pos(w: int, idx: int) -> Vector2:
	return Vector2(WINDOW_X[w], SLOT_Y[clampi(idx, 0, SLOTS_PER_WINDOW - 1)])

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
	# Teller stamp pulse + floating "+$N".
	if w < _staff_nodes.size():
		var teller: Node2D = _staff_nodes[w]
		var tw := teller.create_tween()
		tw.tween_property(teller, "scale", Vector2(1.18, 1.18), 0.09)
		tw.tween_property(teller, "scale", Vector2.ONE, 0.16)
	_spawn_float("+$" + _value_text, Vector2(WINDOW_X[w], COUNTER_Y - 34.0))
	# Remaining queue shuffles forward.
	for i in _queues[w].size():
		(_queues[w][i] as Visitor).target = _slot_pos(w, i)
	# Off to the gallery: 1-2 exhibits, then the exit.
	var keys: Array = EXHIBIT_KEYS.duplicate()
	keys.shuffle()
	var spots: Array = []
	for k in keys.slice(0, randi_range(1, 2)):  # slice end is exclusive: 1-2 exhibits
		var opts: Array = BROWSE_SPOTS[k]
		spots.append(opts[randi() % opts.size()])
	v.spots = spots
	v.state = "browse"
	v.window = -1
	v.target = v.spots.pop_front()
	# Freed slots anywhere pull the waiting crowd into lanes.
	for w2 in _windows_active:
		if _crowd.is_empty():
			break
		if _queues[w2].size() < SLOTS_PER_WINDOW:
			_assign_to_window(_crowd[0], w2)

func _update_visitors(dt: float) -> void:
	var done: Array = []
	for v in _visitors:
		var c: Node2D = v.node
		var arrived: bool = _move(v, c, dt)
		match v.state:
			"to_queue":
				if arrived:
					v.state = "queue"
			"queue", "crowd":
				pass  # targets maintained by queue/crowd management
			"browse":
				if arrived:
					if v.wait <= 0.0:
						v.wait = randf_range(1.2, 2.6)
					v.wait -= dt
					if v.wait <= 0.0:
						if v.spots.is_empty():
							v.state = "exit"
							v.target = DOOR_POS
						else:
							v.target = v.spots.pop_front()
			"exit":
				if arrived:
					done.append(v)
	for v in done:
		_visitors.erase(v)
		v.node.queue_free()

func _move(v: Visitor, c: Character, dt: float) -> bool:
	var d: Vector2 = v.target - c.position
	var dist: float = d.length()
	if dist < 3.0:
		c.walking = false
		return true
	var step: float = minf(v.speed * dt, dist)
	c.position += d / dist * step
	c.facing = 1 if d.x >= 0.0 else -1
	c.walking = true
	return false

func _porter_speed() -> float:
	return clampf(70.0 + _transport * 18.0, 70.0, 170.0)

func _update_porters(dt: float) -> void:
	for p in _porters:
		var c: Node2D = p.node
		match p.state:
			"idle":
				var best: int = -1
				for w in _windows_active:
					if _stacks[w] >= 2 and (best == -1 or _stacks[w] > _stacks[best]):
						best = w
				if best != -1:
					p.window = best
					p.state = "to_window"
					p.target = Vector2(WINDOW_X[best] + 52.0, COUNTER_Y + 40.0)
			"to_window":
				if _porter_move(p, c, dt):
					var take: int = mini(_stacks[p.window], 6)
					_stacks[p.window] -= take
					_stacks_dirty = true
					p.carried = take
					c.carry_stack = clampi(take, 1, 4)
					c.queue_redraw()
					p.state = "to_vault"
					p.target = VAULT_DROP
			"to_vault":
				if _porter_move(p, c, dt):
					p.carried = 0
					c.carry_stack = 0
					c.queue_redraw()
					_porter_trips += 1
					_pile_flash = 1.0
					p.state = "idle"
					p.target = PORTER_HOME + Vector2(_porters.find(p) * 26.0, 0)

func _porter_move(p: Porter, c: Character, dt: float) -> bool:
	var d: Vector2 = p.target - c.position
	var dist: float = d.length()
	if dist < 4.0:
		c.walking = false
		return true
	var step: float = minf(_porter_speed() * dt, dist)
	c.position += d / dist * step
	c.facing = 1 if d.x >= 0.0 else -1
	c.walking = true
	return false

func _spawn_float(text: String, pos: Vector2) -> void:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 19)
	l.add_theme_color_override("font_color", UI.UPGRADE_GREEN.darkened(0.1))
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.position = pos + Vector2(-18, 0)
	_canvas.add_child(l)
	var tw := l.create_tween()
	tw.set_parallel(true)
	tw.tween_property(l, "position:y", pos.y - 40.0, 1.0)
	tw.tween_property(l, "modulate:a", 0.0, 1.0)
	tw.chain().tween_callback(l.queue_free)

# --- Static diorama drawing ----------------------------------------------------

func _draw_statics() -> void:
	# Base floor + outer wall.
	_statics.draw_rect(Rect2(Vector2.ZERO, FLOOR), UI.FLOOR_CREAM)
	for y in range(0, int(FLOOR.y), 38):  # floorboard seams
		_statics.draw_line(Vector2(0, y), Vector2(FLOOR.x, y), UI.FLOOR_CREAM.darkened(0.05), 1.0)
	_statics.draw_rect(Rect2(Vector2.ZERO, FLOOR), UI.WALL_BROWN, false, 8.0)

	_draw_room(R_GALLERY, UI.ROOM_GALLERY, "GRAND GALLERY", "gallery")
	_draw_room(R_VAULT, UI.ROOM_VAULT, "THE ARCHIVE", "archive")
	_draw_room(R_PROMO, UI.ROOM_PROMO, "PROMOTIONS", "promotions")
	_draw_room(R_TICKET, UI.ROOM_TICKET, "TICKET HALL", "ticket")

	# Red carpet with gold trim along the entrance walk.
	_statics.draw_rect(R_CARPET, UI.CARPET_RED)
	_statics.draw_rect(R_CARPET.grow_side(SIDE_TOP, -4).grow_side(SIDE_BOTTOM, -4),
		UI.CARPET_RED.lightened(0.12))
	_statics.draw_line(R_CARPET.position, R_CARPET.position + Vector2(R_CARPET.size.x, 0), UI.BRASS, 2.0)
	var cb: Vector2 = R_CARPET.position + Vector2(0, R_CARPET.size.y)
	_statics.draw_line(cb - Vector2(0, 2), Vector2(cb.x + R_CARPET.size.x, cb.y - 2), UI.BRASS, 2.0)

	# Entrance double door at the carpet's left end.
	var door := Rect2(20, 660, 64, 56)
	_statics.draw_rect(door, UI.WALL_BROWN)
	_statics.draw_rect(door.grow(-5), Color("#8A6543"))
	_statics.draw_line(door.get_center() + Vector2(0, -22), door.get_center() + Vector2(0, 22),
		UI.WALL_BROWN, 3.0)
	_statics.draw_circle(door.get_center() + Vector2(-7, 0), 2.6, UI.BRASS)
	_statics.draw_circle(door.get_center() + Vector2(7, 0), 2.6, UI.BRASS)

	_draw_gallery_exhibits()
	_draw_vault_interior()
	_draw_promo_interior()
	_draw_ticket_interior()

func _draw_room(r: Rect2, accent: Color, title: String, dept_id: String) -> void:
	_statics.draw_rect(r, accent.lerp(UI.FLOOR_CREAM, 0.72))
	_statics.draw_rect(r, accent, false, 5.0)
	if _choke == dept_id:  # bottleneck room gets a warning inner frame
		_statics.draw_rect(r.grow(-8), UI.DANGER, false, 3.0)
	_statics.draw_string(_font, r.position + Vector2(12, 24), title,
		HORIZONTAL_ALIGNMENT_LEFT, -1, 16, accent.darkened(0.45))

func _draw_gallery_exhibits() -> void:
	var bone := Color("#EFE6D0")
	var bone_line := Color("#D8CCAF")
	# Dino skeleton on a pedestal (original rig: arched spine, rib arcs, horned skull).
	var ped := Rect2(60, 196, 150, 26)
	_statics.draw_rect(ped, Color("#B9A88A"))
	_statics.draw_rect(ped, UI.WALL_BROWN, false, 2.0)
	# Spine: shallow arch of vertebra dots from tail (left) to neck (right).
	var spine_pts := PackedVector2Array()
	for i in 13:
		var t: float = float(i) / 12.0
		spine_pts.append(Vector2(lerpf(84.0, 186.0, t), 168.0 - sin(t * PI) * 22.0))
	_statics.draw_polyline(spine_pts, bone_line, 4.0)
	for p in spine_pts:
		_statics.draw_circle(p, 3.2, bone)
	for i in range(3, 10, 2):  # rib cages hanging below the mid spine
		var top: Vector2 = spine_pts[i]
		_statics.draw_arc(top + Vector2(0, 2), 15.0, 0.15 * PI, 0.85 * PI, 8, bone, 3.0)
	_statics.draw_line(spine_pts[0], spine_pts[0] + Vector2(-26, -10), bone_line, 3.5)  # tail
	_statics.draw_line(spine_pts[12], spine_pts[12] + Vector2(18, -16), bone_line, 4.0)  # neck
	var skull := spine_pts[12] + Vector2(30, -20)
	_statics.draw_circle(skull, 10.5, bone)  # skull
	_statics.draw_circle(skull + Vector2(4, -2), 2.2, UI.INK)  # eye socket
	_statics.draw_line(skull + Vector2(-4, -8), skull + Vector2(-10, -18), bone_line, 3.0)  # horns
	_statics.draw_line(skull + Vector2(4, -10), skull + Vector2(8, -21), bone_line, 3.0)
	for lx in [104.0, 168.0]:  # legs straddling the pedestal
		_statics.draw_line(Vector2(lx, 178), Vector2(lx - 5, 208), bone, 4.5)
		_statics.draw_line(Vector2(lx - 5, 208), Vector2(lx + 3, 208), bone, 3.5)
	# Framed painting (landscape) on the back wall.
	var frame := Rect2(272, 66, 116, 84)
	_statics.draw_rect(frame, UI.BRASS)
	_statics.draw_rect(frame.grow(-7), Color("#A9C8E8"))
	_statics.draw_circle(frame.position + Vector2(34, 26), 10, Color("#F2D57E"))  # sun
	_statics.draw_colored_polygon(PackedVector2Array([  # hills
		frame.position + Vector2(7, 77), frame.position + Vector2(45, 44),
		frame.position + Vector2(80, 77)]), Color("#7A9B76"))
	_statics.draw_colored_polygon(PackedVector2Array([
		frame.position + Vector2(55, 77), frame.position + Vector2(88, 50),
		frame.position + Vector2(109, 77)]), Color("#5F8360"))
	# Sarcophagus (rounded lid, striped mask band) on a plinth.
	var plinth := Rect2(296, 316, 92, 20)
	_statics.draw_rect(plinth, Color("#B9A88A"))
	_statics.draw_rect(plinth, UI.WALL_BROWN, false, 2.0)
	var coffin := Rect2(306, 250, 72, 66)
	_statics.draw_rect(coffin, Color("#C9963B"))
	_statics.draw_circle(coffin.position + Vector2(36, 0), 36, Color("#C9963B"))
	_statics.draw_rect(Rect2(coffin.position + Vector2(8, 14), Vector2(56, 16)), Color("#3E7E8C"))
	_statics.draw_circle(coffin.position + Vector2(28, 22), 4, UI.PANEL)  # mask eyes
	_statics.draw_circle(coffin.position + Vector2(44, 22), 4, UI.PANEL)
	_statics.draw_line(coffin.position + Vector2(10, 44), coffin.position + Vector2(62, 44),
		Color("#3E7E8C"), 4.0)
	_statics.draw_rect(coffin, UI.WALL_BROWN.darkened(0.1), false, 2.0)

func _draw_vault_interior() -> void:
	# Round vault door on the back wall: ring, spokes, handle.
	var c := Vector2(616, 142)
	_statics.draw_circle(c, 52, Color("#4A627E"))
	_statics.draw_circle(c, 44, Color("#87A3C4"))
	for i in 6:
		var a: float = TAU * float(i) / 6.0
		_statics.draw_line(c + Vector2(cos(a), sin(a)) * 14.0,
			c + Vector2(cos(a), sin(a)) * 40.0, Color("#4A627E"), 4.0)
	_statics.draw_circle(c, 14, Color("#4A627E"))
	_statics.draw_circle(c, 8, UI.BRASS)
	_statics.draw_string(_font, R_VAULT.position + Vector2(12, R_VAULT.size.y - 12),
		"vault", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, UI.ROOM_VAULT.darkened(0.3))

func _draw_promo_interior() -> void:
	# Campaign desk + exhibit poster board.
	var desk := Rect2(548, 404, 118, 26)
	_statics.draw_rect(desk, Color("#8A6543"))
	_statics.draw_rect(desk, UI.WALL_BROWN, false, 2.0)
	var board := Rect2(496, 336, 92, 62)
	_statics.draw_rect(board, UI.PANEL)
	_statics.draw_rect(board, UI.WALL_BROWN, false, 3.0)
	_statics.draw_circle(board.position + Vector2(24, 20), 9, UI.ROOM_PROMO)
	_statics.draw_line(board.position + Vector2(12, 42), board.position + Vector2(80, 42),
		UI.ROOM_PROMO.darkened(0.2), 3.0)
	_statics.draw_line(board.position + Vector2(12, 52), board.position + Vector2(62, 52),
		UI.ROOM_PROMO.darkened(0.2), 3.0)

func _draw_ticket_interior() -> void:
	for w in _windows_active:
		var wx: float = WINDOW_X[w]
		# Counter block with a brass service ledge.
		var counter := Rect2(wx - 46, COUNTER_Y, 92, 26)
		_statics.draw_rect(counter, UI.ROOM_TICKET.darkened(0.12))
		_statics.draw_rect(counter, UI.WALL_BROWN, false, 2.0)
		_statics.draw_rect(Rect2(wx - 46, COUNTER_Y - 4, 92, 6), UI.BRASS)
		# Queue lane: brass posts + sagging velvet rope on both sides.
		for side in [-26.0, 26.0]:
			var px: float = wx + side
			var prev := Vector2.ZERO
			for j in SLOTS_PER_WINDOW:
				var py: float = SLOT_Y[j] + 2.0
				_statics.draw_line(Vector2(px, py), Vector2(px, py - 12), UI.WALL_BROWN, 2.5)
				_statics.draw_circle(Vector2(px, py - 14), 3.6, UI.BRASS)
				if j > 0:
					var rope := PackedVector2Array()
					for k in 9:
						var t: float = float(k) / 8.0
						var p: Vector2 = prev.lerp(Vector2(px, py - 13), t)
						p.y += sin(t * PI) * 7.0
						rope.append(p)
					_statics.draw_polyline(rope, UI.ROPE_RED, 2.5)
				prev = Vector2(px, py - 13)
	# Window number plaques.
	for w in _windows_active:
		_statics.draw_string(_font, Vector2(WINDOW_X[w] - 6, COUNTER_Y + 44), str(w + 1),
			HORIZONTAL_ALIGNMENT_LEFT, -1, 13, UI.ROOM_TICKET.darkened(0.35))

# --- Dynamic layers -------------------------------------------------------------

func _draw_stacks() -> void:
	# Ticket-stub bundles piling up beside each counter; archive choke lets them
	# overflow into artifact crates on the floor.
	var cap: int = MAX_STACK_VIS * 2 if _choke == "archive" else MAX_STACK_VIS
	for w in _windows_active:
		var n: int = mini(_stacks[w], cap)
		for i in n:
			var r := Rect2(WINDOW_X[w] + 50.0, COUNTER_Y + 18.0 - float(i) * 5.0, 24, 4)
			_stacks_layer.draw_rect(r, UI.PANEL if i % 2 == 0 else UI.FLOOR_CREAM)
			_stacks_layer.draw_rect(r, UI.ROOM_TICKET.darkened(0.3), false, 1.0)
		if _choke == "archive" and _stacks[w] > cap:
			var crate := Rect2(WINDOW_X[w] + 48.0, COUNTER_Y + 26.0, 28, 20)
			_stacks_layer.draw_rect(crate, Color("#C89B5E"))
			_stacks_layer.draw_rect(crate, UI.WALL_BROWN, false, 2.0)

func _draw_pile() -> void:
	# Vault pile: artifact crates at the base + coin mound that grows (log scale)
	# with the venue's total earnings. Flashes bright on a porter deposit.
	var gold := UI.ROOM_GALLERY.lightened(0.1 + 0.35 * _pile_flash)
	for i in 2:  # base artifact crates (ours — not cash bags)
		var crate := Rect2(PILE_POS + Vector2(-44.0 - float(i) * 30.0, -16.0), Vector2(26, 16))
		_pile_layer.draw_rect(crate, Color("#C89B5E"))
		_pile_layer.draw_rect(crate, UI.WALL_BROWN, false, 2.0)
	var rows: int = int(_pile_height / 7.0)
	for r_i in rows:
		var w: float = 84.0 * (1.0 - float(r_i) / float(rows + 2))
		var y: float = PILE_POS.y - float(r_i) * 6.4
		var coins: int = maxi(int(w / 12.0), 1)
		for c_i in coins:
			var x: float = PILE_POS.x - w * 0.5 + float(c_i) * 12.0
			_pile_layer.draw_circle(Vector2(x, y), 5.2, gold.darkened(0.08 * float(r_i % 2)))
