extends SceneTree
## Renders the cast's poses side by side, large, against a flat backdrop.
##
## Exists because "the seated pose is wired and six people entered it" is not the
## same claim as "sitting looks like sitting", and a live floor is a bad place to
## check: the first two attempts to eyeball it caught the vault's uniformed staff
## stacked over the lounge by the storey lift, not sitters at all. One figure per
## pose, no simulation, no ambiguity.
##
##   godot --path . -s tools/pose_shot.gd -- out=/abs/poses.png
##
## Dev tool. Lives outside tests/ so the suite glob never picks it up.

const Character := preload("res://scenes/venue/floor/character.gd")
const Exhibits := preload("res://scenes/venue/floor/exhibits.gd")
const Iso := preload("res://scenes/venue/floor/iso.gd")

const DESIGN := Vector2i(640, 320)
const SCALE := 3.0

var _vp: SubViewport
var _out: String = "user://poses.png"
var _frames: int = 0

func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := (a as String).split("=", true, 1)
		if kv.size() == 2 and kv[0] == "out":
			_out = kv[1]

	_vp = SubViewport.new()
	_vp.size = DESIGN
	_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_vp.transparent_bg = false
	root.add_child(_vp)

	var bg := ColorRect.new()
	bg.color = Color("#EFF0F5")
	bg.size = Vector2(DESIGN)
	_vp.add_child(bg)

	# One holder per pose, scaled up so the legs are unambiguous.
	var poses: Array = [
		{"label": "standing", "seated": false, "bench": false},
		{"label": "walking", "seated": false, "bench": false, "walking": true},
		{"label": "seated (no bench)", "seated": true, "bench": false},
		{"label": "seated on bench", "seated": true, "bench": true},
	]
	for i in poses.size():
		var p: Dictionary = poses[i]
		var holder := Node2D.new()
		holder.position = Vector2(78.0 + float(i) * 155.0, 230.0)
		holder.scale = Vector2(SCALE, SCALE)
		_vp.add_child(holder)
		if bool(p.get("bench", false)):
			# The bench is drawn in grid space, so give it its own item anchored so
			# the seat lands under the figure.
			var furn := Node2D.new()
			furn.position = -Iso.to_screen(Vector2(1.0, 1.0))
			holder.add_child(furn)
			var painter := _FurnPainter.new()
			furn.add_child(painter)
		var c: Character = Character.new()
		c.set_look_slot(3 + i * 5)
		c.seated = bool(p.get("seated", false))
		c.walking = bool(p.get("walking", false))
		holder.add_child(c)
		var lab := Label.new()
		lab.text = str(p["label"])
		lab.position = Vector2(holder.position.x - 70.0, 258.0)
		lab.size = Vector2(150.0, 40.0)
		lab.add_theme_color_override("font_color", Color("#1B1F3B"))
		lab.autowrap_mode = TextServer.AUTOWRAP_WORD
		_vp.add_child(lab)

class _FurnPainter extends Node2D:
	func _draw() -> void:
		var Ex := load("res://scenes/venue/floor/exhibits.gd")
		var call: Callable = Ex.painter("bench", {
			"at": [0.4, 1.0], "len": 1.6,
		})
		if call.is_valid():
			call.call(self)

func _process(_dt: float) -> bool:
	_frames += 1
	if _frames < 8:
		return false
	var img: Image = _vp.get_texture().get_image()
	var target: String = _out
	if not (target.begins_with("res://") or target.begins_with("user://")) \
			and not target.begins_with("/"):
		target = ProjectSettings.globalize_path("res://").path_join(target)
	print("POSE ", target, " err=", img.save_png(target))
	quit(0)
	return true
