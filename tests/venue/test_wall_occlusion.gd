extends SceneTree
const WallOcclusion := preload("res://scenes/venue/floor/wall_occlusion.gd")
const Iso := preload("res://scenes/venue/floor/iso.gd")

class FakeTheme extends RefCounted:
	var id := "cloudrest"
	var walls: Array = []
	func level_at(point: Vector2) -> int:
		return 2 if point.x > 8.0 else 0
	func lift_at(point: Vector2) -> float:
		return Iso.level_lift(level_at(point))

var failures := 0
func check(ok: bool, label: String) -> void:
	if not ok:
		failures += 1
		printerr("FAIL: ", label)

func _initialize() -> void:
	var canvas := Node2D.new()
	root.add_child(canvas)
	var theme := FakeTheme.new()
	theme.walls = [
		{"at":Vector2(1,2),"len":1.5,"axis":"x","level":0,"h":30,"col":Color.WHITE,"occludes":true},
		{"at":Vector2(4,5),"len":1.5,"axis":"y","level":0,"h":30,"col":Color.WHITE,"occludes":true},
		{"at":Vector2(9,3),"len":1.5,"axis":"x","level":1,"h":30,"col":Color.WHITE,"occludes":true},
		{"at":Vector2(0,0),"len":8.0,"axis":"x","level":0,"h":30,"col":Color.WHITE},
	]
	var nodes: Array[Node2D] = []
	WallOcclusion.rebuild(canvas, theme, nodes)
	check(nodes.size() == 6 and canvas.get_child_count() == 6,
		"only opted-in x/y walls split into bounded sections")
	check(is_equal_approx(nodes[0].position.y, Iso.to_screen(Vector2(1.375,2)).y),
		"ground x-axis section uses projected depth")
	check(is_equal_approx(nodes[2].position.y, Iso.to_screen(Vector2(4,5.375)).y),
		"ground y-axis section uses projected depth")
	check(nodes[4].z_index == Iso.LEVEL_Z and is_equal_approx(nodes[4].position.y,
		Iso.to_screen(Vector2(9.375,3)).y + Iso.level_lift(1)),
		"authored raised level controls both lift and z band")
	WallOcclusion.clear(nodes)
	check(nodes.is_empty() and canvas.get_child_count() == 0,
		"retheme clear detaches old geometry immediately")
	print("Wall occlusion failures: ", failures)
	quit(1 if failures else 0)
