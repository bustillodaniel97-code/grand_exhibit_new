extends Node3D
## CafeWorld — the Pop-Up Café as a live toy diorama (art3d/cafe).
##
## Built from data/cafe_event.json: the terrace shell, the four stations at
## their spots, bistro tables and a menu board, all recoloured to the event's
## theme through their c_* role materials. Closed stations wait under dust
## sheets. Customers walk in, buy at an open station (a coin pops) and linger
## at a table before leaving. Decoration only: CafeSystem owns the numbers.

const CafeSystem := preload("res://scripts/events/cafe_system.gd")
const Npc := preload("res://scenes/venue3d/toy_npc.gd")
const Venue3D := preload("res://scenes/venue3d/venue_3d.gd")
const POP_FONT := preload("res://assets/fonts/Quicksand-Bold.ttf")
const DUST := "res://art3d/props/dust_sheet.glb"
const FLOOR_Y := 0.36
const ENTRANCE := Vector3(0.0, 0.05, 4.6)

var camera: Camera3D
var customers := 6
var _stations := {}   # id -> {"node", "sheet", "label", "spot"}
var _rng := RandomNumberGenerator.new()
var _spawn_clock := 0.5
var _count := 0
var _closing := false
var _tints := {}

func _ready() -> void:
	_rng.randomize()
	_environment()
	var palette: Dictionary = CafeSystem.theme().get("palette", {})
	add_child(_kit("cafe_shell", palette))
	_sign(str(CafeSystem.theme().get("name", "Pop-Up Cafe")), palette)
	for st in CafeSystem.stations():
		var id := str(st["id"])
		var pos: Array = st.get("pos", [0, 0])
		var at := Vector3(float(pos[0]), FLOOR_Y, -float(pos[1]))
		var node := _kit(str(st.get("kit", "coffee_bar")), palette)
		node.position = at
		add_child(node)
		var label := Label3D.new()
		label.font = POP_FONT
		label.font_size = 40
		label.outline_size = 12
		label.outline_modulate = Color("#3A2A10")
		label.pixel_size = 0.006
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.no_depth_test = true
		label.position = at + Vector3(0.0, 2.0, 0.3)
		add_child(label)
		var sheet: Node3D = null
		if ResourceLoader.exists(DUST):
			sheet = (load(DUST) as PackedScene).instantiate()
			sheet.position = at
			sheet.scale = Vector3(1.05, 0.9, 0.85)
			add_child(sheet)
		_stations[id] = {"node": node, "sheet": sheet, "label": label, "spot": at + Vector3(0.0, 0.0, 1.0)}
	for tpos in CafeSystem.config().get("tables", []):
		var t := _kit("bistro_table", palette)
		t.position = Vector3(float(tpos[0]), FLOOR_Y, -float(tpos[1]))
		add_child(t)
	var menu := _kit("menu_board", palette)
	menu.position = Vector3(2.1, FLOOR_Y, 2.7)
	menu.rotation.y = -0.4
	add_child(menu)
	camera = Camera3D.new()
	camera.fov = 30.0
	var eye := Vector3(0.0, 8.2, 13.2)
	camera.transform = Transform3D(Basis.looking_at(Vector3(0.0, 1.1, 0.2) - eye), eye)
	add_child(camera)
	camera.current = true
	refresh()

func _exit_tree() -> void:
	_closing = true
	# A coroutine awaiting a signal of an object that is then freed is never
	# released. Wake every suspended customer and wait; each sees _closing.
	for c in get_children():
		if c is Npc:
			(c as Npc).arrived.emit()
	for t in _waits.duplicate():
		if is_instance_valid(t):
			(t as Timer).timeout.emit()
	_waits.clear()

