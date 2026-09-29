extends SceneTree
const Character=preload("res://scenes/venue/floor/character.gd")
var failures:=0
var floor_node: Node
var VF: GDScript
func check(ok: bool,label: String) -> void:
 if not ok:failures+=1;printerr("FAIL: ",label)
func guest(plan: Dictionary):
 var v=VF.Visitor.new();v.node=Character.new();v.node.set_look_slot(3)
 floor_node._canvas.add_child(v.node);v.node.set_process(false)
 v.pos=plan.entry;v.target=v.pos;v.speed=1.2;v.state="exit";v.city_plan=plan
 floor_node._place(v.node,v.pos);return v
func _initialize() -> void:call_deferred("run")
func run() -> void:
 if OS.get_environment("GRAND_EXHIBIT_TEST_RUN")!="1":quit(2);return
 seed(20260918)
 root.get_node("SaveSystem").set_process(false)
 var gs=root.get_node("GameState");gs.reset_to_new_game();gs.ready_flag=true
 VF=load("res://scenes/venue/floor/venue_floor.gd")
 floor_node=VF.new();floor_node.size=Vector2(720,760);root.add_child(floor_node);floor_node.set_process(false)
 for vid in root.get_node("DataLoader").venue_order():
  gs.current_venue=vid;floor_node.retheme(vid)
  var journeys=floor_node._journeys;var city=floor_node._city
  for i in 16:
   var plan: Dictionary=journeys.plan(null);var v=guest(plan)
   check(journeys.accept(v),vid+" retains departing guest")
  var routes: Array=[]
  for business in journeys.businesses:routes.append(business.path)
  for path in routes:
   for j in range(path.size()-1):
    var a: Vector2=path[j];var b: Vector2=path[j+1]
    for sample in range(int(a.distance_to(b)/.10)+1):
     var at:=a.lerp(b,float(sample)/maxf(1,ceilf(a.distance_to(b)/.10)))
     for building in city.district.design.buildings:
      var r:=Rect2(building.rect[0],building.rect[1],building.rect[2],building.rect[3])
      var world:=Rect2(city.map_point(r.position),city.map_point(r.end)-city.map_point(r.position))
      check(not world.has_point(at),vid+" business approach avoids buildings")
     for row in city.district.design.roads:
      var r:=Rect2(row[0],row[1],row[2],row[3])
      var world:=Rect2(city.map_point(r.position),city.map_point(r.end)-city.map_point(r.position))
      check(not world.has_point(at),vid+" business approach stays off roads")
     for feature in city.district.design.features:
      var r:=Rect2(feature.rect[0],feature.rect[1],feature.rect[2],feature.rect[3])
      var world:=Rect2(city.map_point(r.position),city.map_point(r.end)-city.map_point(r.position))
      check(not world.has_point(at),vid+" business approach avoids water and features")
  # A real museum exit must retain its actor through the existing indoor
  # egress and public handoff, not just work when placed at a bus stop.
  var departing=guest({"entry":floor_node._exit_door_g})
  var identity=departing.node.get_instance_id()
  floor_node._begin_exit(departing);floor_node._visitors.append(departing)
  var handed_off:=false
  for tick in 20000:
   city.advance(.05,floor_node._pedestrian_crossing());floor_node._update_visitors(.05);journeys.advance(.05)
   for p in journeys.people:
    if p.v==departing:
     handed_off=true
     check(p.v.node.get_instance_id()==identity,vid+" museum departure keeps the same character")
   for p in journeys.people:
    if p.state=="boarding":check(not city.transit.vehicle(p.plan.kind).is_empty(),vid+" vehicle remains present throughout boarding")
   if journeys.people.is_empty() and floor_node._visitors.is_empty():break
  for p in journeys.people:printerr("REMAINING ",vid," ",p.state," ",p.plan.kind," at=",p.v.pos," target=",p.v.target," slot=",p.slot)
  check(handed_off,vid+" indoor exit hands guest into city journey")
  check(floor_node._visitors.is_empty(),vid+" museum departure clears without a loop")
  check(journeys.people.is_empty(),vid+" all sixteen purposeful journeys finish")
  check(journeys.completed.taxi>=1,vid+" taxi boarding completes")
  check(journeys.completed.shuttle>=1,vid+" shuttle boarding completes")
  check(journeys.completed.park>=1,vid+" park stop completes")
  if not journeys.businesses.is_empty():check(journeys.completed.business>=2,vid+" business entries complete")
  print("JOURNEYS ",vid," ",journeys.completed," route_failures=",floor_node._plaza.failed_routes)
 floor_node.free();print("CITY_JOURNEYS failures=",failures);quit(1 if failures else 0)
