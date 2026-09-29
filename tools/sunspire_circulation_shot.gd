extends "res://tools/circulation_shot.gd"
## Passive route evidence at 5 Hz; does not assign destinations or force arrivals.
var next_route_sample := 0.0
var next_route_report := 5.0
var stair_users: Dictionary = {}
var dial_viewers: Dictionary = {}
func _process(delta: float) -> bool:
 if _t >= next_route_sample:
  next_route_sample += .2
  var floor_node := _find_floor(root)
  if floor_node != null and floor_node._theme.id == "sunspire":
   var stair: Rect2 = floor_node._theme.rect("sun_stair")
   var views: Array = floor_node._browse.get("solar_dial", [])
   for visitor in floor_node._visitors:
    var actor_id: int = visitor.node.get_instance_id()
    if stair.has_point(visitor.pos):stair_users[actor_id] = true
    if visitor.state == "browse":
     for spot in views:
      if visitor.pos.distance_to(spot) < .25 and visitor.target.distance_to(spot) < .01:
       dial_viewers[actor_id] = true
   if _t >= next_route_report:
    next_route_report += 5.0
    print("SUNSPIRE_ROUTES t=", snappedf(_t, 1), " stair_users=", stair_users.size(), " sundial_arrivals=", dial_viewers.size())
 return super._process(delta)
