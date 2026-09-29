extends SceneTree
var output: String
func _initialize() -> void: call_deferred("run")
func snap(vp: SubViewport, name: String) -> void:
 for i in 3: await process_frame
 await RenderingServer.frame_post_draw
 vp.get_texture().get_image().save_png(output+"/"+name+".png")
func run() -> void:
 if OS.get_environment("GRAND_EXHIBIT_TEST_RUN")!="1":quit(2);return
 output=OS.get_cmdline_user_args()[0];DirAccess.make_dir_recursive_absolute(output)
 root.get_node("SaveSystem").set_process(false)
 var gs: Node=root.get_node("GameState");gs.reset_to_new_game();gs.ready_flag=true
 var ds: GDScript=load("res://scripts/meta/decor_system.gd")
 var vp:=SubViewport.new();vp.size=Vector2i(960,960);vp.render_target_update_mode=SubViewport.UPDATE_ALWAYS;root.add_child(vp)
 var floor_node: Control=load("res://scenes/venue/floor/venue_floor.tscn").instantiate();floor_node.size=Vector2(960,960);vp.add_child(floor_node)
 for n in root.get_children():
  if n!=vp:n.process_mode=Node.PROCESS_MODE_DISABLED
 floor_node.set_process(false)
 var rows: Array=[]
 for vid in root.get_node("DataLoader").venue_order():
  gs.current_venue=vid;gs.venue_state(vid)["decor"]={};gs.cash=BigNumber.from_parts(9,300);gs.gems=1000000
  for dept in ["ticket","gallery","archive","promotions"]:
   for track in ["speed","value","staff"]:gs.set_dept_level(vid,dept,track,int(root.get_node("DataLoader").get_venue(vid).track_level_cap))
  floor_node.retheme(vid);floor_node._station_ui.hide();floor_node._labels_layer.hide()
  await snap(vp,vid+"-before")
  var bought: bool=ds.buy_decor(vid,"brass_fountain")
  await snap(vp,vid+"-after")
  for did in root.get_node("DataLoader").decor.keys():
   ds.buy_decor(vid,did)
  var disconnected: Array=[]
  for w in floor_node._max_windows:
   if floor_node._nav_ids(floor_node._door_g, floor_node._admissions.slot(w, 0)).is_empty():disconnected.append(w)
  if not disconnected.is_empty():printerr("DECOR_ROUTE_FAILURE ",vid," ",disconnected)
  await create_timer(.9).timeout
  await snap(vp,vid+"-full")
  rows.append({"venue":vid,"bought":bought,"disconnected_admission_stations":disconnected,"anchor":str(floor_node._decor_anchor_by_id),"theme_anchors":str(floor_node._theme.decor_anchors)})
 FileAccess.open(output+"/receipts.json",FileAccess.WRITE).store_string(JSON.stringify(rows," "))
 quit(0)
