extends Node3D
## DigPit — the 3D excavation pit for one Dig Site (toy-diorama style).
##
## A 7 x 9 pit framed in timber, each cell a stack of rounded soil blocks
## (art3d/digsite/soil_block.glb, recoloured per layer from the site's soil
## palette). Under the soil lies the artifact (art3d/artifacts/<shape>.glb,
## stretched to its footprint and painted from dig_sites.json), plus coins,
## gems and energy crystals. The pit only DRAWS the site dict; the rules live in
## scripts/digsite/dig_logic.gd and the screen feeds results back in via
## apply_result().
##
## Grid -> world: cell (x, y) is centred at (x - cols/2 + 0.5, *, y - rows/2 + 0.5);
## the surface is y = 0 and the pit floor, where finds rest, is y = -LAYER_H x layers.

const DigLogic := preload("res://scripts/digsite/dig_logic.gd")
const POP_FONT := preload("res://assets/fonts/Quicksand-Bold.ttf")
const ToyLook := preload("res://scripts/render/toy_look.gd")
const LAYER_H := 0.3

var site: Dictionary = {}
var site_def: Dictionary = {}
var art_def: Dictionary = {}
var camera: Camera3D

var _blocks := {}        # cell index -> Array[Node3D] (bottom first)
var _finds := {}         # cell index -> Node3D
var _flags := {}         # cell index -> Node3D
var _artifact: Node3D
var _soil_mats: Array = []
var _rock_mat: StandardMaterial3D
var _peek_mat: StandardMaterial3D
var _scenes := {}
var _board: Node3D

func setup(p_site: Dictionary, p_site_def: Dictionary, p_art_def: Dictionary) -> void:
	site = p_site
	site_def = p_site_def
	art_def = p_art_def
	if is_inside_tree():
		_rebuild()

func _ready() -> void:
	_environment()
	_camera()
	_surroundings()
	if not site.is_empty():
		_rebuild()

func _scene(path: String) -> PackedScene:
	if not _scenes.has(path):
		_scenes[path] = load(path)
	return _scenes[path]

func _cols() -> int:
	return int(site.get("cols", 7))

func _rows() -> int:
	return int(site.get("rows", 9))

func _depth() -> int:
	var mx := 1
	for v in site.get("layers", []):
		mx = maxi(mx, int(v))
	return maxi(mx, 3)

func cell_center(x: int, y: int, h := 0.0) -> Vector3:
	return Vector3(float(x) - _cols() * 0.5 + 0.5, h, float(y) - _rows() * 0.5 + 0.5)

func floor_y() -> float:
	return -LAYER_H * 3.0

## Screen point -> cell [x, y], or [] when outside the pit.
func cell_at(screen: Vector2) -> Array:
	if camera == null:
		return []
	var hit: Variant = Plane(Vector3.UP, -0.15).intersects_ray(camera.project_ray_origin(screen), camera.project_ray_normal(screen))
	if hit == null:
		return []
	var p := hit as Vector3
	var x := int(floor(p.x + _cols() * 0.5))
	var y := int(floor(p.z + _rows() * 0.5))
	if x < 0 or y < 0 or x >= _cols() or y >= _rows():
		return []
	return [x, y]

