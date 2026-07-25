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
var _labels_layer: Node2D      # room name plaques (always above the cast)
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
	# Y-sorting is what makes the cast occupy the room instead of floating over
	# it: whoever stands nearer the viewer draws in front, recomputed per frame.
	_canvas.y_sort_enabled = true
	add_child(_canvas)
	# Statics / stacks / pile all sit at the canvas origin, so Y-sorting alone
	# puts them behind every actor. Do NOT give them a negative z_index to force
	# it: z_index is global within the canvas layer, not scoped to the parent, so
	# a negative value drops them behind main.gd's full-screen background and the
	# whole diorama silently disappears.
	_statics = Node2D.new()
	_statics.name = "Statics"
	_canvas.add_child(_statics)
	_stacks_layer = Node2D.new()
	_stacks_layer.name = "Stacks"
	_canvas.add_child(_stacks_layer)
	_pile_layer = Node2D.new()
	_pile_layer.name = "VaultPile"
	_canvas.add_child(_pile_layer)
	# Room plaques ride above everyone. They name the tap target, so a visitor
	# wandering across the wall band must not be able to hide one.
	_labels_layer = Node2D.new()
	_labels_layer.name = "Labels"
	# Just above the cast (z 0), NOT a large value: z_index is global inside the
	# canvas layer, so a big number here paints the plaque over the dept sheet.
	_labels_layer.z_index = 1
	_canvas.add_child(_labels_layer)

	_stacks_layer.draw.connect(_draw_stacks)
	_pile_layer.draw.connect(_draw_pile)
	_statics.draw.connect(_draw_statics)
	_labels_layer.draw.connect(_draw_labels)

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
	_apply_depth(_marketer)

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
		_apply_depth(c)
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
		_apply_depth(c)
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
		_apply_depth(c)
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
		_apply_depth(c)
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

## Actors shrink toward the back of the hall. Combined with Y-sorting this is
## what reads as depth — a flat plan with same-size sprites is what made the
## v1 floor look like a diagram.
const DEPTH_SCALE_BACK := 0.80
const DEPTH_SCALE_FRONT := 1.10

func _apply_depth(c: Node2D) -> void:
	var t: float = clampf(c.position.y / FLOOR.y, 0.0, 1.0)
	var s: float = lerpf(DEPTH_SCALE_BACK, DEPTH_SCALE_FRONT, t)
	# Magnitude only — Character._process re-applies the facing sign to scale.x.
	c.scale = Vector2(s, s)

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
	_apply_depth(c)
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
					_spawn_coin_burst(VAULT_DROP + Vector2(0, -8), 7)
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
	_apply_depth(c)
	return false

## Cash pops off the counter on an arc, overshoots, then fades as it drifts up.
## The straight vertical fade it replaced was the single flattest thing on the
## floor — a sale is the core beat of the loop and should feel like one.
func _spawn_float(text: String, pos: Vector2) -> void:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", UI.font())
	l.add_theme_font_size_override("font_size", 21)
	l.add_theme_color_override("font_color", UI.UPGRADE_GREEN.darkened(0.15))
	# Dark rim keeps the number legible over any room colour underneath.
	l.add_theme_color_override("font_outline_color", Color(1, 1, 1, 0.85))
	l.add_theme_constant_override("outline_size", 4)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.z_index = 2
	l.position = pos + Vector2(-18, 0)
	l.pivot_offset = Vector2(18, 10)
	l.scale = Vector2(0.6, 0.6)
	_canvas.add_child(l)
	var drift: float = randf_range(-14.0, 14.0)
	var tw := l.create_tween()
	tw.set_parallel(true)
	tw.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(l, "scale", Vector2.ONE, 0.22)
	tw.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(l, "position:y", pos.y - 52.0, 1.1)
	tw.tween_property(l, "position:x", l.position.x + drift, 1.1)
	tw.chain().tween_property(l, "modulate:a", 0.0, 0.34)
	tw.chain().tween_callback(l.queue_free)

