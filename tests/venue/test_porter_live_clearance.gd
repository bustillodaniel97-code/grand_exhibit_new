extends SceneTree
var failures:=0
func check(ok: bool,label: String) -> void:
 if not ok:failures+=1;printerr("FAIL: ",label)
func _initialize() -> void:call_deferred("run")
func run() -> void:
 root.get_node("SaveSystem").set_process(false)
 var gs: Node=root.get_node("GameState");gs.reset_to_new_game();gs.ready_flag=true
 var f: Node=load("res://scenes/venue/floor/venue_floor.tscn").instantiate();f.set_size(Vector2(720,760));root.add_child(f);f._porter_planning_budget_usec=0
 for n in root.get_children():n.process_mode=Node.PROCESS_MODE_DISABLED
 var records: Array=[]
 for vid in root.get_node("DataLoader").venue_order():
  if OS.has_environment("PORTER_LIVE_ONLY") and vid not in OS.get_environment("PORTER_LIVE_ONLY").split(","):continue
  gs.current_venue=vid
  for dept in ["ticket","archive","gallery","promotions"]:
   for track in ["staff","speed","value"]:gs.set_dept_level(vid,dept,track,8)
  f.retheme(vid);f.set_rates(root.get_node("Economy").venue_rates(vid));f._stacks.fill(1)
  var collected: Dictionary={};var deposited: Dictionary={};var samples:=0;var clips:=0;var jumps:=0;var turns:=0;var reverse_steps:=0;var elapsed:=0.0
  for tick in 12000:
   var before: Array=[]
   for p in f._porters:before.append(p.pos)
   f._update_porters(.025);elapsed+=.025
   for i in f._porters.size():
    var p: Variant=f._porters[i]
    if p.pos.distance_to(before[i])>f._porter_speed(p)*.025+.0001:jumps+=1
    var heading: Vector2=p.heading
    if not p.motion_step.is_empty() and p.motion_step.turn:
     heading=p.heading.rotated(p.heading.angle_to(p.motion_step.heading)*p.turn_progress);turns+=1
    if p.node.walk_backwards:reverse_steps+=1
    if tick%3==0:
     samples+=1
     if not f._porter_layout.fits(p.pos,heading,false):
      clips+=1
      if clips<=4:printerr("CLIP ",vid," ",p.state," ",p.pos," ",heading)
    if p.state=="collect":collected[p.window]=true
    if p.state=="deposit":deposited[p.window]=true
   if deposited.size()==f._max_windows:break
  check(clips==0,vid+" live body/cart clears full static geometry through turns and reverse motion")
  check(jumps==0,vid+" moving courier never teleports")
  check(deposited.size()==f._max_windows and collected.size()==f._max_windows,vid+" all real collection/deposit states complete")
  check(turns>0 and reverse_steps>0,vid+" live test exercises both turning and backing")
  records.append({"venue":vid,"samples":samples,"clips":clips,"jumps":jumps,"turn_ticks":turns,"reverse_ticks":reverse_steps,"collections":collected.size(),"deposits":deposited.size(),"sim_seconds":elapsed})
  print("LIVE_CLEARANCE ",vid," collected=",collected.size()," deposited=",deposited.size()," clips=",clips," jumps=",jumps," seconds=",elapsed)
  if OS.get_cmdline_user_args().size()>0:
   var file:=FileAccess.open(OS.get_cmdline_user_args()[0],FileAccess.WRITE);file.store_string(JSON.stringify(records,"\t"));file.close()
 print("Live porter clearance failures: ",failures);quit(1 if failures else 0)
