extends SceneTree
const City=preload("res://scenes/venue/floor/city.gd")
var failures:=0
func check(ok: bool,label: String) -> void:
 if not ok:failures+=1;printerr("FAIL: ",label)
func _initialize() -> void:call_deferred("run")
func run() -> void:
 root.get_node("SaveSystem").set_process(false)
 for vid in root.get_node("DataLoader").venue_order():
  var city:=City.new();city.venue_id=vid;root.add_child(city)
  var positions:={};var directions:={};var trips:=0;var moved:=0.0
  for step in range(12000):
   city.advance(.05,step%180<30)
   for i in (city._cars+city.district.traffic).size():
    var car: Dictionary=(city._cars+city.district.traffic)[i];var at:=Vector2(car.gx,car.gy)
    var road_ok:=at.y>=City.KERB_B and at.y<=City.ROAD_B
    for row in city.district.design.roads:road_ok=road_ok or Rect2(row[0],row[1],row[2],row[3]).has_point(at)
    check(road_ok,str(vid)+" car stays on connected asphalt")
    if positions.has(i) and positions[i].trip==car.trip:
     var delta: float=at.distance_to(positions[i].at)
     check(delta<=float(car.speed)*.05+.01,str(vid)+" moves continuously within a trip")
     moved+=delta
    elif positions.has(i):trips+=1
    positions[i]={"at":at,"trip":car.trip}
    directions[city.Vehicles.direction(car)]=true
  check(trips>=6,str(vid)+" traffic completes trips without deadlock: "+str(trips))
  check(directions.size()==4,str(vid)+" uses all street directions")
  print("ROUTES ",vid," trips=",trips," moved=",moved)
  city.free()
 print("Traffic failures: ",failures);quit(1 if failures else 0)