## Coin burst when a porter banks a load into the vault.
func _spawn_coin_burst(pos: Vector2, count: int = 6) -> void:
	for i in count:
		var coin := Node2D.new()
		coin.position = pos
		coin.z_index = 2
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

# --- Static diorama drawing ----------------------------------------------------
## The floor is a dollhouse cutaway, not a flat plan: every room is a lit box
## with a floor slab, a back wall, side returns and a baseboard, and everything
## standing on it casts a contact shadow. A literal 45-degree isometric grid was
## the other option and was rejected — in a 720px-wide portrait viewport, diamond
## rooms waste most of the horizontal space, and rotating the layout would have
## meant re-deriving every visitor waypoint and tap zone. Per-room volume plus
## depth-scaled, Y-sorted actors buys the same read of depth at none of that risk.
##
## Light is a single warm key from the upper left; every gradient in here points
## the same way, which is most of what separates this from the flat v1 pass.

## Antialiased canvas strokes generate separate AA geometry and break batching.
## With a full diorama plus 28 actors that cost ~750 draw calls a frame.
const AA_STROKES := false
const WALL_H := 30.0          # back-wall extrusion above each room's top edge
const SIDE_W := 9.0           # side-wall return thickness

func _draw_statics() -> void:
	_draw_floor_base()
	_draw_room_box(R_GALLERY, UI.ROOM_GALLERY, "GRAND GALLERY", "gallery")
	_draw_room_box(R_VAULT, UI.ROOM_VAULT, "THE ARCHIVE", "archive")
	_draw_room_box(R_PROMO, UI.ROOM_PROMO, "PROMOTIONS", "promotions")
	_draw_room_box(R_TICKET, UI.ROOM_TICKET, "TICKET HALL", "ticket")
	_draw_entrance()
	_draw_gallery_exhibits()
	_draw_vault_interior()
	_draw_promo_interior()
	_draw_ticket_interior()
	_draw_vignette()

## Hall floor: warm gradient, parquet seams, and a soft pool of light up-left.
func _draw_floor_base() -> void:
	_vgrad(Rect2(Vector2.ZERO, FLOOR), UI.FLOOR_CREAM.lightened(0.06),
		UI.FLOOR_CREAM.darkened(0.10))
	var seam := UI.FLOOR_CREAM.darkened(0.06)
	for y in range(0, int(FLOOR.y), 40):
		_statics.draw_line(Vector2(0, y), Vector2(FLOOR.x, y), seam, 1.0)
	for x in range(0, int(FLOOR.x), 80):
		_statics.draw_line(Vector2(x, 0), Vector2(x, FLOOR.y), seam, 1.0)
	# Outer shell.
	_statics.draw_rect(Rect2(Vector2.ZERO, FLOOR), UI.WALL_BROWN, false, 8.0)

