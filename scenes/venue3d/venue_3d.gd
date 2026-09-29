extends Node3D
## Real-time 3D museum floor in the toy-diorama style (vertical slice, museum 1).
##
## Everything is built from the venue's authored data (data/venues.json ->
## theme): the SAME rooms, walls, props, exhibits and stations the 2D floor
## draws, rendered from the glTF kit that tools/blender/toybox generates into
## art3d/. Placement mirrors tools/blender/toybox/venue.py `_place`; keep the
## two in step when a rule changes.
##
## Grid -> world: a grid point (gx, gy) is world (gx, height, gy). The camera
## looks toward -Z, so the building's front (large gy) faces the player.

const Npc := preload("res://scenes/venue3d/toy_npc.gd")
const ToyCamera := preload("res://scenes/venue3d/toy_camera.gd")
const TILT_SHIFT := preload("res://scenes/venue3d/tilt_shift.gdshader")

const FLOOR_TOP := 0.17
const WALL_T := 0.16

## kind -> [art3d folder, footprint it was modelled at]
## (tools/blender/toybox/props.py PROPS).
const KIT := {
	"planter": ["props", Vector2(0.5, 0.5)], "bench": ["props", Vector2(1.5, 0.4)],
	"kiosk": ["props", Vector2(0.7, 0.7)], "shelf": ["props", Vector2(2.0, 0.5)],
	"crate": ["props", Vector2(0.8, 0.6)], "cabinet": ["props", Vector2(0.5, 0.7)],
	"vault_door": ["props", Vector2(1.6, 0.24)], "info_desk": ["props", Vector2(2.2, 0.7)],
	"bin": ["props", Vector2(0.3, 0.3)], "desk": ["props", Vector2(1.9, 0.6)],
	"facade": ["props", Vector2(2.4, 0.5)], "ticket_counter": ["props", Vector2(1.55, 0.6)],
	"docent_stand": ["props", Vector2(0.5, 0.4)], "promo_booth": ["props", Vector2(1.9, 0.6)],
	"rope_post": ["props", Vector2(0.2, 0.2)],
	"skeleton": ["exhibits", Vector2(3.2, 1.2)], "mural": ["exhibits", Vector2(2.2, 0.08)],
	"casket": ["exhibits", Vector2(1.0, 1.0)], "statue": ["exhibits", Vector2(1.0, 1.0)],
	"vitrine": ["exhibits", Vector2(0.7, 1.5)], "case": ["exhibits", Vector2(1.5, 0.7)],
}
const HERO_KINDS := ["skeleton", "casket", "statue"]

# Cast palettes: brighter than the 2D cast's, for the toy look.
const SKIN := ["#FFE0C2", "#F7C9A0", "#E3A876", "#C68552", "#94603A", "#6E4529"]
const HAIR := ["#2B2320", "#5A3A22", "#8A5A2B", "#E0B14A", "#E8E4DC", "#C0452E", "#5B3F8C"]
const SHIRT := ["#3A78D8", "#E0524A", "#4FB86A", "#F2A33A", "#8E6BD8", "#2FB0B0", "#E36FA8", "#F2D14A"]
const PANTS := ["#2F3848", "#5A4A3A", "#3F5A84", "#4A3F5A", "#7A6A5A"]
const SHOE := ["#5A3A22", "#2B2B33", "#E8E4DC", "#C0392B"]
const DEPT_VEST := {"ticket": "#C0392B", "gallery": "#2E8B57", "promotions": "#8E44AD", "archive": "#8B5A2B"}

@export var venue_id := "whispering_pines"
@export var visitor_target := 26

var theme: Dictionary = {}
var rooms: Array = []
var W := 14.0
var H := 18.0
var road_z := 0.0
var camera: Camera3D

var _rng := RandomNumberGenerator.new()
var _scenes := {}
var _region: NavigationRegion3D
var _nav_ready := false
var _visitors := 0
var _spawn_clock := 0.0
var _windows: Array = []  # {spot, look}: where a visitor stands to buy a ticket
var _views: Array = []    # {spot, look, hero}
var _door_out := Vector3.ZERO
var _door_in := Vector3.ZERO
var _exit_in := Vector3.ZERO
var _exit_out := Vector3.ZERO
var _vehicles: Array = []