# ------------------------------------------------------------------ building
func _rebuild() -> void:
	if _board != null:
		_board.queue_free()
	_board = Node3D.new()
	_board.name = "Board"
	add_child(_board)
	_blocks.clear()
	_finds.clear()
	_flags.clear()
	var soil: Array = site_def.get("soil", ["#D9B27A", "#B98A57", "#8E6440"])
	_soil_mats.clear()
	for c in soil:
		var m := StandardMaterial3D.new()
		m.albedo_color = Color(str(c))
		m.roughness = 0.85
		_soil_mats.append(m)
	_rock_mat = StandardMaterial3D.new()
	_rock_mat.albedo_color = Color(str(site_def.get("rock", "#9A9486")))
	_rock_mat.roughness = 0.7
	var cols_art: Array = art_def.get("colors", ["#F3E6C4", "#6B4A2E"])
	_peek_mat = StandardMaterial3D.new()
	_peek_mat.albedo_color = Color(str(soil[0])).lerp(Color(str(cols_art[0])), 0.55)
	_peek_mat.roughness = 0.6
	_peek_mat.emission_enabled = true
	_peek_mat.emission = Color(str(cols_art[0])) * 0.15
	# pit floor
	var floor_mesh := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(_cols(), 0.1, _rows())
	floor_mesh.mesh = bm
	var fm := StandardMaterial3D.new()
	fm.albedo_color = Color(str(soil[soil.size() - 1])).darkened(0.25)
	floor_mesh.material_override = fm
	floor_mesh.position = Vector3(0, floor_y() - 0.05, 0)
	_board.add_child(floor_mesh)
	_place_artifact()
	var layers: Array = site.get("layers", [])
	for i in layers.size():
		var x := i % _cols()
		var y := i / _cols()
		var stack: Array = []
		var rock := DigLogic.is_rock(site, i)
		for k in int(layers[i]):
			var b: Node3D = _scene("res://art3d/digsite/%s.glb" % ("rock_block" if rock else "soil_block")).instantiate()
			_board.add_child(b)
			b.position = cell_center(x, y, floor_y() + LAYER_H * k)
			_paint_block(b, rock, k)
			stack.append(b)
		_blocks[i] = stack
		var finds: Dictionary = site.get("finds", {})
		if finds.has(str(i)) and not bool(finds[str(i)].get("taken", false)):
			var kind := str(finds[str(i)]["kind"])
			var piece: String = {"coins": "coin_find", "gems": "gem_find", "crystals": "crystal_find"}.get(kind, "coin_find")
			var f: Node3D = _scene("res://art3d/digsite/%s.glb" % piece).instantiate()
			_board.add_child(f)
			f.position = cell_center(x, y, floor_y())
			f.scale = Vector3.ONE * 1.3
			_finds[i] = f
		if i in (site.get("flags", []) as Array) and int(layers[i]) > 0:
			var fl: Node3D = _scene("res://art3d/digsite/survey_flag.glb").instantiate()
			_board.add_child(fl)
			fl.position = cell_center(x, y, floor_y() + LAYER_H * int(layers[i])) + Vector3(0.28, 0, -0.28)
			_flags[i] = fl
		_refresh_peek(i)

func _paint_block(b: Node3D, rock: bool, k: int) -> void:
	var m: Material = _rock_mat if rock else _soil_mats[clampi(_soil_mats.size() - 1 - k, 0, _soil_mats.size() - 1)]
	for node in b.find_children("*", "MeshInstance3D", true, false) + ([b] if b is MeshInstance3D else []):
		var mi := node as MeshInstance3D
		for s in mi.mesh.get_surface_count():
			var src := mi.mesh.surface_get_material(s)
			if src != null and src.resource_name == "main":
				mi.set_surface_override_material(s, m)

func _place_artifact() -> void:
	var shape := str(art_def.get("shape", "rock"))
	var path := "res://art3d/artifacts/%s.glb" % shape
	if not ResourceLoader.exists(path):
		path = "res://art3d/artifacts/rock.glb"
	_artifact = _scene(path).instantiate()
	_board.add_child(_artifact)
	var cells: Array = site.get("art_cells", [])
	var mn := Vector2(1e9, 1e9)
	var mx := Vector2(-1e9, -1e9)
	for c in cells:
		var v := Vector2(int(c) % _cols(), int(c) / _cols())
		mn = mn.min(v)
		mx = mx.max(v)
	var size := mx - mn + Vector2.ONE
	var center := (mn + mx) * 0.5
	_artifact.position = Vector3(center.x - _cols() * 0.5 + 0.5, floor_y(), center.y - _rows() * 0.5 + 0.5)
	var s := minf(size.x, size.y)
	_artifact.scale = Vector3(size.x, s, size.y) * 0.92
	var cols: Array = art_def.get("colors", ["#F3E6C4", "#6B4A2E"])
	var main := StandardMaterial3D.new()
	main.albedo_color = Color(str(cols[0]))
	main.roughness = 0.35
	var accent := StandardMaterial3D.new()
	accent.albedo_color = Color(str(cols[1] if cols.size() > 1 else cols[0]))
	accent.roughness = 0.45
	for node in _artifact.find_children("*", "MeshInstance3D", true, false) + ([_artifact] if _artifact is MeshInstance3D else []):
		var mi := node as MeshInstance3D
		for i in mi.mesh.get_surface_count():
			var src := mi.mesh.surface_get_material(i)
			if src == null:
				continue
			if src.resource_name == "main":
				mi.set_surface_override_material(i, main)
			elif src.resource_name == "accent":
				mi.set_surface_override_material(i, accent)
	if int(site.get("damage", 0)) > 0:
		_crack_look()