## One room as a lit box. Floor slab is inset under the walls so the baseboard
## reads as thickness rather than a drawn line.
func _draw_room_box(r: Rect2, accent: Color, _title: String, dept_id: String) -> void:
	var wall_top: float = r.position.y - WALL_H
	# 0.70 toward cream washed the accents back out to pastel; 0.42 keeps the
	# room hue clearly saturated while staying light enough for the outlined
	# cast to read against it.
	var floor_col: Color = accent.lerp(UI.FLOOR_CREAM, 0.42)

	# Back wall: darker at the top, catching light where it meets the floor.
	_vgrad(Rect2(r.position.x, wall_top, r.size.x, WALL_H),
		accent.darkened(0.34), accent.darkened(0.06))
	# Side returns, angled in, so the box has corners.
	_statics.draw_colored_polygon(PackedVector2Array([
		Vector2(r.position.x, wall_top), Vector2(r.position.x + SIDE_W, wall_top + 4.0),
		Vector2(r.position.x + SIDE_W, r.position.y + r.size.y),
		Vector2(r.position.x, r.position.y + r.size.y),
	]), accent.darkened(0.22))
	_statics.draw_colored_polygon(PackedVector2Array([
		Vector2(r.end.x, wall_top), Vector2(r.end.x - SIDE_W, wall_top + 4.0),
		Vector2(r.end.x - SIDE_W, r.end.y), Vector2(r.end.x, r.end.y),
	]), accent.darkened(0.14))

	# Floor slab, lighter toward the viewer.
	var slab := Rect2(r.position.x + SIDE_W, r.position.y, r.size.x - SIDE_W * 2.0, r.size.y)
	_vgrad(slab, floor_col.darkened(0.07), floor_col.lightened(0.05))
	# Ambient occlusion where wall meets floor.
	_vgrad(Rect2(slab.position.x, slab.position.y, slab.size.x, 14.0),
		Color(0.18, 0.12, 0.06, 0.20), Color(0.18, 0.12, 0.06, 0.0))
	# Baseboard.
	_statics.draw_line(Vector2(slab.position.x, r.position.y),
		Vector2(slab.end.x, r.position.y), accent.darkened(0.40), 2.5)
	# Room outline.
	_statics.draw_rect(Rect2(r.position.x, wall_top, r.size.x, r.size.y + WALL_H),
		accent.darkened(0.30), false, 3.0)

	if _choke == dept_id:
		# Bottleneck: pulse-free warning frame, readable at a glance.
		_statics.draw_rect(Rect2(r.position.x, wall_top, r.size.x, r.size.y + WALL_H).grow(-6),
			UI.DANGER, false, 3.0)


## Plaques for all four rooms, drawn on their own layer above the cast.
func _draw_labels() -> void:
	for spec in [[R_GALLERY, UI.ROOM_GALLERY, "GRAND GALLERY"],
			[R_VAULT, UI.ROOM_VAULT, "THE ARCHIVE"],
			[R_PROMO, UI.ROOM_PROMO, "PROMOTIONS"],
			[R_TICKET, UI.ROOM_TICKET, "TICKET HALL"]]:
		var r: Rect2 = spec[0]
		_draw_plaque(Vector2(r.position.x + 14.0, r.position.y - WALL_H + 5.0),
			str(spec[2]), spec[1])

## Room name on a wall plaque. On the wall, deliberately: the v1 pass drew labels
## on the floor, where the cast walked straight through them.
func _draw_plaque(pos: Vector2, title: String, accent: Color) -> void:
	var w: float = float(_font.get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1, 15).x) + 20.0
	var plate := Rect2(pos.x, pos.y, w, 21.0)
	_labels_layer.draw_rect(plate, accent.darkened(0.52))
	_labels_layer.draw_rect(plate, UI.BRASS.darkened(0.1), false, 1.5)
	_labels_layer.draw_string(_font, pos + Vector2(10.0, 15.0), title,
		HORIZONTAL_ALIGNMENT_LEFT, -1, 15, UI.FLOOR_CREAM)

## Red carpet + entrance doors.
func _draw_entrance() -> void:
	_soft_shadow(R_CARPET.get_center() + Vector2(0, 4), R_CARPET.size.x * 0.5, 12.0, 0.16)
	_vgrad(R_CARPET, UI.CARPET_RED.lightened(0.10), UI.CARPET_RED.darkened(0.16))
	_statics.draw_line(R_CARPET.position, Vector2(R_CARPET.end.x, R_CARPET.position.y),
		UI.BRASS, 2.0)
	_statics.draw_line(Vector2(R_CARPET.position.x, R_CARPET.end.y - 2.0),
		Vector2(R_CARPET.end.x, R_CARPET.end.y - 2.0), UI.BRASS, 2.0)

	var door := Rect2(20, 656, 64, 60)
	_soft_shadow(Vector2(door.get_center().x, door.end.y), 34.0, 7.0, 0.18)
	_statics.draw_rect(door.grow(4.0), UI.WALL_BROWN)
	_vgrad(door, Color("#9A7350"), Color("#7A5638"))
	for leaf_x in [door.position.x + 3.0, door.get_center().x + 1.0]:
		var leaf := Rect2(leaf_x, door.position.y + 4.0, door.size.x * 0.5 - 4.0, door.size.y - 8.0)
		_statics.draw_rect(leaf, Color(1, 1, 1, 0.10))
		_statics.draw_rect(leaf, UI.WALL_BROWN.darkened(0.2), false, 1.5)
	_statics.draw_circle(door.get_center() + Vector2(-6, 2), 2.8, UI.BRASS)
	_statics.draw_circle(door.get_center() + Vector2(8, 2), 2.8, UI.BRASS)
	# Transom fanlight above the doors.
	_statics.draw_colored_polygon(_arc_band(door.get_center() + Vector2(0, -26),
		26.0, PI, TAU, 7.0), UI.BRASS.darkened(0.15))

