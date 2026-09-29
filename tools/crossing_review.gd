extends SceneTree
const Character=preload("res://scenes/venue/floor/character.gd")
const City=preload("res://scenes/venue/floor/city.gd")
const Iso=preload("res://scenes/venue/floor/iso.gd")
func _initialize() -> void:call_deferred("run")
func run() -> void:
 if OS.get_environment("GRAND_EXHIBIT_TEST_RUN")!="1":quit(2);return
 var output: String=OS.get_cmdline_user_args()[0];DirAccess.make_dir_recursive_absolute(output)
 root.get_node("SaveSystem").set_process(false)
 var vp:=SubViewport.new();vp.size=Vector2i(720,900);vp.render_target_update_mode=SubViewport.UPDATE_ALWAYS;root.add_child(vp)
 var floor_node: Node=load("res://scenes/venue/floor/venue_floor.tscn").instantiate();floor_node.size=vp.size;vp.add_child(floor_node)
 floor_node.set_process(false)
 var city: Node=floor_node._city
 for other in city._cars+city.district.traffic:other.wait=9999
 var car: Dictionary=city._cars[0];car.gx=City.CROSS_MIN_GX-city.car_half_extent(car)+.2;car.gy=City.LANE_OUT
 City.Routes.start(car,City.Routes.main_route(city,true),true)
 var floor_script=load("res://scenes/venue/floor/venue_floor.gd")
 var v=floor_script.Visitor.new();v.node=Character.new();v.node.set_look_slot(2);floor_node._canvas.add_child(v.node);v.node.set_process(false)
 v.pos=city.map_point(City.CROSS_FAR);v.target=city.map_point(City.CROSS_NEAR);v.speed=v.node.preferred_walk_speed();v.state="arriving";v.uses_crosswalk=true
 floor_node._visitors.append(v);floor_node._place(v.node,v.pos)
 floor_node._user_zoom=2.0;floor_node._fit_canvas()
 var point: Vector2=Iso.to_screen(v.pos.lerp(v.target,.5))*floor_node._canvas.scale+floor_node._canvas.position
 floor_node._pan_camera(floor_node.size*.5-point)
 var records: Array=[]
 for tick in 100:
  city.advance(.2,floor_node._pedestrian_crossing())
  floor_node._move(v,.2);v.node._process(.2)
  if tick%5==0:
   await process_frame;await RenderingServer.frame_post_draw
   vp.get_texture().get_image().save_png(output+"/crossing-%03d.png"%tick)
   records.append({"seconds":(tick+1)*.2,"pedestrian":str(v.pos),"car":car.gx,"occupied":city.crossing_has_car()})
 var passed: bool=v.pos.distance_to(v.target)<.01 and car.gx>City.CROSS_MAX_GX+city.car_half_extent(car)
 var file:=FileAccess.open(output+"/review.json",FileAccess.WRITE);file.store_string(JSON.stringify({"passed":passed,"frames":records},"\t"))
 print("NATIVE_CROSSING passed=",passed);quit(0 if passed else 1)
