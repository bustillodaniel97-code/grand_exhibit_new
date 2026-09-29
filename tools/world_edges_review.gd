extends SceneTree
## Frozen real-scene comparison. Disposable saves only; never a phone benchmark.
var vp: SubViewport
var output: String
func _initialize() -> void:call_deferred("run")
func find_floor(n: Node) -> Node:
 if n.name=="VenueFloor":return n
 for c in n.get_children():
  var found:=find_floor(c)
  if found!=null:return found
 return null
func sample(label: String) -> void:
 for i in range(30):await process_frame
 await RenderingServer.frame_post_draw
 vp.get_texture().get_image().save_png(output+"/"+label+".png")
 var times: Array=[];var calls: Array=[];var gpu: Array=[];var cpu: Array=[];var intervals: Array=[]
 var previous:=Time.get_ticks_usec()
 for i in range(180):
  await process_frame
  var now:=Time.get_ticks_usec();intervals.append((now-previous)/1000.0);previous=now
  times.append(Performance.get_monitor(Performance.TIME_PROCESS)*1000)
  gpu.append(RenderingServer.viewport_get_measured_render_time_gpu(vp.get_viewport_rid()))
  cpu.append(RenderingServer.viewport_get_measured_render_time_cpu(vp.get_viewport_rid()))
  calls.append(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
 times.sort();calls.sort();gpu.sort();cpu.sort();intervals.sort()
 print("EDGES_PROFILE ",label," ",JSON.stringify({"median_process_ms":times[90],"p95_process_ms":times[171],"median_draw_calls":calls[90],"frames":180,"median_viewport_gpu_ms":gpu[90],"median_viewport_render_cpu_ms":cpu[90],"median_frame_interval_ms":intervals[90],"p95_frame_interval_ms":intervals[171]}))
func run() -> void:
 output=OS.get_cmdline_user_args()[0]
 root.get_node("SaveSystem").set_process(false)
 var gs: Node=root.get_node("GameState");gs.reset_to_new_game();seed(817)
 vp=SubViewport.new();vp.size=Vector2i(720,1280);vp.render_target_update_mode=SubViewport.UPDATE_ALWAYS
 root.add_child(vp);RenderingServer.viewport_set_measure_render_time(vp.get_viewport_rid(),true);vp.add_child(load("res://scenes/main.tscn").instantiate())
 await create_timer(2).timeout
 for i in range(4):load("res://scripts/ui/popup_manager.gd").close_top()
 var floor_node: Node=find_floor(vp)
 for dept in ["ticket","archive","promotions","gallery"]:
  for track in ["staff","speed","value"]:gs.set_dept_level(gs.current_venue,dept,track,8)
 floor_node.set_rates(root.get_node("Economy").venue_rates(gs.current_venue));floor_node.advance_sim(30)
 await create_timer(1).timeout
 for node in root.get_children():
  if node != vp:node.process_mode=Node.PROCESS_MODE_DISABLED
 vp.get_child(0).process_mode=Node.PROCESS_MODE_DISABLED
 var effect: ColorRect=floor_node._world_edges
 effect.material.set_shader_parameter("smoothing_enabled",false)
 await sample("passthrough")
 effect.material.set_shader_parameter("smoothing_enabled",true)
 await sample("smoothed")
 effect.visible=false;floor_node._world_copy.visible=false
 await sample("original")
 effect.visible=true;floor_node._world_copy.visible=true
 await sample("smoothed-repeat")
 quit(0)