func _draw_gallery_exhibits() -> void:
	var bone := Color("#F3EAD6")
	var bone_dk := Color("#CFC0A2")

	# --- Sauropod skeleton on a plinth ---------------------------------------
	var ped := Rect2(60, 196, 156, 24)
	_soft_shadow(Vector2(ped.get_center().x, ped.end.y - 1.0), 82.0, 9.0, 0.20)
	_vgrad(ped, Color("#CBBA9A"), Color("#A08D6E"))
	_statics.draw_rect(ped, UI.WALL_BROWN, false, 2.0)

	# Every bone is stroked dark first, then filled lighter on top. Bone-on-gold
	# is a low-contrast pairing; without the dark pass the whole skeleton washed
	# out into the gallery floor and read as a scribble.
	var edge := Color("#6E5C3C")
	var spine := PackedVector2Array()
	for i in 15:
		var t: float = float(i) / 14.0
		spine.append(Vector2(lerpf(78.0, 188.0, t), 168.0 - sin(t * PI) * 30.0))
	_statics.draw_polyline(spine, edge, 9.0, AA_STROKES)
	_statics.draw_polyline(spine, bone, 5.4, AA_STROKES)
	# Vertebrae read as segmentation along the back.
	for p in spine:
		_statics.draw_circle(p, 3.4, edge)
		_statics.draw_circle(p, 2.1, bone)
	# Rib cage hanging off the mid-spine.
	for i in range(3, 11, 2):
		var anchor: Vector2 = spine[i] + Vector2(0, 3)
		_statics.draw_arc(anchor, 19.0, 0.10 * PI, 0.90 * PI, 12, edge, 5.4, AA_STROKES)
		_statics.draw_arc(anchor, 19.0, 0.10 * PI, 0.90 * PI, 12, bone_dk, 2.8, AA_STROKES)
	# Tail whipping down-left, neck sweeping up-right to the skull.
	var tail := PackedVector2Array([spine[0], spine[0] + Vector2(-14, 2), spine[0] + Vector2(-28, -6),
		spine[0] + Vector2(-38, -18)])
	_statics.draw_polyline(tail, edge, 7.0, AA_STROKES)
	_statics.draw_polyline(tail, bone, 3.6, AA_STROKES)
	var neck := PackedVector2Array([spine[14], spine[14] + Vector2(12, -16), spine[14] + Vector2(22, -34)])
	_statics.draw_polyline(neck, edge, 8.0, AA_STROKES)
	_statics.draw_polyline(neck, bone, 4.4, AA_STROKES)
	# Long-snouted skull: cranium + tapering jaw, so it isn't just a blob.
	var skull: Vector2 = spine[14] + Vector2(26, -40)
	var head := PackedVector2Array([
		skull + Vector2(-9, -7), skull + Vector2(7, -8), skull + Vector2(19, -1),
		skull + Vector2(20, 4), skull + Vector2(5, 6), skull + Vector2(-8, 4),
	])
	var head_ring := head.duplicate()
	head_ring.append(head[0])
	_statics.draw_colored_polygon(head, bone)
	_statics.draw_polyline(head_ring, edge, 3.0, AA_STROKES)
	_statics.draw_colored_polygon(_ellipse(skull + Vector2(2, -2), Vector2(3.0, 2.6)), edge)
	# Teeth along the jawline.
	for t_i in 5:
		var tx: float = lerpf(2.0, 17.0, float(t_i) / 4.0)
		_statics.draw_line(skull + Vector2(tx, 5), skull + Vector2(tx, 8.5), bone, 1.6, AA_STROKES)
	# Four legs braced on the plinth.
	for lx in [98.0, 124.0, 160.0, 182.0]:
		var top_y: float = 168.0 - sin((lx - 78.0) / 110.0 * PI) * 30.0 + 4.0
		_statics.draw_line(Vector2(lx, top_y), Vector2(lx - 5, 198), edge, 8.0, AA_STROKES)
		_statics.draw_line(Vector2(lx, top_y), Vector2(lx - 5, 198), bone, 4.2, AA_STROKES)
		_statics.draw_line(Vector2(lx - 5, 198), Vector2(lx + 4, 198), edge, 5.0, AA_STROKES)

	# --- Framed landscape on the gallery wall --------------------------------
	var frame := Rect2(272, 62, 118, 88)
	_soft_shadow(Vector2(frame.get_center().x, frame.end.y + 3.0), 56.0, 6.0, 0.14)
	_statics.draw_rect(frame.grow(5.0), UI.BRASS.darkened(0.25))
	_vgrad(frame.grow(1.0), UI.BRASS.lightened(0.15), UI.BRASS.darkened(0.15))
	var canvas_r := frame.grow(-7.0)
	_vgrad(canvas_r, Color("#BFDCF2"), Color("#E8DFC4"))
	_statics.draw_circle(canvas_r.position + Vector2(30, 22), 11.0, Color("#F7DE93"))
	_statics.draw_colored_polygon(PackedVector2Array([
		canvas_r.position + Vector2(-2, 74), canvas_r.position + Vector2(38, 34),
		canvas_r.position + Vector2(74, 74)]), Color("#7E9E78"))
	_statics.draw_colored_polygon(PackedVector2Array([
		canvas_r.position + Vector2(46, 74), canvas_r.position + Vector2(80, 42),
		canvas_r.position + Vector2(110, 74)]), Color("#5D8060"))
	_statics.draw_rect(canvas_r, UI.WALL_BROWN.darkened(0.2), false, 1.5)

	# --- Sarcophagus, upright in a display case ------------------------------
	var plinth := Rect2(294, 314, 96, 22)
	_soft_shadow(Vector2(plinth.get_center().x, plinth.end.y - 1.0), 52.0, 8.0, 0.20)
	_vgrad(plinth, Color("#CBBA9A"), Color("#A08D6E"))
	_statics.draw_rect(plinth, UI.WALL_BROWN, false, 2.0)
	var body := Rect2(306, 248, 72, 66)
	# Rounded lid: a capsule silhouette, not a box with a circle stuck on top.
	var lid := PackedVector2Array()
	for i in 13:
		var a: float = PI + PI * float(i) / 12.0
		lid.append(body.get_center() + Vector2(0, -33) + Vector2(cos(a) * 36.0, sin(a) * 30.0))
	lid.append(Vector2(body.end.x, body.end.y))
	lid.append(Vector2(body.position.x, body.end.y))
	_statics.draw_colored_polygon(lid, Color("#D2A047"))
	# Vertical sheen down the gold.
	_statics.draw_line(Vector2(body.position.x + 16, body.position.y - 18),
		Vector2(body.position.x + 16, body.end.y - 6), Color(1, 1, 1, 0.22), 6.0, true)
	var mask := Rect2(body.position.x + 12, body.position.y + 6, 48, 20)
	_statics.draw_rect(mask, Color("#3E7E8C"))
	_statics.draw_colored_polygon(_ellipse(mask.position + Vector2(15, 10), Vector2(5.0, 3.6)), UI.PANEL)
	_statics.draw_colored_polygon(_ellipse(mask.position + Vector2(33, 10), Vector2(5.0, 3.6)), UI.PANEL)
	_statics.draw_line(body.position + Vector2(10, 44), body.position + Vector2(62, 44),
		Color("#3E7E8C"), 4.0, true)
	_statics.draw_line(body.position + Vector2(14, 54), body.position + Vector2(58, 54),
		Color("#3E7E8C").darkened(0.2), 3.0, true)
	var ring := lid.duplicate()
	ring.append(lid[0])
	_statics.draw_polyline(ring, Color("#8A6524"), 2.2, AA_STROKES)

