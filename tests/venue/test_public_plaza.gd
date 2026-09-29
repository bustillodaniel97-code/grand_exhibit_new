extends "res://tests/venue/test_nav_reachability.gd"
## Real arrivals, resting, wildlife and departure on every authored exterior.
const Props := preload("res://scenes/venue/floor/museum_props.gd")
func _check_all_venues() -> void:
 _floor.set_process(false)
 var previous: Array = []
 for vid in DL.venue_order():
  root.get_node("GameState").current_venue = str(vid)
  _floor.retheme(str(vid))
  for node in previous:check(not is_instance_valid(node) or node.is_queued_for_deletion(),"previous plaza actor retired")
  var plaza = _floor._plaza
  # Isolate local seating and obstacle tests; cross-district lifecycle is
  # exercised with real transit in test_public_city_journeys.gd.
  plaza.journeys=null
  check(Props._textures.has("res://art/environment/%s-bench-150-x-0.png" % vid),str(vid)+" public benches use the authored furniture kit without fallback art")
  var flock: Node2D = plaza.flocks[0]
  check(plaza.flocks.size()==1 and flock.is_inside_tree(),str(vid)+" wildlife exists before its feeding visitor arrives")
  check(plaza.fixtures.size()==5,str(vid)+" all authored exterior fixtures fit outside rooms and door lanes")
  for fixture in plaza.fixtures:
   for existing in plaza.existing_fixtures:
    check(not fixture.rect.intersects(existing),str(vid)+" public furniture clears legacy venue decorations")
   for other in plaza.fixtures:
    if fixture==other:continue
    check(not fixture.rect.intersects(other.rect),str(vid)+" exterior furniture does not overlap")
  for activity in plaza.activities:
   for start in plaza.spawn_points:
    var path: Array = plaza.route(start,activity.at)
    check(not path.is_empty(),str(vid)+" "+activity.kind+" reachable from both sidewalk approaches")
  for side in [false,true]:
   var arrival: Array = _floor._city.near_sidewalk_route(side)
   for leg in range(1,arrival.size()):
    check(plaza._line_clear(arrival[leg-1],arrival[leg]),str(vid)+" museum arrivals clear curbside trees, lights, bollards and plaza furniture")
  var lobby: Rect2 = _floor._theme.role("lobby").rect
  for outside in [Vector2(_floor._door_g.x,lobby.end.y+.65),_floor._exit_wall_g+Vector2(0,.65)]:
   check(not plaza.route(outside,plaza.spawn_points[0]).is_empty(),str(vid)+" museum door connects to plaza and street")
  var city = _floor._city
  check(is_zero_approx(city.surface_drop(city.ramp_top())),str(vid)+" ramp meets forecourt height")
  check(is_equal_approx(city.surface_drop(city.ramp_bottom()),city.DROP),str(vid)+" ramp meets sidewalk height")
  # Drive the production exterior update, bounded to the same fixed step used
  # by VenueFloor. The larger circulation audit separately drives the full sim.
  var feeding_frames: Dictionary = {}
  # The dog circuit now reserves the shared bench passage; allow a full
  # sequential activity cycle instead of requiring simultaneous visits.
  for step in 10400:
   plaza.advance(.05)
   check_population(plaza,str(vid))
   for person in plaza.people:
    if person.node._feeding_frame >= 0:feeding_frames[person.node._feeding_frame] = true
  print("PUBLIC_PLAZA ",vid," steps=",plaza.movement_steps," completed=",plaza.completed," invalid=",plaza.invalid_steps," route_failures=",plaza.failed_routes)
  check(plaza.completed.rest>0 and plaza.completed.feed>0 and plaza.completed.dog>0,str(vid)+" guests complete rest, bird feeding and dog walking visits")
  check(plaza.invalid_steps==0,str(vid)+" exterior movement stays clear of walls, supports, furniture and slab edges")
  check(plaza.failed_routes==0,str(vid)+" no failed exterior routes")
  check(feeding_frames.size()==preload("res://scripts/characters/activity_sprites.gd").frame_count(),str(vid)+" natural arrivals perform the entire feeding gesture before departing")
  check(plaza.flocks.size()==1 and plaza.flocks[0]==flock and not flock.is_queued_for_deletion(),str(vid)+" the same flock survives feeding-visitor turnover")
  _after_public_venue(plaza,str(vid))
  previous = plaza.nodes.duplicate()

 # Closing the real departure node must hold the visitor, not count a
 # completed visit or invent a straight-line walk through scenery.
 var plaza = _floor._plaza
 if plaza.people.is_empty():plaza._spawn()
 var stuck: Dictionary = plaza.people[0]
 var before: Vector2 = stuck.pos
 var home_id := Vector2i((stuck.home/plaza.STEP).round())
 plaza.graph.set_point_solid(home_id,true)
 plaza._leave(stuck)
 plaza.advance(.05)
 check(plaza.people.has(stuck) and stuck.pos.is_equal_approx(before) and not stuck.node.walking,"blocked exterior departure holds its guest without a false exit")
 plaza.graph.set_point_solid(home_id,false)

func _after_public_venue(_plaza,_vid: String) -> void:
 pass

func check_population(plaza,vid: String) -> void:
 if plaza.people.size()>plaza.MAX_PEOPLE:
  check(false,vid+" exceeded exterior population cap")
 for p in plaza.people:
  if p.node.identity.get("role")!="visitor" or p.node.identity.get("is_staff",false):
   check(false,vid+" exterior activity spawned a staff identity")
  if is_instance_valid(p.get("companion")) and not plaza.walkable(p.companion_pos):
   check(false,vid+" dog leaves the owner's clear route")
