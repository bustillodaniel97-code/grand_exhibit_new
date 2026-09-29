extends SceneTree
## Render genuine museum dioramas with an isolated authoring save, without HUD.
func _initialize() -> void: call_deferred("run")
func run() -> void:
 if OS.get_environment("GRAND_EXHIBIT_TEST_RUN") != "1":
  push_error("An isolated authoring profile is required");quit(1);return
 var output: String=OS.get_cmdline_user_args()[0]
 DirAccess.make_dir_recursive_absolute(output)
 root.get_node("SaveSystem").set_process(false)
 var gs: Node=root.get_node("GameState")
 gs.reset_to_new_game();seed(917)
 var vp:=SubViewport.new()
 vp.size=Vector2i(1280,960)
 vp.render_target_update_mode=SubViewport.UPDATE_ALWAYS
 root.add_child(vp)
 var floor_node: Control=load("res://scenes/venue/floor/venue_floor.tscn").instantiate()
 floor_node.size=Vector2(1280,960)
 vp.add_child(floor_node)
 for n in root.get_children():
  if n!=vp:n.process_mode=Node.PROCESS_MODE_DISABLED
 floor_node.set_process(false)
 for vid in root.get_node("DataLoader").venue_order():
  gs.current_venue=vid
  for dept in ["ticket","archive","promotions","gallery"]:
   for track in ["staff","speed","value"]:gs.set_dept_level(vid,dept,track,8)
  floor_node.retheme(vid)
  floor_node.set_rates(root.get_node("Economy").venue_rates(vid))
  floor_node.advance_sim(30)
  floor_node._user_zoom=1.05;floor_node._fit_canvas()
  floor_node._station_ui.hide();floor_node._labels_layer.hide()
  for i in 4:await process_frame
  await RenderingServer.frame_post_draw
  var img:=vp.get_texture().get_image()
  img.resize(960,720,Image.INTERPOLATE_LANCZOS)
  if img.save_png(output+"/"+vid+".png")!=OK:quit(1);return
  print("VENUE_ART ",vid)
 quit(0)