func _draw_vault_interior() -> void:
	# Round vault door, recessed into the back wall.
	var c := Vector2(614, 150)
	_soft_shadow(c + Vector2(0, 58), 54.0, 9.0, 0.18)
	_statics.draw_circle(c, 56.0, Color("#3C5068"))
	_statics.draw_circle(c, 50.0, Color("#5B7896"))
	_statics.draw_circle(c, 45.0, Color("#8FA9C8"))
	# Key light on the upper-left of the steel.
	_statics.draw_colored_polygon(_ellipse(c + Vector2(-12, -14), Vector2(24.0, 18.0)),
		Color(1, 1, 1, 0.14))
	for i in 8:
		var a: float = TAU * float(i) / 8.0
		_statics.draw_line(c + Vector2(cos(a), sin(a)) * 15.0,
			c + Vector2(cos(a), sin(a)) * 41.0, Color("#4A627E"), 4.0, true)
	_statics.draw_circle(c, 15.0, Color("#3C5068"))
	_statics.draw_circle(c, 9.0, UI.BRASS)
	_statics.draw_circle(c + Vector2(-2, -2), 4.0, UI.BRASS.lightened(0.35))
	# Hinges.
	for hy in [-30.0, 30.0]:
		_statics.draw_rect(Rect2(c.x + 52, c.y + hy - 6, 10, 12), Color("#3C5068"))

