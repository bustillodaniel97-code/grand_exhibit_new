extends "res://tools/shot.gd"
## Passive diagnostics during normal simulation: no teleporting or forced states.
var next_sample := 5.0
var seen_states: Dictionary = {}
var courtyard_visitors: Dictionary = {}
var resting_visitors: Dictionary = {}
var cafe_visitors: Dictionary = {}
func _process(delta: float) -> bool:
 if _t >= next_sample:
  next_sample += 5.0
  var floor_node := _find_floor(root)
  if floor_node != null:
   var cafe: Dictionary = floor_node._theme.role("promo")
   var cafe_rect: Rect2 = cafe.get("rect",Rect2())
   for visitor in floor_node._visitors:
    seen_states[visitor.state] = true
    var actor_id: int = visitor.node.get_instance_id()
    if visitor.state == "rest":resting_visitors[actor_id] = true
    if str(cafe.get("experience","")) == "cafe" and cafe_rect.has_point(visitor.pos) and visitor.state == "browse":
     cafe_visitors[actor_id] = true
    if floor_node._theme.id == "grand_river" and visitor.pos.x > 7 and visitor.pos.x < 8.4 and visitor.pos.y > 2 and visitor.pos.y < 9:
     courtyard_visitors[actor_id] = true
   print("CIRCULATION t=", snappedf(_t,1), " census=", floor_node.state_census(), " states_seen=", seen_states.keys(), " garden_unique=", courtyard_visitors.size(), " rest_unique=", resting_visitors.size(), " cafe_browse_unique=", cafe_visitors.size())
 return super._process(delta)
