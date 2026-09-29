extends SceneTree
## Exercise the actual remapped building/road geometry and live district actors.
const District:=preload("res://scenes/venue/floor/city_district.gd")
var failures:=0
func check(ok: bool,label: String) -> void:
 if not ok:failures+=1;printerr("FAIL: ",label)
func _initialize() -> void:call_deferred("run")
func run() -> void:
 root.get_node("SaveSystem").set_process(false)
 var gs: Node=root.get_node("GameState");gs.reset_to_new_game()
 var floor_node: Control=load("res://scenes/venue/floor/venue_floor.gd").new();floor_node.size=Vector2(720,760);root.add_child(floor_node);floor_node.time_scale=0
 var signatures:={};var total_buildings:=0;var steps:=0
 for vid in root.get_node("DataLoader").venue_order():
  gs.current_venue=vid;floor_node.retheme(vid)
  var city: Node2D=floor_node._city;var district=city.district;var d: Dictionary=district.design
  check(not d.is_empty(),str(vid)+" loads its own district")
  if d.is_empty():continue
  signatures[JSON.stringify([d.roads,d.buildings,d.features])]=true
  var lots: Array[Rect2]=[]
  for b in d.buildings:
   var r:=District.rect(b.rect)
   var world:=Rect2(city.map_point(r.position),city.map_point(r.end)-city.map_point(r.position))
   check(not world.intersects(city.apron_bounds()),str(vid)+" building clears the playable apron")
   for other in lots:check(not world.intersects(other),str(vid)+" neighboring buildings do not overlap")
   lots.append(world);total_buildings+=1
   for road in d.roads:check(not r.intersects(District.rect(road).grow(.65)),str(vid)+" buildings leave roads and sidewalks clear")
   for f in d.features:check(not r.intersects(District.rect(f.rect)),str(vid)+" buildings clear water and public features")
  var roads: Array[Rect2]=[Rect2(-30,city.KERB_B,75,city.ROAD_B-city.KERB_B)]
  for r in d.roads:roads.append(District.rect(r))
  var connected:={0:true}
  for pass_index in roads.size():
   for i in roads.size():
    if connected.has(i):continue
    for j in connected.keys():
     if roads[i].intersects(roads[j],true):connected[i]=true;break
  check(connected.size()==roads.size(),str(vid)+" every street connects to the arrival road")
  for feature in d.features:
   var r:=District.rect(feature.rect)
   for road in d.roads:check(not r.intersects(District.rect(road)),str(vid)+" no road runs through water or a feature")
  check(district.walkers.size()==2 and district.traffic.size()==2,str(vid)+" has bounded live sidewalk and traffic populations")
  var previous: Array=[]
  for p in district.walkers:previous.append(p.node.position)
  var previous_cars: Array=[]
  for car in district.traffic:previous_cars.append(Vector2(car.gx,car.gy))
  var car_moved: Array[bool]=[false,false]
  var moved:=false
  for step in range(720):
   city.advance(.25)
   for car in district.traffic:
    var car_index: int=district.traffic.find(car)
    car_moved[car_index]=car_moved[car_index] or Vector2(car.gx,car.gy).distance_to(previous_cars[car_index])>.1
    var at:=Vector2(car.gx,car.gy);var on_road:=false
    for road in roads:on_road=on_road or road.has_point(at)
    check(on_road,str(vid)+" every live traffic sample stays on the connected street network")
   for i in district.walkers.size():
    var person: Dictionary=district.walkers[i]
    var at: Vector2=person.pos
    for lot in lots:check(not lot.grow(.10).has_point(at),str(vid)+" live sidewalk walkers avoid buildings at="+str(at)+" lot="+str(lot))
    check(not city.apron_bounds().has_point(at),str(vid)+" district walkers stay outside the playable apron")
    check(person.node.actor_role=="visitor",str(vid)+" street walkers never borrow employees")
    moved=moved or previous[i].distance_to(person.node.position)>1
    steps+=1
  check(moved,str(vid)+" sidewalk actors actually travel")
  for person in district.walkers:check(person.visits>=2,str(vid)+" residents complete real business errands")
  for i in district.traffic.size():
   var car: Dictionary=district.traffic[i];var at:=Vector2(car.gx,car.gy);var on_road:=false
   for r in roads:on_road=on_road or r.has_point(at)
   check(on_road and car_moved[i],str(vid)+" district traffic moves on a street")
  print("DISTRICT ",vid," buildings=",d.buildings.size()," walkers=",district.walkers.size()," traffic=",district.traffic.size())
 check(signatures.size()==12,"campaign districts have twelve independently authored geometries")
 floor_node.free()
 print("District buildings: ",total_buildings,"; live walker samples: ",steps,"; failures: ",failures)
 quit(1 if failures else 0)
