extends "res://tools/circulation_shot.gd"
## Observe abrupt elevation changes between adjacent simulation frames.
var prior: Dictionary = {}
var jumps := 0
var next_report := 5.0
var rooms_seen: Dictionary = {}
func _process(delta: float) -> bool:
 var floor_node := _find_floor(root)
 if floor_node != null:
  var alive := {}
  for visitor in floor_node._visitors:
   var actor_id: int = visitor.node.get_instance_id()
   alive[actor_id] = true
   var lift: float = floor_node._theme.lift_at(visitor.pos)
   var old: Dictionary = prior.get(actor_id, {})
   if not old.is_empty() and visitor.pos.distance_to(old.pos) < .25 and absf(lift - old.lift) > 20:
    jumps += 1
    print("ELEVATION_JUMP from=", old.pos, " to=", visitor.pos, " delta=", lift-old.lift, " state=", visitor.state)
   prior[actor_id] = {"pos":visitor.pos, "lift":lift}
   var room: Dictionary = floor_node._theme.room_at(visitor.pos)
   var room_id := str(room.get("id", "outside"))
   if not rooms_seen.has(room_id):rooms_seen[room_id] = {}
   rooms_seen[room_id][actor_id] = true
  for actor_id in prior.keys():
   if not alive.has(actor_id):prior.erase(actor_id)
  if _t >= next_report:
   next_report += 5.0
   var counts := {}
   for room_id in rooms_seen:counts[room_id] = rooms_seen[room_id].size()
   print("ELEVATION_PROBE t=", snappedf(_t,1), " jumps=", jumps, " room_users=", counts)
 return super._process(delta)
