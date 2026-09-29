extends SceneTree
func _initialize() -> void:call_deferred("run")
func run() -> void:
 if OS.get_environment("GRAND_EXHIBIT_TEST_RUN")!="1":quit(2);return
 seed(20260919)
 var saves=root.get_node("SaveSystem");saves.set_process(false)
 if not saves.load_game():printerr("No copied playtest save");quit(2);return
 var gs=root.get_node("GameState");gs.ready_flag=true
 var f: Node=load("res://scenes/venue/floor/venue_floor.tscn").instantiate();f.size=Vector2(720,760);root.add_child(f)
 for n in root.get_children():n.process_mode=Node.PROCESS_MODE_DISABLED
 f._porter_planning_budget_usec=0;f.set_rates(root.get_node("Economy").venue_rates(gs.current_venue))
 var birth: Dictionary={}
 for tick in 6000:
  f.advance_sim(.1)
  for v in f._visitors:
   var id: int=v.node.get_instance_id()
   if not birth.has(id):birth[id]=tick*.1
  if tick%300==299:
   var states: Dictionary={}
   for v in f._visitors:states[v.state]=int(states.get(v.state,0))+1
   print("CLUSTER seconds=",(tick+1)*.1," states=",states," clumps=",f.clump_report()," departed=",f._journeys.completed)
  if tick in [1199,2999,5999]:
   for v in f._visitors:
    print("ACTOR age=",tick*.1-float(birth[v.node.get_instance_id()])," state=",v.state," pos=",v.pos," target=",v.target," path=",v.path.slice(0,3)," wait=",v.wait," seat=",v.seat)
 f.free();quit()
