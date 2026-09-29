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
  for index in 4:
   for overlap in [-.3,.01,.2,.6]:
    for other in city._cars+city.district.traffic:other.wait=9999
    var car: Dictionary=city._cars[index]
    var forward: bool=car.forward
    var half:=city.car_half_extent(car)
    car.gx=City.CROSS_MIN_GX-half+overlap if forward else City.CROSS_MAX_GX+half-overlap
    car.gy=City.LANE_OUT if forward else City.LANE_IN
    City.Routes.start(car,City.Routes.main_route(city,forward),true)
    var start: float=car.gx
    var entered:=false;var crossed:=false;var progress:=0.0
    for tick in 400:
     city.advance(.05,not crossed)
     if not entered and not city.crossing_has_car():entered=true
     if entered and not crossed:
      check(not city.crossing_has_car(),str(vid)+" car yields while guest crosses")
      progress+=.05
      crossed=progress>=8.0
    check(crossed,str(vid)+" reactive crossing clears overlap="+str(overlap)+" car="+str(index))
    check(absf(car.gx-start)>1.0,str(vid)+" car resumes after crossing")
  city.free()
 print("CROSSING_DEADLOCK failures=",failures);quit(1 if failures else 0)
