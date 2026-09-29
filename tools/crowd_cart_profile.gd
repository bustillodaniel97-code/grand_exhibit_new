extends SceneTree
func _initialize() -> void:call_deferred("run")
func elapsed(call: Callable) -> int:
 var began:=Time.get_ticks_usec();call.call();return Time.get_ticks_usec()-began
func stats(samples: Array) -> Dictionary:
 samples.sort();var total:=0
 for value in samples:total+=int(value)
 return {"count":samples.size(),"mean_usec":float(total)/maxi(1,samples.size()),"p50_usec":samples[int((samples.size()-1)*.50)],"p95_usec":samples[int((samples.size()-1)*.95)],"p99_usec":samples[int((samples.size()-1)*.99)],"max_usec":samples.back()}
func run() -> void:
 root.get_node("SaveSystem").set_process(false)
 var gs: Node=root.get_node("GameState");gs.reset_to_new_game();gs.ready_flag=true;seed(918)
 var args:=OS.get_cmdline_user_args();var venue:=str(args[0]) if not args.is_empty() else "cloudrest"
 gs.current_venue=venue
 for dept in ["ticket","archive","gallery","promotions"]:
  for track in ["staff","speed","value"]:gs.set_dept_level(venue,dept,track,8)
 var floor_node: Node=load("res://scenes/venue/floor/venue_floor.tscn").instantiate();floor_node.set_size(Vector2(720,760));root.add_child(floor_node)
 for n in root.get_children():n.process_mode=Node.PROCESS_MODE_DISABLED
 floor_node._porter_planning_budget_usec=1500;floor_node.set_rates(root.get_node("Economy").venue_rates(venue))
 for tick in 1200:floor_node.advance_sim(.05)
 var full: Array=[]
 for tick in 1200:full.append(elapsed(func():floor_node.advance_sim(.05)))
 var plan: Array=[];var refresh: Array=[];var begin: Array=[];var visitors: Array=[];var rejected: Array=[];var porters: Array=[]
 var blocked_frames:=0;var refuge_frames:=0
 for tick in 2400:
  plan.append(elapsed(func():floor_node._plan_porter_routes()))
  floor_node._spawn_t+=.05;floor_node._try_spawn();floor_node._update_serve(.05)
  refresh.append(elapsed(func():floor_node._crowd_traffic.refresh_obstacles(.05)))
  begin.append(elapsed(func():floor_node._crowd_traffic.begin_step()))
  visitors.append(elapsed(func():floor_node._update_visitors(.05)))
  rejected.append(elapsed(func():floor_node._update_rejected(.05)))
  porters.append(elapsed(func():floor_node._update_porters(.05,false)))
  var blocked:=false
  for p in floor_node._porters:
   if p.pedestrian_wait>0:blocked=true
   if p.state=="yielding":refuge_frames+=1
  if blocked:blocked_frames+=1
 var report:={"venue":venue,"warmup_seconds":60,"full_advance_seconds":60,"component_seconds":120,"visitors":floor_node._visitors.size(),"rejected":floor_node._rejected.size(),"obstacles":floor_node._crowd_traffic.obstacles.size(),"blocked_frames":blocked_frames,"refuge_porter_frames":refuge_frames,"full_advance":stats(full),"dispatcher_plan":stats(plan),"crowd_refresh":stats(refresh),"crowd_begin":stats(begin),"visitors_update":stats(visitors),"rejected_update":stats(rejected),"porters_update":stats(porters),"scope":"Headless desktop CPU-concurrent diagnostic; component phase advances relevant floor systems manually and excludes city/plaza/visual decoration updates. It is not a phone FPS or hard real-time guarantee."}
 var path:=str(args[1]) if args.size()>1 else "/tmp/crowd-cart-profile.json"
 var file:=FileAccess.open(path,FileAccess.WRITE);file.store_string(JSON.stringify(report,"\t"));file.close()
 print("CROWD_CART_PROFILE ",JSON.stringify(report));quit(0)