func _ready() -> void:
	_rng.seed = 20260928
	get_viewport().msaa_3d = Viewport.MSAA_4X
	theme = DataLoader.get_venue(venue_id).get("theme", {})
	rooms = theme.get("rooms", [])
	_measure()
	_environment()
	_region = NavigationRegion3D.new()
	add_child(_region)
	_region.add_child(_scene("res://art3d/venues/%s/shell.glb" % venue_id).instantiate())
	_place_all()
	_staff()
	_traffic()
	_camera()
	_tilt_shift()
	_bake_nav()

# ------------------------------------------------------------------ layout
func _measure() -> void:
	for r in rooms:
		var rect: Array = r["rect"]
		W = maxf(W, float(rect[0]) + float(rect[2]))
		H = maxf(H, float(rect[1]) + float(rect[3]))
	road_z = H + 5.2 + 1.5
	var door_x := W * 0.5
	for p in theme.get("props", []):
		if str(p.get("kind", "")) == "facade":
			door_x = float(p["at"][0]) + float(p.get("len", 2.4)) * 0.5
	_door_out = Vector3(door_x, 0.08, H + 1.4)
	_door_in = Vector3(door_x, FLOOR_TOP, H - 0.6)
	var lobby := _room_by_role("lobby")
	var ex: Array = lobby.get("exit", [W * 0.5, 3])
	var ex_x := float(lobby["rect"][0]) + float(ex[0])
	_exit_in = Vector3(ex_x, FLOOR_TOP, H - 0.6)
	_exit_out = Vector3(ex_x, 0.08, H + 1.4)

func _room_by_role(role: String) -> Dictionary:
	for r in rooms:
		if str(r.get("role", "")) == role:
			return r
	return {}

func _room_by_id(id: String) -> Dictionary:
	for r in rooms:
		if str(r.get("id", "")) == id:
			return r
	return {}

func _scene(path: String) -> PackedScene:
	if not _scenes.has(path):
		_scenes[path] = load(path)
	return _scenes[path]

func _kit(kind: String) -> Node3D:
	var info: Array = KIT[kind]
	return _scene("res://art3d/%s/%s.glb" % [info[0], kind]).instantiate()

static func _v2(a: Variant, fallback := Vector2.ZERO) -> Vector2:
	if a is Array and (a as Array).size() >= 2:
		return Vector2(float(a[0]), float(a[1]))
	return fallback

# ------------------------------------------------------------------ props
func _place_all() -> void:
	for spec in theme.get("props", []) + theme.get("exhibits", []):
		var kind := str(spec.get("kind", ""))
		if KIT.has(kind):
			_place(kind, spec)
		if spec.has("barrier"):
			_rope_line(spec["barrier"])
		if spec.has("views") and spec.has("anchor"):
			var anchor := _v2(spec["anchor"])
			for v in spec["views"]:
				var p := anchor + _v2(v)
				_views.append({"spot": Vector3(p.x, FLOOR_TOP, p.y), "look": Vector3(anchor.x, 1.0, anchor.y),
					"hero": kind in HERO_KINDS})
	for room in rooms:
		var origin := _v2(room["rect"])
		if str(room.get("role", "")) == "exhibit":
			for s in room.get("stations", []):
				_place("docent_stand", {"at": [origin.x + float(s[0]), origin.y + float(s[1])]})
		var q: Dictionary = room.get("queue", {})
		for st in q.get("stations", []):
			var base := _v2(_room_by_id(str(st.get("room", ""))).get("rect", room["rect"]))
			var at := base + _v2(st["at"])
			var f := _v2(st.get("front"), Vector2(1, 0))
			_place("ticket_counter", {"at": [at.x + f.x * 0.15, at.y + f.y * 0.15], "front": [f.x, f.y]})
			var spot := at + f * 0.85
			_windows.append({"spot": Vector3(spot.x, FLOOR_TOP, spot.y), "look": Vector3(at.x, 0.5, at.y),
				"clerk": Vector3(at.x - f.x * 0.55, FLOOR_TOP, at.y - f.y * 0.55), "front": f})

