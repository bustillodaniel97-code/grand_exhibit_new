extends RefCounted
## Two real fleet vehicles serve signed curb stops once per connected trip.
var city: Node2D
var stops: Dictionary={}
var renderers: Array[Node2D]=[]
var boarded:={"taxi":0,"shuttle":0}
var arrivals:={"taxi":0,"shuttle":0}
func _init(host: Node2D) -> void:city=host
func configure() -> void:
 var signs:=city.get_node_or_null("TransitStops")
 if signs!=null:signs.queue_redraw()
 stops.clear();boarded={"taxi":0,"shuttle":0};arrivals={"taxi":0,"shuttle":0}
 for i in mini(2,city._cars.size()):
  var car: Dictionary=city._cars[i]
  car.transit="taxi" if i==0 else "shuttle"
  reset_trip(car)
 var bus_half: float=city.car_half_extent(city._cars[1])
 var taxi_half: float=city.car_half_extent(city._cars[0])
 var bus_x: float=city.CROSS_MIN_GX-bus_half-.7
 stops={"shuttle":Vector2(bus_x,18.42),"taxi":Vector2(bus_x-bus_half-taxi_half-1.1,18.42)}
 # Open with vehicles at actual stops so early guests can see where to travel.
 for i in 2:
  var car: Dictionary=city._cars[i]
  car.gx=stops[car.transit].x;car.gy=city.LANE_OUT
  city.Routes.start(car,city.Routes.main_route(city,true),true)
func reset_trip(car: Dictionary) -> void:
 if not car.has("transit"):return
 car.vehicle="morrow_sedan" if car.transit=="taxi" else "atlas_shuttle"
 car.paint=0;car.stop_served=false;car.dwell=0.0;car.passengers=0;car.alight=0;car.boarding=false;car.clearance=0.0
func limit_step(car: Dictionary,distance: float,dt: float) -> float:
 if not car.has("transit"):return distance
 car.clearance=maxf(0,float(car.clearance)-dt)
 if float(car.dwell)>0:
  car.dwell=maxf(0,float(car.dwell)-dt)
  if car.dwell==0:car.stop_served=true
  return 0.0
 if bool(car.stop_served) or not is_equal_approx(float(car.gy),city.LANE_OUT) or float(car.dir)<0:return distance
 var stop: Vector2=stops.get(car.transit,Vector2.INF)
 if float(car.gx)>stop.x+.001:return distance
 return minf(distance,maxf(0,stop.x-float(car.gx)))
func after_step(car: Dictionary) -> void:
 if not car.has("transit") or bool(car.stop_served) or float(car.dwell)>0:return
 var stop: Vector2=stops[car.transit]
 if absf(float(car.gx)-stop.x)<.001 and is_equal_approx(float(car.gy),city.LANE_OUT):
  car.dwell=9.0;car.alight=2 if car.transit=="shuttle" else 1
func vehicle(kind: String) -> Dictionary:
 for car in city._cars:
  if car.get("transit","")==kind and float(car.get("dwell",0))>0 and float(car.wait)<=0:return car
 return {}
func ready(kind: String) -> bool:
 var car:=vehicle(kind)
 return not car.is_empty() and int(car.passengers)<(8 if kind=="shuttle" else 3) and float(car.dwell)>2.5 and float(car.clearance)<=0 and not bool(car.boarding)
func board(kind: String) -> bool:
 if not ready(kind):return false
 var car:=vehicle(kind);car.passengers+=1;car.boarding=true;car.dwell=maxf(float(car.dwell),4.0);boarded[kind]+=1
 return true
func take_arrival(kind: String) -> bool:
 var car:=vehicle(kind)
 if car.is_empty() or bool(car.boarding) or int(car.alight)<=0 or float(car.dwell)<3:return false
 car.alight-=1;car.clearance=2.0;car.dwell=maxf(float(car.dwell),4.0);arrivals[kind]+=1;return true
func curb(kind: String) -> Vector2:return city.map_point(stops[kind])
func door(kind: String) -> Vector2:
 var stop: Vector2=stops[kind]
 return city.map_point(Vector2(stop.x,city.LANE_OUT-.53))

func build_renderers() -> void:
 # Vehicle contact points participate in the same Y-sort as their passengers.
 # Keeping a bus in the city's background batch drew boarders on its roof.
 for kind in ["taxi","shuttle"]:
  var n:=Node2D.new();n.name="TransitVehicle_"+kind;city.get_parent().add_child(n);renderers.append(n)
  n.draw.connect(func() -> void:
   if not is_instance_valid(city):return
   for car in city._cars:
    if car.get("transit","")!=kind:continue
    n.draw_set_transform(Vector2.ZERO,0,Vector2(1,.42));n.draw_circle(Vector2.ZERO,29,Color(0,0,0,.15));n.draw_set_transform(Vector2.ZERO)
    city.Vehicles.draw(n,car,Vector2.ZERO)
    if kind=="taxi":
     var badge:=Vector2(-9,-25)
     n.draw_rect(Rect2(badge,Vector2(18,9)),Color("ead591"))
     n.draw_string(ThemeDB.fallback_font,badge+Vector2(1,7),"TAXI",HORIZONTAL_ALIGNMENT_LEFT,-1,6,Color("253942")))
 city.tree_exiting.connect(func() -> void:
  for n in renderers:
   if is_instance_valid(n):n.queue_free())
 update_visuals()
func update_visuals() -> void:
 for i in renderers.size():
  var car: Dictionary=city._cars[i];var n:=renderers[i]
  n.visible=float(car.get("wait",0))<=0
  n.position=city.Iso.to_screen(city.map_point(Vector2(car.gx,car.gy)))+Vector2(0,city.DROP+5)
  n.queue_redraw()
