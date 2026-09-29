extends SceneTree
## Native-render coverage: same frozen population, smoothing on/off, every venue.
var vp: SubViewport
var output: String
func _initialize() -> void:call_deferred("run")
func find_floor(n: Node) -> Node:
 if n.name=="VenueFloor":return n
 for c in n.get_children():
  var found:=find_floor(c)
  if found!=null:return found
 return null
func capture(path: String) -> void:
 for i in range(3):await process_frame
 await RenderingServer.frame_post_draw
 var err:=vp.get_texture().get_image().save_png(path)
 if err!=OK:printerr("FAIL save ",path);quit(1)
func run() -> void:
 output=OS.get_cmdline_user_args()[0]
 root.get_node("SaveSystem").set_process(false)
 var gs: Node=root.get_node("GameState");gs.reset_to_new_game();seed(817)
 vp=SubViewport.new();vp.size=Vector2i(720,1280);vp.render_target_update_mode=SubViewport.UPDATE_ALWAYS
 root.add_child(vp);vp.add_child(load("res://scenes/main.tscn").instantiate())
 await create_timer(2).timeout
 for i in range(4):load("res://scripts/ui/popup_manager.gd").close_top()
 var floor_node: Node=find_floor(vp)
 await create_timer(1).timeout
 for node in root.get_children():
  if node != vp:node.process_mode=Node.PROCESS_MODE_DISABLED
 vp.get_child(0).process_mode=Node.PROCESS_MODE_DISABLED
 var records: Array=[]
 for vid in root.get_node("DataLoader").venue_order():
  gs.current_venue=vid;floor_node.retheme(vid)
  for dept in ["ticket","archive","promotions","gallery"]:
   for track in ["staff","speed","value"]:gs.set_dept_level(vid,dept,track,8)
  floor_node.set_rates(root.get_node("Economy").venue_rates(vid));floor_node.advance_sim(30)
  for zoom in [1.0,2.0]:
   floor_node._user_zoom=zoom;floor_node._fit_canvas()
   var name:=str(vid)+("-close" if zoom>1 else "")
   floor_node.set_world_edge_smoothing(false)
   await capture(output+"/"+name+"-original.png")
   floor_node.set_world_edge_smoothing(true)
   floor_node._world_edges.material.set_shader_parameter("smoothing_enabled",false)
   await capture(output+"/"+name+"-passthrough.png")
   floor_node._world_edges.material.set_shader_parameter("smoothing_enabled",true)
   await capture(output+"/"+name+"-smoothed.png")
   records.append({"venue":vid,"zoom":zoom,"floor_rect":str(floor_node.get_global_rect())})
  print("EDGES_CAPTURE ",vid)
 var f:=FileAccess.open(output+"/capture-manifest.json",FileAccess.WRITE);f.store_string(JSON.stringify(records,"\t"));f.close()
 quit(0)
