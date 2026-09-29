extends "res://tools/circulation_shot.gd"
## Passive stalled-arrival probe. A crowd in one screenshot is not a stuck route.
var next_probe := 1.0
var previous: Dictionary = {}
var reported: Dictionary = {}
func _process(delta: float) -> bool:
 if _t >= next_probe:
  next_probe += 1.0
  var floor_node := _find_floor(root)
  if floor_node != null:
   var alive: Dictionary = {}
   for visitor in floor_node._visitors:
    var actor_id: int = visitor.node.get_instance_id()
    alive[actor_id] = true
    var old: Dictionary = previous.get(actor_id, {})
    var still := 0
    if visitor.state == "to_queue" and old.get("state", "") == "to_queue" and visitor.pos.distance_to(old.get("pos", visitor.pos)) < .08:
     still = int(old.get("still", 0)) + 1
    previous[actor_id] = {"pos":visitor.pos, "state":visitor.state, "still":still}
    if still >= 8 and not reported.has(actor_id):
     reported[actor_id] = true
     print("STALLED_ARRIVAL t=", snappedf(_t, 1), " position=", visitor.pos, " target=", visitor.target, " path=", visitor.path, " window=", visitor.window)
   for actor_id in previous.keys():
    if not alive.has(actor_id):previous.erase(actor_id)
   if int(next_probe) % 10 == 0:
    print("ARRIVAL_PROBE t=", snappedf(_t, 1), " stalled_arrivals_seen=", reported.size())
 return super._process(delta)
