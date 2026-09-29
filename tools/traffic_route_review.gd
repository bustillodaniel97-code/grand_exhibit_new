extends SceneTree
## Native close-ups of a foreground car continuing into a side street.
const City=preload("res://scenes/venue/floor/city.gd")
func _initialize() -> void:call_deferred("run")
func run() -> void:
 if OS.get_environment("GRAND_EXHIBIT_TEST_RUN")!="1":quit(1);return
 root.get_node("SaveSystem").set_process(false)
 var output: String=OS.get_cmdline_user_args()[0];DirAccess.make_dir_recursive_absolute(output)
 var vp:=SubViewport.new();vp.size=Vector2i(800,600);vp.render_target_update_mode=SubViewport.UPDATE_ALWAYS;root.add_child(vp)
 for vid in ["whispering_pines","celestial_conservatory","copper_kettle"]:
  var city:=City.new();city.venue_id=vid;vp.add_child(city)
  var car: Dictionary=city._cars[2 if vid!="celestial_conservatory" else 0]
  var points: PackedVector2Array=car.route;var bend:=Vector2.ZERO
  for i in range(points.size()-1):
   if points[i].y>18 and points[i+1].y<points[i].y-.001:bend=points[i];break
  city.position=Vector2(400,330)-city._p(bend,18)
  city.set_visible_band(Rect2(-city.position,Vector2(800,600)))
  # Start before the actual outgoing turn, preserving its native route.
  car.gx=bend.x+3.0*(1 if not car.forward else -1);car.gy=City.LANE_IN if not car.forward else City.LANE_OUT
  City.Routes.start(car,points,true)
  for other in city._cars+city.district.traffic:
   if other!=car:other.wait=9999
  for frame in range(60):
   city.advance(.15)
   await process_frame;await RenderingServer.frame_post_draw
   vp.get_texture().get_image().save_png(output+"/%s-%03d.png"%[vid,frame])
  city.free()
 quit(0)