func _crack_look() -> void:
	for node in _artifact.find_children("*", "MeshInstance3D", true, false) + ([_artifact] if _artifact is MeshInstance3D else []):
		var mi := node as MeshInstance3D
		for i in mi.mesh.get_surface_count():
			var m := mi.get_surface_override_material(i) as StandardMaterial3D
			if m != null:
				m.albedo_color = m.albedo_color.darkened(0.08 * float(site.get("damage", 0)))

## A top block one layer above the artifact takes on its colour: bone peeking
## through the dirt, the cue to switch to the brush.
func _refresh_peek(i: int) -> void:
	var stack: Array = _blocks.get(i, [])
	if stack.is_empty():
		return
	var top := stack.back() as Node3D
	if DigLogic.peeks(site, i):
		for node in top.find_children("*", "MeshInstance3D", true, false) + ([top] if top is MeshInstance3D else []):
			var mi := node as MeshInstance3D
			for s in mi.mesh.get_surface_count():
				mi.set_surface_override_material(s, _peek_mat)

# ------------------------------------------------------------------ feedback
## Animate what a swing did (the site dict is already updated by DigLogic).
func apply_result(x: int, y: int, res: Dictionary) -> void:
	var i := y * _cols() + x
	var stack: Array = _blocks.get(i, [])
	var removed := int(res.get("removed", 0))
	for _k in removed:
		if stack.is_empty():
			break
		var b := stack.pop_back() as Node3D
		var tw := b.create_tween()
		tw.set_parallel(true)
		tw.tween_property(b, "position:y", b.position.y + 0.6, 0.22).set_ease(Tween.EASE_OUT)
		tw.tween_property(b, "scale", Vector3.ONE * 0.05, 0.22)
		tw.chain().tween_callback(b.queue_free)
	_dust(cell_center(x, y, floor_y() + LAYER_H * stack.size() + 0.1))
	if _flags.has(i):
		(_flags[i] as Node3D).queue_free()
		_flags.erase(i)
	_refresh_peek(i)
	if bool(res.get("cracked", false)):
		_pop(cell_center(x, y, 0.4), "CRACK!", Color("#FF6B5A"))
		_crack_look()
	var find: Dictionary = res.get("find", {})
	if not find.is_empty() and _finds.has(i):
		var f := _finds[i] as Node3D
		_finds.erase(i)
		var tw2 := f.create_tween()
		tw2.tween_property(f, "position:y", 1.2, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tw2.parallel().tween_property(f, "rotation:y", TAU, 0.6)
		tw2.tween_property(f, "scale", Vector3.ONE * 0.05, 0.25)
		tw2.tween_callback(f.queue_free)
		var label := {"coins": "+Cash!", "gems": tr("+%d Gems") % int(find.get("amount", 1)), "crystals": tr("+%d Energy") % int(find.get("amount", 3))}
		_pop(cell_center(x, y, 1.0), str(label.get(str(find["kind"]), "")), Color("#FFE680"))
	if bool(res.get("complete", false)):
		celebrate()

## The artifact lifts out of the pit and spins, with a burst of confetti.
func celebrate() -> void:
	if _artifact == null:
		return
	var tw := _artifact.create_tween()
	tw.tween_property(_artifact, "position:y", 1.2, 0.8).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(_artifact, "rotation:y", TAU, 2.4).as_relative()
	_confetti(_artifact.position + Vector3(0, 1.4, 0))

func _dust(at: Vector3) -> void:
	var p := CPUParticles3D.new()
	p.one_shot = true
	p.amount = 14
	p.lifetime = 0.6
	p.explosiveness = 0.9
	p.direction = Vector3.UP
	p.spread = 60.0
	p.initial_velocity_min = 1.5
	p.initial_velocity_max = 3.0
	p.gravity = Vector3(0, -6, 0)
	p.scale_amount_min = 0.5
	p.scale_amount_max = 1.2
	var s := SphereMesh.new()
	s.radius = 0.06
	s.height = 0.12
	s.radial_segments = 6
	s.rings = 3
	var m := StandardMaterial3D.new()
	m.albedo_color = (_soil_mats[0] as StandardMaterial3D).albedo_color if not _soil_mats.is_empty() else Color("#C8A06A")
	s.material = m
	p.mesh = s
	add_child(p)
	p.position = at
	p.emitting = true
	get_tree().create_timer(1.2).timeout.connect(p.queue_free)

func _confetti(at: Vector3) -> void:
	var p := CPUParticles3D.new()
	p.one_shot = true
	p.amount = 90
	p.lifetime = 1.8
	p.explosiveness = 0.95
	p.direction = Vector3.UP
	p.spread = 70.0
	p.initial_velocity_min = 4.0
	p.initial_velocity_max = 7.0
	p.gravity = Vector3(0, -7, 0)
	p.angular_velocity_min = -360.0
	p.angular_velocity_max = 360.0
	var q := QuadMesh.new()
	q.size = Vector2(0.12, 0.08)
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	q.material = m
	p.mesh = q
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.33, 0.66, 1.0])
	g.colors = PackedColorArray([Color("#FF5A5F"), Color("#FFD34D"), Color("#4FB86A"), Color("#3A78D8")])
	p.color_initial_ramp = g
	add_child(p)
	p.position = at
	p.emitting = true
	get_tree().create_timer(2.5).timeout.connect(p.queue_free)

