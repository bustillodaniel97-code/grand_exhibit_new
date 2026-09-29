extends SceneTree
const Character=preload("res://scenes/venue/floor/character.gd")
const Iso=preload("res://scenes/venue/floor/iso.gd")
func _initialize() -> void:call_deferred("run")
func run() -> void:
 if OS.get_environment("GRAND_EXHIBIT_TEST_RUN")!="1":quit(2);return
 var output: String=OS.get_cmdline_user_args()[0];DirAccess.make_dir_recursive_absolute(output)
 root.get_node("SaveSystem").set_process(false)
 var vp:=SubViewport.new();vp.size=Vector2i(960,720);vp.render_target_update_mode=SubViewport.UPDATE_ALWAYS;root.add_child(vp)
 var script=load("res://scenes/venue/floor/venue_floor.gd")
 var floor_node: Node=script.new();floor_node.size=vp.size;vp.add_child(floor_node);floor_node.set_process(false)
 for vid in ["whispering_pines","celestial_conservatory","grand_river"]:
  floor_node.retheme(vid)
  var city=floor_node._city;var journeys=floor_node._journeys
  for i in 5:
   var v=script.Visitor.new();v.city_plan=journeys.plan(v)
   v.node=Character.new();v.node.set_look_slot(i*5);floor_node._canvas.add_child(v.node);v.node.set_process(false)
   v.pos=v.city_plan.entry;v.speed=v.node.preferred_walk_speed();floor_node._place(v.node,v.pos)
   journeys.accept(v)
  floor_node._user_zoom=2.0;floor_node._fit_canvas()
  var focus: Vector2=city.transit.curb("shuttle")+Vector2(-1,-.7)
  var point: Vector2=Iso.to_screen(focus)*floor_node._canvas.scale+floor_node._canvas.position
  floor_node._pan_camera(floor_node.size*.5-point)
  for tick in 180:
   city.advance(.1);journeys.advance(.1)
   for p in journeys.people:p.v.node._process(.1)
   if tick%5==0:
    await process_frame;await RenderingServer.frame_post_draw
    vp.get_texture().get_image().save_png(output+"/%s-%03d.png"%[vid,tick])
  if not journeys.businesses.is_empty():
   var b: Dictionary=journeys.businesses[0]
   var at: Vector2=b.door
   var point2: Vector2=Iso.to_screen(at)*floor_node._canvas.scale+floor_node._canvas.position
   floor_node._canvas.position+=floor_node.size*.5-point2
   city.set_visible_band(Rect2(-floor_node._canvas.position/floor_node._canvas.scale,floor_node.size/floor_node._canvas.scale))
   var v=script.Visitor.new();v.node=Character.new();v.node.set_look_slot(12);floor_node._canvas.add_child(v.node);v.node.set_process(false)
   v.pos=b.path[-2];v.target=b.door;v.speed=v.node.preferred_walk_speed();v.state="city"
   var person: Dictionary={"v":v,"plan":{"kind":"business","business":b,"park":-1},"state":"travel","wait":0.0,"slot":-1}
   journeys.people.append(person);floor_node._place(v.node,v.pos)
   for tick in 60:
    city.advance(.1);journeys.advance(.1)
    if is_instance_valid(v.node) and not v.node.is_queued_for_deletion():v.node._process(.1)
    await process_frame;await RenderingServer.frame_post_draw
    vp.get_texture().get_image().save_png(output+"/%s-business-%02d.png"%[vid,tick])
 print("CITY_JOURNEY_REVIEW complete");quit()
