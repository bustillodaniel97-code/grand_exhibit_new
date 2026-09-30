extends RefCounted
## The diorama's light and surfaces, shared by the museum, the Pop-Up Café and
## the Dig Site so all three read as one set.
##
## Matte clay rather than glossy plastic: a bright, warm, even fill, a gentle
## sun with wide soft shadows, slightly muted colour, and almost no specular.
## The art kit exported every Principled material at roughness 0.4, which under
## a single sun put a hot highlight on every dome, table and visitor; matte()
## flattens them at load time so the look doesn't hang on re-exporting models.
## Plain RefCounted with statics; callers preload this file.

const BACKDROP := Color("#e9e4db")    # studio backdrop behind the diorama
const AMBIENT := Color("#eef0ee")     # warm-neutral fill light
const AMBIENT_ENERGY := 0.4
const SUN_COLOR := Color("#fff3e3")
const SUN_ENERGY := 0.6
const SHADOW_BLUR := 2.4
const SHADOW_OPACITY := 0.9
const SATURATION := 0.78
const CONTRAST := 1.0
const GLOW := 0.1                     # emissive lamps only, no bloom on paint

const ROUGH_MIN := 0.88
const SPECULAR := 0.18
const METAL_MAX := 0.1
## Brass and gilt keep a little sheen so gold still reads as gold.
const GILT_METAL := 0.35
const GILT_ROUGH := 0.55

const _DONE := "toy_matte"

static func environment(backdrop: Color = BACKDROP) -> Environment:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = backdrop
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = AMBIENT
	env.ambient_light_energy = AMBIENT_ENERGY
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR  # Filmic bleaches toy colours to white in Compatibility
	env.tonemap_exposure = 1.0
	env.glow_enabled = true
	env.glow_intensity = GLOW
	env.glow_hdr_threshold = 1.4
	env.adjustment_enabled = true
	env.adjustment_saturation = SATURATION
	env.adjustment_contrast = CONTRAST
	return env

static func sun(rotation_deg: Vector3, max_distance: float) -> DirectionalLight3D:
	var s := DirectionalLight3D.new()
	s.rotation_degrees = rotation_deg
	s.light_energy = SUN_ENERGY
	s.light_color = SUN_COLOR
	s.light_specular = 0.3
	s.shadow_enabled = true
	s.shadow_blur = SHADOW_BLUR
	s.shadow_opacity = SHADOW_OPACITY
	s.directional_shadow_max_distance = max_distance
	return s

## Matte one material in place. Materials from the art kit are shared by every
## instance, so each is only touched once.
static func matte_material(m: Material) -> void:
	var bm := m as BaseMaterial3D
	if bm == null or bm.has_meta(_DONE):
		return
	bm.set_meta(_DONE, true)
	if bm.shading_mode == BaseMaterial3D.SHADING_MODE_UNSHADED:
		return
	if bm.metallic > 0.5:
		bm.metallic = GILT_METAL
		bm.roughness = maxf(bm.roughness, GILT_ROUGH)
	else:
		bm.metallic = minf(bm.metallic, METAL_MAX)
		bm.roughness = maxf(bm.roughness, ROUGH_MIN)
	bm.metallic_specular = minf(bm.metallic_specular, SPECULAR)
	bm.diffuse_mode = BaseMaterial3D.DIFFUSE_LAMBERT_WRAP

## A gilt material (gold dome, brass rims) with the set's soft sheen.
static func gilt(color: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.metallic = GILT_METAL
	m.roughness = GILT_ROUGH
	m.metallic_specular = SPECULAR
	m.diffuse_mode = BaseMaterial3D.DIFFUSE_LAMBERT_WRAP
	m.set_meta(_DONE, true)
	return m

static func matte_node(n: Node) -> void:
	var gi := n as GeometryInstance3D
	if gi == null:
		return
	if gi.material_override != null:
		matte_material(gi.material_override)
	var mi := gi as MeshInstance3D
	if mi == null or mi.mesh == null:
		return
	for i in mi.mesh.get_surface_count():
		var own := mi.get_surface_override_material(i)
		if own != null:
			matte_material(own)
		var src := mi.mesh.surface_get_material(i)
		if src != null:
			matte_material(src)

static func matte(root: Node) -> void:
	matte_node(root)
	for c in root.get_children():
		matte(c)

## Keeps a world matte as it grows: every mesh that later enters under `world`
## (visitors, bought decor, renovated floors) is flattened on arrival, and the
## whole tree is swept once more after the first frame for materials assigned
## after their node entered.
static func watch(world: Node) -> void:
	var w := Watcher.new()
	w.name = "MatteWatcher"
	w.look = load("res://scripts/render/toy_look.gd")
	world.add_child(w)

class Watcher extends Node:
	var look: GDScript

	func _enter_tree() -> void:
		get_tree().node_added.connect(_on_added)

	func _exit_tree() -> void:
		if get_tree().node_added.is_connected(_on_added):
			get_tree().node_added.disconnect(_on_added)

	func _ready() -> void:
		_sweep.call_deferred()

	func _sweep() -> void:
		var world := get_parent()
		if world != null:
			look.call("matte", world)

	func _on_added(n: Node) -> void:
		if n is GeometryInstance3D and get_parent() != null and get_parent().is_ancestor_of(n):
			look.call("matte_node", n)