func _place(kind: String, spec: Dictionary) -> Node3D:
	var node := _kit(kind)
	_region.add_child(node)
	var fp: Vector2 = KIT[kind][1]
	var at := _v2(spec.get("at"))
	if kind == "mural":
		var len_m := float(spec.get("len", 2.2))
		node.position = Vector3(at.x + len_m * 0.5, FLOOR_TOP + 0.55, at.y + WALL_T * 0.5 + 0.05)
		return node
	if kind == "vault_door" or kind == "facade":
		var length := float(spec.get("len", fp.x))
		var vertical := str(spec.get("axis", "x")) == "y"
		var c := Vector2(at.x, at.y + length * 0.5) if vertical else Vector2(at.x + length * 0.5, at.y)
		node.position = Vector3(c.x, FLOOR_TOP, c.y)
		node.rotation.y = PI * 0.5 if vertical else 0.0
		return node
	var size := Vector2.ZERO
	if spec.has("size"):
		size = _v2(spec["size"])
	elif spec.has("len") or kind == "bench":
		var l := float(spec.get("len", 1.5))
		size = Vector2(0.4, l) if str(spec.get("axis", "x")) == "y" else Vector2(l, 0.4)
	if size == Vector2.ZERO:  # point-placed piece
		node.position = Vector3(at.x, FLOOR_TOP, at.y)
		if spec.has("front"):
			var f := _v2(spec["front"])
			node.rotation.y = atan2(f.x, f.y)
		return node
	var rotate := (fp.x >= fp.y) != (size.x >= size.y)
	node.position = Vector3(at.x + size.x * 0.5, FLOOR_TOP, at.y + size.y * 0.5)
	node.rotation.y = PI * 0.5 if rotate else 0.0
	var k := maxf(size.x, size.y) / maxf(fp.x, fp.y)
	var short := clampf(minf(size.x, size.y) / minf(fp.x, fp.y), 0.6, 1.4)
	node.scale = Vector3(k, 1.0, short)  # local axes, applied before the turn
	return node

func _rope_line(barrier: Dictionary) -> void:
	var a := _v2(barrier.get("from"))
	var b := _v2(barrier.get("to"))
	var posts := maxi(2, int(barrier.get("posts", 3)))
	var rope := StandardMaterial3D.new()
	rope.albedo_color = Color("#B0263A")
	rope.roughness = 0.5
	for i in posts:
		var p := a.lerp(b, float(i) / float(posts - 1))
		_place("rope_post", {"at": [p.x, p.y]})
		if i > 0:
			var q := a.lerp(b, float(i - 1) / float(posts - 1))
			var seg := MeshInstance3D.new()
			var cyl := CylinderMesh.new()
			cyl.top_radius = 0.02
			cyl.bottom_radius = 0.02
			cyl.height = p.distance_to(q)
			cyl.radial_segments = 8
			seg.mesh = cyl
			seg.material_override = rope
			_region.add_child(seg)
			var mid := (p + q) * 0.5
			seg.position = Vector3(mid.x, FLOOR_TOP + 0.5, mid.y)
			var d := p - q
			seg.rotation = Vector3(0.0, -atan2(d.y, d.x), PI * 0.5)

# ------------------------------------------------------------------ people
func _look(role := "visitor", dept := "") -> Dictionary:
	var pick := func(arr: Array) -> String: return str(arr[_rng.randi() % arr.size()])
	var look := {"skin": pick.call(SKIN), "hair": pick.call(HAIR), "shirt": pick.call(SHIRT),
		"pants": pick.call(PANTS), "shoe": pick.call(SHOE), "acc": []}
	var acc: Array = look["acc"]
	if role == "staff":
		look["shirt"] = "#FFF7E6"
		look["pants"] = "#2F3848"
		look["acc_vest"] = DEPT_VEST.get(dept, "#C0392B")
		acc.append("acc_vest")
		if dept == "archive":
			acc.append("acc_cap")
			look["acc_cap"] = "#8B5A2B"
		return look
	var r := _rng.randf()
	if r < 0.18:
		acc.append("acc_hat")
	elif r < 0.36:
		acc.append("acc_cap")
		look["acc_cap"] = pick.call(SHIRT)
	elif r < 0.5:
		acc.append("acc_bow")
	if _rng.randf() < 0.25:
		acc.append("acc_backpack")
		look["acc_pack"] = pick.call(SHIRT)
	if _rng.randf() < 0.2:
		acc.append("acc_glasses")
	if _rng.randf() < 0.18:
		acc.append("acc_camera")
	if _rng.randf() < 0.15:
		acc.append("acc_bag")
	var age := _rng.randf()
	if age < 0.2:
		look["scale"] = 0.78  # kids
	elif age > 0.88:
		look["hair"] = "#E8E4DC"
	return look