func _draw_promo_interior() -> void:
	# Poster board on the wall + campaign desk on the floor.
	var board := Rect2(496, 332, 92, 62)
	_soft_shadow(Vector2(board.get_center().x, board.end.y + 3.0), 44.0, 5.0, 0.14)
	_statics.draw_rect(board.grow(3.0), UI.WALL_BROWN)
	_vgrad(board, UI.PANEL, UI.PANEL.darkened(0.10))
	_statics.draw_circle(board.position + Vector2(24, 20), 9.0, UI.ROOM_PROMO)
	_statics.draw_line(board.position + Vector2(12, 42), board.position + Vector2(80, 42),
		UI.ROOM_PROMO.darkened(0.2), 3.0, true)
	_statics.draw_line(board.position + Vector2(12, 52), board.position + Vector2(62, 52),
		UI.ROOM_PROMO.darkened(0.2), 3.0, true)

	var desk := Rect2(548, 400, 118, 28)
	_soft_shadow(Vector2(desk.get_center().x, desk.end.y - 1.0), 62.0, 8.0, 0.20)
	_vgrad(desk, Color("#9C7550"), Color("#6E4E33"))
	_statics.draw_rect(desk, UI.WALL_BROWN, false, 2.0)
	_statics.draw_line(desk.position + Vector2(0, 3), Vector2(desk.end.x, desk.position.y + 3),
		Color(1, 1, 1, 0.18), 2.0, true)

