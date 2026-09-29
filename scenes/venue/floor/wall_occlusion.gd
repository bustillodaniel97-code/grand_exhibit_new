extends RefCounted
## Opaque interior walls that must interleave with the cast. Walls normally stay
## in the storey ground batch; authored `occludes` walls opt into short Y-sorted
## sections so actors can pass behind and in front of the same run.
const Iso := preload("res://scenes/venue/floor/iso.gd")
const Exhibits := preload("res://scenes/venue/floor/exhibits.gd")
const MuseumArchitecture := preload("res://scenes/venue/floor/museum_architecture.gd")
const MAX_SECTION := 0.75

static func clear(nodes: Array[Node2D]) -> void:
	for node in nodes:
		if is_instance_valid(node):
			var parent := node.get_parent()
			if parent != null:
				parent.remove_child(node)
			node.queue_free()
	nodes.clear()

static func rebuild(canvas: Node2D, theme: RefCounted, nodes: Array[Node2D]) -> void:
	clear(nodes)
	for entry in theme.walls:
		var wall: Dictionary = entry as Dictionary
		if not bool(wall.get("occludes", false)):
			continue
		var at: Vector2 = Exhibits.v2(wall.get("at"))
		var length: float = Exhibits.f(wall.get("len"), 1.0)
		var axis: String = str(wall.get("axis", "x"))
		var along := Vector2.RIGHT if axis == "x" else Vector2.DOWN
		var sections := maxi(1, ceili(length / MAX_SECTION))
		var section_length := length / float(sections)
		var wall_level := int(wall.get("level", theme.level_at(at + Vector2(0.25, 0.25))))
		for index in sections:
			var section_at := at + along * section_length * float(index)
			var anchor := section_at + along * section_length * 0.5
			var screen_anchor := Iso.to_screen(anchor)
			var node := Node2D.new()
			node.name = "OccludingWall"
			node.position = screen_anchor + Vector2(0.0, Iso.level_lift(wall_level))
			node.z_index = wall_level * Iso.LEVEL_Z
			canvas.add_child(node)
			node.draw.connect(func() -> void:
				node.draw_set_transform(-screen_anchor)
				Iso.wall(node, section_at, section_length, axis,
					Exhibits.c(wall.get("col"), Color.WHITE), Exhibits.f(wall.get("h"), Iso.WALL_H))
				MuseumArchitecture.wall_details(node, theme.id, section_at,
					section_length, axis, Exhibits.f(wall.get("h"), Iso.WALL_H), false))
			nodes.append(node)
