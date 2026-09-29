extends SceneTree
## Renders one piece of furniture in every facing it claims to have.
##
## `axis` plus `flip` is meant to give four orientations. That is a claim about
## pixels, and the mirror maths behind it is the kind of thing that looks right in
## the source and comes out with the backrest through the seat. One sheet settles
## it.
##
##   godot --path . -s tools/facing_shot.gd -- out=/abs/facings.png kind=bench

const Exhibits := preload("res://scenes/venue/floor/exhibits.gd")
const Iso := preload("res://scenes/venue/floor/iso.gd")

const DESIGN := Vector2i(720, 520)
const SCALE := 2.4

var _vp: SubViewport
var _out := "user://facings.png"
var _kind := "bench"
var _mode := "facing"
var _frames := 0

func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := (a as String).split("=", true, 1)
		if kv.size() == 2:
			if kv[0] == "out":
				_out = kv[1]
			elif kv[0] == "kind":
				_kind = kv[1]
			elif kv[0] == "mode":
				_mode = kv[1]

	_vp = SubViewport.new()
	_vp.size = DESIGN
	_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(_vp)

	var bg := ColorRect.new()
	bg.color = Color("#EFF0F5")
	bg.size = Vector2(DESIGN)
	_vp.add_child(bg)

	var combos: Array = []
	if _mode == "mirror":
		combos = [
			{"label": "original"},
			{"mirror": "d", "label": "mirror d (left-right)"},
			{"mirror": "y", "label": "mirror y (east-west)"},
			{"mirror": "x", "label": "mirror x (north-south)"},
		]
	elif _mode == "rot":
		for d in [0, 45, 90, 135, 180, 225, 270, 315]:
			combos.append({"rot": float(d), "label": "%d deg" % d})
	else:
		combos = [
			{"axis": "x", "flip": false, "label": "axis x"},
			{"axis": "x", "flip": true, "label": "axis x, flipped"},
			{"axis": "y", "flip": false, "label": "axis y"},
			{"axis": "y", "flip": true, "label": "axis y, flipped"},
		]
	for i in combos.size():
		var holder := Node2D.new()
		var cols: int = 4
		holder.position = Vector2(96.0 + float(i % cols) * 176.0,
			150.0 + float(i / cols) * 250.0)
		holder.scale = Vector2(SCALE, SCALE)
		_vp.add_child(holder)
		var painter := _One.new()
		# Painters work in GRID space, so grid (0,0) lands at Iso.ORIGIN rather
		# than at this holder. Pull it back so the piece sits where it is placed.
		painter.position = -Iso.to_screen(Vector2.ZERO)
		painter.spec = {
			"kind": _kind, "at": [0.0, 0.0], "len": 1.6, "size": [1.6, 0.5],
			"axis": str(combos[i].get("axis", "x")),
			"flip": bool(combos[i].get("flip", false)),
			"rot": float(combos[i].get("rot", 0.0)),
			"mirror": str(combos[i].get("mirror", "")),
		}
		holder.add_child(painter)
		var lab := Label.new()
		lab.text = str(combos[i]["label"])
		lab.position = Vector2(holder.position.x - 78.0, holder.position.y + 46.0)
		lab.size = Vector2(160.0, 40.0)
		lab.add_theme_color_override("font_color", Color("#1B1F3B"))
		_vp.add_child(lab)

class _One extends Node2D:
	var spec: Dictionary = {}
	func _draw() -> void:
		var Ex := load("res://scenes/venue/floor/exhibits.gd")
		var call: Callable = Ex.painter(str(spec.get("kind", "bench")), spec)
		if call.is_valid():
			call.call(self)

func _process(_dt: float) -> bool:
	_frames += 1
	if _frames < 8:
		return false
	var img: Image = _vp.get_texture().get_image()
	var target := _out
	if not (target.begins_with("res://") or target.begins_with("user://")) \
			and not target.begins_with("/"):
		target = ProjectSettings.globalize_path("res://").path_join(target)
	print("FACINGS ", target, " err=", img.save_png(target))
	quit(0)
	return true