func _draw_ticket_interior() -> void:
	for w in _windows_active:
		var wx: float = WINDOW_X[w]
		var counter := Rect2(wx - 46, COUNTER_Y, 92, 28)
		_soft_shadow(Vector2(wx, counter.end.y - 1.0), 50.0, 8.0, 0.22)
		# Counter body + brass service ledge catching the key light.
		_vgrad(counter, UI.ROOM_TICKET.darkened(0.04), UI.ROOM_TICKET.darkened(0.30))
		_statics.draw_rect(counter, UI.WALL_BROWN, false, 2.0)
		_vgrad(Rect2(wx - 48, COUNTER_Y - 6.0, 96, 8), UI.BRASS.lightened(0.25), UI.BRASS.darkened(0.2))
		# Window number plaque, on the counter face where nobody stands.
		_statics.draw_string(_font, Vector2(wx - 4, COUNTER_Y + 21), str(w + 1),
			HORIZONTAL_ALIGNMENT_LEFT, -1, 14, UI.FLOOR_CREAM)

		# Queue lane: brass stanchions with sagging velvet rope.
		for side in [-26.0, 26.0]:
			var px: float = wx + side
			var prev := Vector2.ZERO
			for j in SLOTS_PER_WINDOW:
				var py: float = SLOT_Y[j] + 2.0
				_soft_shadow(Vector2(px, py + 1.0), 5.0, 2.4, 0.18)
				_statics.draw_line(Vector2(px, py), Vector2(px, py - 13), UI.WALL_BROWN, 2.6, AA_STROKES)
				_statics.draw_circle(Vector2(px, py - 15), 3.8, UI.BRASS)
				_statics.draw_circle(Vector2(px - 1, py - 16), 1.6, UI.BRASS.lightened(0.4))
				if j > 0:
					var rope := PackedVector2Array()
					for k in 11:
						var t: float = float(k) / 10.0
						var p: Vector2 = prev.lerp(Vector2(px, py - 14), t)
						p.y += sin(t * PI) * 8.0
						rope.append(p)
					_statics.draw_polyline(rope, UI.ROPE_RED.darkened(0.25), 3.4, AA_STROKES)
					_statics.draw_polyline(rope, UI.ROPE_RED, 2.0, AA_STROKES)
				prev = Vector2(px, py - 14)

## Corner falloff. Sells "lit room" more cheaply than any amount of prop detail.
func _draw_vignette() -> void:
	var d := 54.0
	_vgrad(Rect2(0, 0, FLOOR.x, d), Color(0.22, 0.15, 0.07, 0.20), Color(0.22, 0.15, 0.07, 0.0))
	_vgrad(Rect2(0, FLOOR.y - d, FLOOR.x, d), Color(0.22, 0.15, 0.07, 0.0), Color(0.22, 0.15, 0.07, 0.22))
	_hgrad(Rect2(0, 0, d, FLOOR.y), Color(0.22, 0.15, 0.07, 0.16), Color(0.22, 0.15, 0.07, 0.0))
	_hgrad(Rect2(FLOOR.x - d, 0, d, FLOOR.y), Color(0.22, 0.15, 0.07, 0.0), Color(0.22, 0.15, 0.07, 0.16))

# --- Drawing helpers -----------------------------------------------------------

## Vertical gradient quad (per-vertex colours — one draw call, no banding).
func _vgrad(r: Rect2, top: Color, bottom: Color) -> void:
	_statics.draw_polygon(
		PackedVector2Array([r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)]),
		PackedColorArray([top, top, bottom, bottom]))

func _hgrad(r: Rect2, left: Color, right: Color) -> void:
	_statics.draw_polygon(
		PackedVector2Array([r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)]),
		PackedColorArray([left, right, right, left]))

## Single soft ellipse. The old version stacked two to fake a penumbra, which
## doubled the shadow draw-call count for a difference invisible at phone size.
func _soft_shadow(center: Vector2, rx: float, ry: float, alpha: float) -> void:
	_statics.draw_colored_polygon(_ellipse(center, Vector2(rx, ry), 16),
		Color(0.20, 0.13, 0.06, alpha))

func _ellipse(center: Vector2, radii: Vector2, segments: int = 22) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in segments:
		var a := TAU * float(i) / float(segments)
		pts.append(center + Vector2(cos(a) * radii.x, sin(a) * radii.y))
	return pts

## Filled band between two radii over an angular sweep (fanlights, arches).
func _arc_band(center: Vector2, radius: float, from_a: float, to_a: float,
		thickness: float, segments: int = 18) -> PackedVector2Array:
	var outer := PackedVector2Array()
	var inner := PackedVector2Array()
	for i in segments + 1:
		var a: float = lerpf(from_a, to_a, float(i) / float(segments))
		outer.append(center + Vector2(cos(a), sin(a)) * radius)
		inner.append(center + Vector2(cos(a), sin(a)) * (radius - thickness))
	inner.reverse()
	var pts := outer
	pts.append_array(inner)
	return pts


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