## Show levels, open stations and dust sheets from CafeSystem.
func refresh() -> void:
	for id in _stations.keys():
		var s: Dictionary = _stations[id]
		var lvl := CafeSystem.level(id)
		(s["node"] as Node3D).visible = lvl > 0
		if s["sheet"] != null:
			(s["sheet"] as Node3D).visible = lvl <= 0
		var label: Label3D = s["label"]
		label.text = tr("%s\nLv %d") % [CafeSystem.station_name(id), lvl] if lvl > 0 else tr("%s\nClosed") % CafeSystem.station_name(id)
		label.modulate = Color("#FFF3B0") if lvl > 0 else Color("#E6DCC4")

## A station just levelled: bounce it and throw a sparkle of stars.
func celebrate(id: String) -> void:
	if not _stations.has(id):
		return
	refresh()
	var node: Node3D = _stations[id]["node"]
	var tw := create_tween()
	tw.tween_property(node, "scale", Vector3(1.12, 1.18, 1.12), 0.08)
	tw.tween_property(node, "scale", Vector3.ONE, 0.25).set_trans(Tween.TRANS_BACK)
	pop_text(node.position + Vector3(0.0, 1.8, 0.0), "Level up!", Color("#9BF08A"))

func station_top(id: String) -> Vector3:
	if not _stations.has(id):
		return Vector3.ZERO
	return (_stations[id]["node"] as Node3D).position + Vector3(0.0, 1.4, 0.0)

func pop_text(at: Vector3, text: String, color := Color("#FFD34D")) -> void:
	var l := Label3D.new()
	l.text = text
	l.font = POP_FONT
	l.font_size = 48
	l.outline_size = 12
	l.outline_modulate = Color("#3A2A10")
	l.modulate = color
	l.pixel_size = 0.006
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.no_depth_test = true
	add_child(l)
	l.position = at
	var tw := l.create_tween()
	tw.set_parallel(true)
	tw.tween_property(l, "position", at + Vector3(0.0, 1.0, 0.0), 1.1)
	tw.tween_property(l, "modulate:a", 0.0, 1.1).set_delay(0.4)
	tw.chain().tween_callback(l.queue_free)

# ------------------------------------------------------------------ customers
func _process(delta: float) -> void:
	_spawn_clock -= delta
	if _spawn_clock > 0.0 or _count >= customers or _closing:
		return
	_spawn_clock = _rng.randf_range(1.2, 2.6)
	var open: Array = []
	for id in _stations.keys():
		if CafeSystem.level(id) > 0:
			open.append(id)
	if open.is_empty():
		return
	_visit(str(open[_rng.randi() % open.size()]))

func _visit(id: String) -> void:
	_count += 1
	var n := Npc.new()
	add_child(n)
	var pick := func(arr: Array) -> String: return str(arr[_rng.randi() % arr.size()])
	var look := {"skin": pick.call(Venue3D.SKIN), "hair": pick.call(Venue3D.HAIR), "shirt": pick.call(Venue3D.SHIRT),
		"pants": pick.call(Venue3D.PANTS), "shoe": pick.call(Venue3D.SHOE), "acc": []}
	if _rng.randf() < 0.3:
		look["acc"] = [pick.call(["acc_hat", "acc_cap", "acc_bow", "acc_bag"])]
	n.setup(look)
	n.speed = _rng.randf_range(1.0, 1.3)
	n.position = ENTRANCE + Vector3(_rng.randf_range(-0.5, 0.5), 0.0, 0.0)
	var spot: Vector3 = _stations[id]["spot"] + Vector3(_rng.randf_range(-0.3, 0.3), 0.0, 0.0)
	for p in [Vector3(n.position.x * 0.5, FLOOR_Y, 2.8), Vector3(spot.x * 0.4, FLOOR_Y, spot.z), spot]:
		await _walk(n, p)
		if not _alive(n):
			return
	n.face(spot + Vector3(0.0, 0.0, -1.0))
	await _wait(_rng.randf_range(1.2, 2.4))
	if not _alive(n):
		return
	pop_text(station_top(id), "+" + BigNumber.from_float(CafeSystem.income(id) * 3.0).to_notation(), Color("#FFE680"))
	var tables: Array = CafeSystem.config().get("tables", [])
	if not tables.is_empty() and _rng.randf() < 0.7:
		var t: Array = tables[_rng.randi() % tables.size()]
		var side := -0.55 if _rng.randf() < 0.5 else 0.55
		var seat := Vector3(float(t[0]) + side, FLOOR_Y, -float(t[1]) + 0.45)
		await _walk(n, seat)
		if not _alive(n):
			return
		n.face(Vector3(float(t[0]), FLOOR_Y, -float(t[1])))
		if _rng.randf() < 0.4:
			n.play("cheer")
		await _wait(_rng.randf_range(2.5, 5.0))
		if not _alive(n):
			return
	for p in [Vector3(0.0, FLOOR_Y, 2.8), ENTRANCE + Vector3(_rng.randf_range(-0.5, 0.5), 0.0, 0.6)]:
		await _walk(n, p)
		if not _alive(n):
			return
	_count -= 1
	n.queue_free()