func _spawn(look: Dictionary, at: Vector3) -> Npc:
	var n := Npc.new()
	add_child(n)
	n.global_position = at
	n.setup(look)
	return n

func _staff() -> void:
	for w in _windows:
		var clerk := _spawn(_look("staff", "ticket"), w["clerk"])
		clerk.face(w["spot"])
	for room in rooms:
		var origin := _v2(room["rect"])
		var dept := str(room.get("dept", ""))
		for s in room.get("stations", []):
			var p := origin + _v2(s) + (Vector2(0.35, 0.1) if dept == "gallery" else Vector2.ZERO)
			var n := _spawn(_look("staff", dept), Vector3(p.x, FLOOR_TOP, p.y))
			n.face(Vector3(p.x, 0.0, p.y + 1.0))
		if room.has("marketer"):
			var m := origin + _v2(room["marketer"])
			_spawn(_look("staff", "promotions"), Vector3(m.x, FLOOR_TOP, m.y)).face(_door_in + Vector3(0, 0, 3))
		var store: Dictionary = room.get("store", {})
		if store.has("home"):
			var h := origin + _v2(store["home"])
			_spawn(_look("staff", "archive"), Vector3(h.x, FLOOR_TOP, h.y)).face(Vector3(h.x + 1.0, 0.0, h.y))

func _process(delta: float) -> void:
	_drive(delta)
	if not _nav_ready:
		return
	_spawn_clock -= delta
	if _visitors < visitor_target and _spawn_clock <= 0.0:
		_spawn_clock = _rng.randf_range(0.6, 1.8)
		var side := -7.0 if _rng.randf() < 0.5 else W + 7.0
		_visit(_spawn(_look(), Vector3(side, 0.1, road_z - 2.35)))

## A visitor's day: in through the entrance, buy a ticket, look at two or
## three exhibits (cheering at the hero pieces), then out through the exit.
## `inside` starts them already past the ticket desk (the opening crowd).
func _visit(n: Npc, inside := false) -> void:
	_visitors += 1
	n.speed = _rng.randf_range(0.9, 1.25)
	if not inside:
		await _walk(n, _door_out + Vector3(_rng.randf_range(-0.6, 0.6), 0, 0))
		await _walk(n, _door_in)
	if not inside and not _windows.is_empty():
		var w: Dictionary = _windows[_rng.randi() % _windows.size()]
		await _walk(n, w["spot"] + Vector3(_rng.randf_range(-0.2, 0.2), 0, _rng.randf_range(-0.2, 0.2)))
		n.face(w["look"])
		await get_tree().create_timer(_rng.randf_range(1.2, 2.6)).timeout
	for i in _rng.randi_range(2, 3):
		if _views.is_empty():
			break
		var v: Dictionary = _views[_rng.randi() % _views.size()]
		await _walk(n, v["spot"])
		n.face(v["look"])
		if bool(v["hero"]) and _rng.randf() < 0.5:
			n.play("cheer")
		await get_tree().create_timer(_rng.randf_range(2.0, 4.5)).timeout
	await _walk(n, _exit_in)
	await _walk(n, _exit_out)
	var leave_x := -7.0 if n.global_position.x < W * 0.5 else W + 7.0
	await _walk(n, Vector3(leave_x, 0.1, road_z - 2.35))
	_visitors -= 1
	n.queue_free()

func _walk(n: Npc, to: Vector3) -> void:
	n.walk_to(to)
	if n.is_walking():
		await n.arrived

# ------------------------------------------------------------------ traffic
func _traffic() -> void:
	var paints := ["#D9413A", "#3A78D8", "#F2D14A", "#4FB86A", "#FFFFFF", "#8E6BD8"]
	for i in 5:
		var bus := i == 0
		var car: Node3D = _scene("res://art3d/vehicles/%s.glb" % ("bus" if bus else "car")).instantiate()
		add_child(car)
		var dir := 1.0 if i % 2 == 0 else -1.0
		car.position = Vector3(_rng.randf_range(-10.0, W + 10.0), 0.03, road_z + (0.75 if dir > 0 else -0.75))
		car.rotation.y = 0.0 if dir > 0 else PI
		if not bus:
			for node in car.find_children("*", "MeshInstance3D", true, false):
				var mi := node as MeshInstance3D
				for s in mi.mesh.get_surface_count():
					var src := mi.mesh.surface_get_material(s)
					if src and src.resource_name == "paint":
						var m := src.duplicate() as StandardMaterial3D
						m.albedo_color = Color(paints[i % paints.size()])
						mi.set_surface_override_material(s, m)
		_vehicles.append({"node": car, "dir": dir, "speed": 1.6 if bus else _rng.randf_range(2.2, 3.4),
			"wheels": car.find_children("wheel_*", "Node3D", true, false), "wait": 0.0, "bus": bus})

