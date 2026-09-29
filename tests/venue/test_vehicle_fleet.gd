extends SceneTree
const Fleet:=preload("res://scenes/venue/floor/vehicle_sprites.gd")
var failures:=0
func _initialize() -> void:call_deferred("run")
func check(ok: bool,label: String) -> void:
 if not ok:failures+=1;printerr("FAIL: ",label)
func run() -> void:
 root.get_node("SaveSystem").set_process(false)
 var gs: Node=root.get_node("GameState");gs.reset_to_new_game()
 var floor_node: Control=load("res://scenes/venue/floor/venue_floor.gd").new();floor_node.size=Vector2(720,760);root.add_child(floor_node);floor_node.set_process(false)
 var data:=Fleet.manifest();var checked:=0
 check(data.sprites.size()==48,"six original models have two paints and four directions")
 for model in data.models:
  for paint in range(2):
   for axis in [Vector2.RIGHT,Vector2.DOWN]:
    for direction in [-1.0,1.0]:
     var record:=Fleet.sprite({"vehicle":model,"paint":paint,"axis":axis,"dir":direction})
     check(not record.is_empty(),"all model/paint/direction combinations exist")
     if record.is_empty():continue
     var texture: Texture2D=load("res://art/vehicles/"+str(record.file))
     check(texture!=null,"fleet texture imports")
     if texture!=null:check(texture.get_image().has_mipmaps(),"traffic remains filtered at distant city scale")
     checked+=1
 var profiles:={}
 for vid in root.get_node("DataLoader").venue_order():
  gs.current_venue=vid;floor_node.retheme(vid);floor_node.set_process(false)
  var city: Node=floor_node._city
  profiles[JSON.stringify(data.profiles[vid])]=true
  for car in city._cars:
   check(car.vehicle!="atlas_shuttle","long shuttle uses district streets, not the short crossing queue")
   var dimensions: Dictionary=data.models[car.vehicle]
   check(float(dimensions.width)<city.LANE_IN-city.LANE_OUT,"vehicle including mirrors fits its lane")
   var half: float=city.car_half_extent(car)
   for center in [city.CROSS_MIN_GX,city.CROSS_MAX_GX]:
    var a: Vector2=city.map_point(Vector2(center-half,city.LANE_OUT));var b: Vector2=city.map_point(Vector2(center+half,city.LANE_OUT))
    check(b.x-a.x+0.0001>=float(dimensions.length),"stop envelope contains actual body after venue remapping")
  var original: Array=city._cars.duplicate()
  for direction in [-1.0,1.0]:
   var car: Dictionary=original[0].duplicate();car.dir=direction;car.speed=1.0
   var half: float=city.car_half_extent(car)
   car.gx=city.CROSS_MIN_GX-half-.1 if direction>0 else city.CROSS_MAX_GX+half+.1
   city.Routes.start(car,PackedVector2Array([Vector2(-30 if direction>0 else 36,city.LANE_OUT),Vector2(36 if direction>0 else -30,city.LANE_OUT)]),true)
   city._cars.clear();city._cars.append(car);city.advance(.5,true)
   check(not city.crossing_has_car(),"yielded physical bumper leaves crossing clear")
   var stopped: float=car.gx;city.advance(.1,false)
   check((float(car.gx)-stopped)*direction>0,"car resumes after pedestrian phase")
   car.gx=city.CROSS_MIN_GX-half+.1 if direction>0 else city.CROSS_MAX_GX+half-.1
   check(city.crossing_has_car(),"physical bumper intrusion holds pedestrians back")
  city._cars.assign(original)
  check(city.district.traffic.size()==2,"background fleet remains bounded")
  for car in city.district.traffic:check(not Fleet.sprite(car).is_empty(),"background car has its real route-facing image")
 check(profiles.size()==12,"each city has its own fleet mix")
 floor_node.free();print("FLEET_RESULT textures=",checked," venues=12 failures=",failures);quit(1 if failures else 0)