func _walk(n: Npc, to: Vector3) -> void:
	n.walk_to(to)
	if n.is_walking():
		await n.arrived

## Wait on a child Timer (never a SceneTreeTimer): it dies with the café, so a
## customer suspended here is released when the screen closes.
func _wait(secs: float) -> void:
	var t := Timer.new()
	t.one_shot = true
	t.wait_time = maxf(secs, 0.01)
	add_child(t)
	_waits.append(t)
	t.start()
	await t.timeout
	_waits.erase(t)
	if is_instance_valid(t):
		t.queue_free()

var _waits: Array = []

func _alive(n: Object) -> bool:
	return not _closing and is_instance_valid(n) and is_inside_tree()

# ------------------------------------------------------------------ building
func _kit(kind: String, palette: Dictionary) -> Node3D:
	var path := "res://art3d/cafe/%s.glb" % kind
	if not ResourceLoader.exists(path):
		return Node3D.new()
	var node: Node3D = (load(path) as PackedScene).instantiate()
	for child in node.find_children("*", "MeshInstance3D", true, false):
		var mi := child as MeshInstance3D
		for s in mi.mesh.get_surface_count():
			var src := mi.mesh.surface_get_material(s)
			if src != null and palette.has(src.resource_name):
				mi.set_surface_override_material(s, _tint(src, str(palette[src.resource_name])))
	return node

func _tint(src: Material, hex: String) -> Material:
	var key := "%s|%s" % [src.resource_name, hex]
	if not _tints.has(key):
		var m := src.duplicate() as StandardMaterial3D
		m.albedo_color = Color(hex)
		_tints[key] = m
	return _tints[key]

func _sign(text: String, palette: Dictionary) -> void:
	var l := Label3D.new()
	l.text = text
	l.font = POP_FONT
	l.font_size = 72
	l.outline_size = 10
	l.outline_modulate = Color(str(palette.get("c_sign", "#2B2245"))).darkened(0.3)
	l.modulate = Color("#FFF3B0")
	l.pixel_size = 0.0075
	l.width = 520.0
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.position = Vector3(0.0, 3.55, -3.06)
	add_child(l)

func _environment() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("#bfe3ff")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("#cfe0ff")
	env.ambient_light_energy = 0.3
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	env.glow_enabled = true
	env.glow_intensity = 0.2
	env.glow_hdr_threshold = 1.4
	env.adjustment_enabled = true
	env.adjustment_saturation = 1.2
	env.adjustment_contrast = 1.08
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55.0, -30.0, 0.0)
	sun.light_energy = 0.65
	sun.light_color = Color("#fff3df")
	sun.shadow_enabled = true
	sun.shadow_blur = 1.4
	sun.directional_shadow_max_distance = 40.0
	add_child(sun)
	# A lawn around the terrace so it doesn't float in the sky.
	var lawn := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(40.0, 40.0)
	lawn.mesh = pm
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color("#5E9E48")
	gm.roughness = 0.9
	lawn.material_override = gm
	lawn.position.y = -0.01
	add_child(lawn)
