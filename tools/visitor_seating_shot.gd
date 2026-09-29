extends "res://tools/shot.gd"
## Deliberately staged seat-placement check on the actual authored benches.
func _seed() -> void:
 super._seed()
 var floor_node: Node = _find_floor(root)
 if floor_node == null:return
 floor_node.time_scale = 0.0
 var slots := [0,3,6,5]
 for i in range(mini(slots.size(),floor_node._seats.size())):
  var c: Node2D = load("res://scenes/venue/floor/character.gd").new()
  c.set_look_slot(slots[i]);c.seated = true;c.walking = false
  floor_node._canvas.add_child(c)
  floor_node._place(c,floor_node._seats[i])
  c.queue_redraw()
