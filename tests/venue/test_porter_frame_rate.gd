extends SceneTree
var failures:=0
func check(ok: bool,label: String) -> void:
 if not ok:failures+=1;printerr("FAIL: ",label)
func _initialize() -> void:call_deferred("run")
func run() -> void:
 root.get_node("SaveSystem").set_process(false)
 var gs: Node=root.get_node("GameState");gs.reset_to_new_game();gs.ready_flag=true;gs.current_venue="whispering_pines"
 for dept in ["ticket","archive","gallery","promotions"]:
  for track in ["staff","speed","value"]:gs.set_dept_level(gs.current_venue,dept,track,8)
 var f: Node=load("res://scenes/venue/floor/venue_floor.tscn").instantiate();f.set_size(Vector2(720,760));root.add_child(f)
 for n in root.get_children():n.process_mode=Node.PROCESS_MODE_DISABLED
 var start: Dictionary=f._porter_layout.drops[0];var goal: Dictionary=f._porter_layout.counters[0]
 var route: Array=f._porter_router.route(start.at,start.heading,goal.at,goal.heading)
 check(not route.is_empty(),"real museum route exists")
 var all_samples: Array=[];var arrivals: Array=[]
 for fps in [20,30,60]:
  var p: Variant=f._porters[0];p.pos=start.at;p.heading=start.heading;p.dock=goal;p.target=goal.at
  p.motion_step={};p.route_job=null;p.route_steps=route.duplicate();p.route_cursor=0;p.route_retry=0;p.replan_after_step=false
  var samples: Array=[];var arrival:=0.0
  for tick in 120*fps:
   var done: bool=f._porter_move(p,1.0/fps)
   if (tick+1)%fps==0:samples.append(p.pos)
   if done:arrival=(tick+1)/float(fps);break
  check(arrival>0,"live follower finishes at "+str(fps)+" fps")
  check(p.pos==goal.at and p.heading==goal.heading,"arrival preserves exact pose")
  all_samples.append(samples);arrivals.append(arrival)
 for i in range(1,3):
  for k in mini(all_samples[0].size(),all_samples[i].size()):check(all_samples[0][k].distance_to(all_samples[i][k])<.001,"equal elapsed time gives equal position across frame rates")
  check(absf(arrivals[0]-arrivals[i])<=.051,"arrival differs by at most one 20-fps tick")
 print("Porter frame-rate failures: ",failures," arrivals_20_30_60=",arrivals);quit(1 if failures else 0)
