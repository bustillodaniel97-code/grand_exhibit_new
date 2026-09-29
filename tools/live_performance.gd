extends SceneTree
## Actual moving scene, with the floor advanced once per real frame so its CPU
## time can be measured separately. Other UI/economy/animation processing stays on.
## Development only. Use a disposable XDG_DATA_HOME and GRAND_EXHIBIT_TEST_RUN=1.
var vp: SubViewport
var output: String
var frames:=600
var venues: Array=[]
func _initialize() -> void:
 var args:=OS.get_cmdline_user_args()
 output=args[0]
 if args.size()>1:venues=Array(args[1].split(","))
 call_deferred("run")
func find_floor(n: Node) -> Node:
 if n.name=="VenueFloor":return n
 for c in n.get_children():
  var found:=find_floor(c)
  if found!=null:return found
 return null
func quantiles(values: Array) -> Dictionary:
 values.sort()
 return {"median":values[int(values.size()*.5)],"p95":values[int(values.size()*.95)],"p99":values[int(values.size()*.99)],"max":values.back()}
func run() -> void:
 root.get_node("SaveSystem").set_process(false)
 var gs: Node=root.get_node("GameState");gs.reset_to_new_game();seed(817)
 if venues.is_empty():venues=Array(root.get_node("DataLoader").venue_order())
 vp=SubViewport.new();vp.size=Vector2i(720,1280);vp.render_target_update_mode=SubViewport.UPDATE_ALWAYS
 root.add_child(vp);RenderingServer.viewport_set_measure_render_time(vp.get_viewport_rid(),true)
 vp.add_child(load("res://scenes/main.tscn").instantiate())
 await create_timer(2).timeout
 for i in range(4):load("res://scripts/ui/popup_manager.gd").close_top()
 var floor_node: Node=find_floor(vp)
 var records: Array=[]
 for vid in venues:
  gs.current_venue=vid;floor_node.retheme(vid)
  floor_node.set_process(false)
  for dept in ["ticket","archive","promotions","gallery"]:
   for track in ["staff","speed","value"]:gs.set_dept_level(vid,dept,track,8)
  floor_node.set_rates(root.get_node("Economy").venue_rates(vid))
  floor_node.advance_sim(90)
  # Warm the actual same moving scene before measuring shader/texture/cache cost.
  for i in range(60):
   await process_frame
   floor_node.advance_sim(1.0/60.0)
  var intervals: Array=[];var sim: Array=[];var gpu: Array=[];var cpu: Array=[];var calls: Array=[];var population: Array=[]
  var previous:=Time.get_ticks_usec()
  var start_cash: String=str(gs.cash.to_save())
  for i in range(frames):
   await process_frame
   var now:=Time.get_ticks_usec();var dt: float=(now-previous)/1000000.0;previous=now
   intervals.append(dt*1000)
   var begin:=Time.get_ticks_usec();floor_node.advance_sim(dt);sim.append((Time.get_ticks_usec()-begin)/1000.0)
   gpu.append(RenderingServer.viewport_get_measured_render_time_gpu(vp.get_viewport_rid()))
   cpu.append(RenderingServer.viewport_get_measured_render_time_cpu(vp.get_viewport_rid()))
   calls.append(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
   population.append(floor_node._visitors.size())
  await RenderingServer.frame_post_draw
  vp.get_texture().get_image().save_png(output+"/"+str(vid)+".png")
  var record:={"venue":vid,"frames":frames,"frame_interval_ms":quantiles(intervals),"floor_simulation_ms":quantiles(sim),"viewport_gpu_ms":quantiles(gpu),"viewport_render_cpu_ms":quantiles(cpu),"draw_calls":quantiles(calls),"visitors":quantiles(population),"cash_before":start_cash,"cash_after":str(gs.cash.to_save()),"staff":floor_node._staff_nodes.size(),"unreachable_targets":floor_node._unreachable_targets.size()}
  records.append(record);print("LIVE_PROFILE ",JSON.stringify(record))
  var file:=FileAccess.open(output+"/results.json",FileAccess.WRITE);file.store_string(JSON.stringify(records,"\t"));file.close()
 quit(0)
