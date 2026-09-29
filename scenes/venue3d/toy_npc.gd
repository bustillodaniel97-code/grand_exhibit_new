extends Node3D
## One toy chibi (art3d/characters/chibi.glb): a look, an animation state and a
## path follower on the venue's navigation map.
##
## A LOOK is a dictionary of role -> colour ("skin", "hair", "shirt", "pants",
## "shoe", "acc_vest", ...) plus "acc": the accessory meshes to show, and an
## optional "scale". Materials are recoloured by the role NAME the Blender
## script gave them, so the model and this file agree without a lookup table.

signal arrived

const CHIBI := preload("res://art3d/characters/chibi.glb")

var speed := 1.1
var _anim: AnimationPlayer
var _path := PackedVector3Array()
var _next := 0
var _facing := 0.0

## Recoloured materials shared across the whole crowd: role + colour -> material.
static var _tints := {}

func setup(look: Dictionary) -> void:
	var model: Node3D = CHIBI.instantiate()
	add_child(model)
	scale = Vector3.ONE * float(look.get("scale", 1.0))
	_anim = model.find_child("AnimationPlayer", true, false) as AnimationPlayer
	for loop_name in ["walk", "idle"]:
		if _anim and _anim.has_animation(loop_name):
			_anim.get_animation(loop_name).loop_mode = Animation.LOOP_LINEAR
	var shown: Array = look.get("acc", [])
	for node in model.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		if str(mi.name).begins_with("acc_"):
			mi.visible = str(mi.name) in shown
		for s in mi.mesh.get_surface_count():
			var src := mi.mesh.surface_get_material(s)
			if src != null and look.has(src.resource_name):
				mi.set_surface_override_material(s, _tint(src, str(look[src.resource_name])))
	play("idle")

static func _tint(src: Material, hex: String) -> Material:
	var key := "%s|%s" % [src.resource_name, hex]
	if not _tints.has(key):
		var m := src.duplicate() as StandardMaterial3D
		m.albedo_color = Color(hex)
		_tints[key] = m
	return _tints[key]

func play(anim_name: String) -> void:
	if _anim and _anim.has_animation(anim_name) and _anim.current_animation != anim_name:
		_anim.play(anim_name, 0.15)

func face(point: Vector3) -> void:
	var d := point - global_position
	if Vector2(d.x, d.z).length() > 0.01:
		_facing = atan2(d.x, d.z)

## Walk to `target` along the navigation map; emits `arrived` on the last point.
func walk_to(target: Vector3) -> void:
	var map := get_world_3d().navigation_map
	_path = NavigationServer3D.map_get_path(map, global_position, target, true)
	if _path.is_empty():
		_path = PackedVector3Array([target])
	_next = 0
	play("walk")

func is_walking() -> bool:
	return _next < _path.size()

func _process(delta: float) -> void:
	if _next < _path.size():
		var goal := _path[_next]
		var to := goal - global_position
		to.y = 0.0
		var step := speed * delta
		if to.length() <= step:
			global_position = goal
			_next += 1
			if _next >= _path.size():
				play("idle")
				arrived.emit()
		else:
			global_position += to.normalized() * step
			# Follow the nav surface up the entrance steps and plinth.
			global_position.y = move_toward(global_position.y, goal.y, step)
			_facing = atan2(to.x, to.z)
	rotation.y = lerp_angle(rotation.y, _facing, minf(1.0, delta * 10.0))