func _pop(at: Vector3, text: String, color: Color) -> void:
	var l := Label3D.new()
	l.text = text
	l.font = POP_FONT
	l.font_size = 56
	l.outline_size = 14
	l.modulate = color
	l.outline_modulate = Color("#3A2A10")
	l.pixel_size = 0.006
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.no_depth_test = true
	add_child(l)
	l.position = at
	var tw := l.create_tween()
	tw.tween_property(l, "position:y", at.y + 1.0, 0.9).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(l, "modulate:a", 0.0, 0.4).set_delay(0.5)
	tw.tween_callback(l.queue_free)

# ------------------------------------------------------------------ scene
func _environment() -> void:
	ToyLook.watch(self)
	var we := WorldEnvironment.new()
	we.environment = ToyLook.environment()
	add_child(we)
	add_child(ToyLook.sun(Vector3(-58.0, -28.0, 0.0), 40.0))

func _camera() -> void:
	camera = Camera3D.new()
	camera.keep_aspect = Camera3D.KEEP_WIDTH
	camera.fov = 30.0
	var pitch := deg_to_rad(62.0)
	var dist := 21.0
	camera.position = Vector3(0, sin(pitch) * dist, cos(pitch) * dist + 0.4)
	camera.rotation = Vector3(-pitch, 0, 0)
	add_child(camera)
	camera.current = true

func _surroundings() -> void:
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color("#8CCB5E")
	gm.roughness = 0.9
	# The pit is cut out of the lawn, so the lawn is four slabs framing the hole.
	for r in [Rect2(-20, -20, 40, 15.5), Rect2(-20, 4.5, 40, 15.5), Rect2(-20, -4.5, 16.5, 9), Rect2(3.5, -4.5, 16.5, 9)]:
		var slab := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(r.size.x, 0.1, r.size.y)
		slab.mesh = bm
		slab.material_override = gm
		slab.position = Vector3(r.get_center().x, -0.05, r.get_center().y)
		add_child(slab)
	var frame: Node3D = _scene("res://art3d/digsite/pit_frame.glb").instantiate()
	add_child(frame)
	var camp: Node3D = _scene("res://art3d/digsite/camp.glb").instantiate()
	add_child(camp)
	camp.position = Vector3(-5.6, 0.0, -3.4)
	camp.rotation.y = 0.5
	var r := RandomNumberGenerator.new()
	r.seed = 5
	for i in 10:
		var t: Node3D = _scene("res://art3d/outdoor/%s.glb" % ("tree" if i % 3 else "bush")).instantiate()
		add_child(t)
		var side := -1.0 if i % 2 == 0 else 1.0
		t.position = Vector3(side * r.randf_range(4.6, 6.5), 0.0, r.randf_range(-7.0, 6.0))
		t.rotation.y = r.randf() * TAU
