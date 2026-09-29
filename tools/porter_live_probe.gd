extends SceneTree
func _initialize() -> void:call_deferred("run")
func run() -> void:
 root.get_node("SaveSystem").set_process(false)
 var gs: Node=root.get_node("GameState");gs.reset_to_new_game();gs.ready_flag=true
 var args:=OS.get_cmdline_user_args();var vid:=args[0];gs.current_venue=vid
 for dept in ["ticket","archive","gallery","promotions"]:
  for track in ["staff","speed","value"]:gs.set_dept_level(vid,dept,track,8)
 var f: Node=load("res://scenes/venue/floor/venue_floor.tscn").instantiate();f.set_size(Vector2(720,760));root.add_child(f)
 for n in root.get_children():n.process_mode=Node.PROCESS_MODE_DISABLED
 f.retheme(vid);f.set_rates(root.get_node("Economy").venue_rates(vid));f._stacks.fill(1)
 var collection: Dictionary={};var deposits: Dictionary={};var peak:=0;var planning:=0
 for tick in 18000:
  f._update_porters(1.0/60.0);peak=maxi(peak,f._porter_planning_usec);planning+=f._porter_planning_usec
  for p in f._porters:
   if p.state=="collect":collection[p.window]=true
   if p.state=="deposit":deposits[p.window]=true
  if tick%3600==3599:
   print("LIVE_CART ",vid," t=",(tick+1)/60," collections=",collection.keys()," deposits=",deposits.keys()," planner_us=",planning," peak=",peak)
   for p in f._porters:print("PORTER ",p.state," ",p.window," pos=",p.pos," target=",p.target," heading=",p.heading," cursor=",p.route_cursor,"/",p.route_steps.size()," retry=",p.route_retry," job=",p.route_job.status if p.route_job else "none"," expanded=",p.route_job.expanded if p.route_job else 0)
  if deposits.size()==f._max_windows:print("LIVE_CART_COMPLETE ",vid," seconds=",tick/60.0," peak=",peak);quit(0);return
 quit(1)