func _drive(delta: float) -> void:
	for v in _vehicles:
		var car: Node3D = v["node"]
		if float(v["wait"]) > 0.0:
			v["wait"] = float(v["wait"]) - delta
			continue
		var dx := float(v["dir"]) * float(v["speed"]) * delta
		var before := car.position.x
		car.position.x += dx
		for w in v["wheels"]:
			(w as Node3D).rotation.z -= dx / 0.17
		# The bus stops at the shelter in front of the museum.
		if bool(v["bus"]) and signf(before - 1.5) != signf(car.position.x - 1.5):
			v["wait"] = 3.0
		if car.position.x > W + 12.0:
			car.position.x = -12.0
		elif car.position.x < -12.0:
			car.position.x = W + 12.0

# ------------------------------------------------------------------ look
func _environment() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("#bfe3ff")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("#cfe0ff")
	env.ambient_light_energy = 0.32
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 0.78
	env.glow_enabled = true
	env.glow_intensity = 0.2
	env.glow_hdr_threshold = 1.4
	env.adjustment_enabled = true
	env.adjustment_saturation = 1.2
	env.adjustment_contrast = 1.1
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-52.0, -32.0, 0.0)
	sun.light_energy = 1.05
	sun.light_color = Color("#fff3df")
	sun.shadow_enabled = true
	sun.shadow_blur = 1.6
	sun.directional_shadow_max_distance = 90.0
	add_child(sun)

func _camera() -> void:
	camera = ToyCamera.new()
	add_child(camera)
	camera.bounds = Rect2(-3.0, -3.0, W + 6.0, H + 12.0)
	camera.frame(Rect2(0.0, 0.0, W, H + 3.0), 0.6)
	camera.current = true

func _tilt_shift() -> void:
	var layer := CanvasLayer.new()
	layer.layer = -1
	add_child(layer)
	var rect := ColorRect.new()
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var mat := ShaderMaterial.new()
	mat.shader = TILT_SHIFT
	rect.material = mat
	layer.add_child(rect)

# ------------------------------------------------------------------ navigation
func _bake_nav() -> void:
	var map := get_world_3d().navigation_map
	NavigationServer3D.map_set_cell_size(map, 0.08)
	NavigationServer3D.map_set_cell_height(map, 0.04)
	# Bevelled floor tiles leave hairline steps that Recast splits into
	# near-duplicate edges; a finer merge grid keeps them from colliding.
	NavigationServer3D.map_set_merge_rasterizer_cell_scale(map, 0.001)
	var nm := NavigationMesh.new()
	nm.cell_size = 0.08
	nm.cell_height = 0.04
	nm.agent_radius = 0.2
	nm.agent_height = 0.9
	nm.agent_max_climb = 0.14
	nm.agent_max_slope = 30.0
	nm.geometry_parsed_geometry_type = NavigationMesh.PARSED_GEOMETRY_MESH_INSTANCES
	nm.filter_baking_aabb = AABB(Vector3(-9.0, -1.0, -8.0), Vector3(W + 18.0, 4.0, H + 22.0))
	_region.navigation_mesh = nm
	_region.bake_finished.connect(_on_baked, CONNECT_ONE_SHOT)
	_region.bake_navigation_mesh(true)

func _on_baked() -> void:
	await get_tree().physics_frame
	await get_tree().physics_frame
	_nav_ready = true
	# Open with a crowd already inside rather than an empty hall.
	for i in mini(_views.size() * 2, visitor_target / 2):
		var v: Dictionary = _views[_rng.randi() % _views.size()]
		var at: Vector3 = v["spot"] + Vector3(_rng.randf_range(-0.3, 0.3), 0.0, _rng.randf_range(-0.3, 0.3))
		_visit(_spawn(_look(), at), true)
