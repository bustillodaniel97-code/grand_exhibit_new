extends SceneTree
func _initialize() -> void:call_deferred("run")
func run() -> void:
 root.get_node("SaveSystem").set_process(false)
 var gs: Node=root.get_node("GameState");gs.reset_to_new_game();gs.ready_flag=true
 var vid:="sunspire";gs.current_venue=vid
 for dept in ["ticket","archive","gallery","promotions"]:
  for track in ["staff","speed","value"]:gs.set_dept_level(vid,dept,track,8)
 var f: Node=load("res://scenes/venue/floor/venue_floor.tscn").instantiate();f.set_size(Vector2(720,760));root.add_child(f)
 for n in root.get_children():n.process_mode=Node.PROCESS_MODE_DISABLED
 f.retheme(vid);f.set_rates(root.get_node("Economy").venue_rates(vid));f._stacks.fill(1)
 var peak:=0;var peak_phase:="";var peak_active:=false;var calls_over:=0;var deposits: Dictionary={}
 for tick in 18000:
  var before_phase:=str(f._cart_dispatch.active.get("phase","select"))
  var before_active: bool=not f._cart_dispatch.active.is_empty()
  f._update_porters(1.0/60.0)
  var elapsed: int=f._porter_planning_usec
  if elapsed>1500:calls_over+=1
  if elapsed>peak:peak=elapsed;peak_phase=before_phase;peak_active=before_active
  for p in f._porters:
   if p.state=="deposit":deposits[p.window]=true
  if deposits.size()==f._max_windows:
   print("CART_BUDGET seconds=",tick/60.0," peak=",peak," over=",calls_over," phase=",peak_phase," active=",peak_active)
   quit(0);return
 printerr("FAIL incomplete CART_BUDGET peak=",peak," phase=",peak_phase);quit(1)
