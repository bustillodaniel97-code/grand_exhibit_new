extends "res://tests/venue/test_queue_protocol.gd"
func run() -> void:
 root.get_node("SaveSystem").set_process(false)
 var gs: Node=root.get_node("GameState");gs.reset_to_new_game();gs.ready_flag=true;gs.current_venue="grand_river"
 for dept in ["ticket","archive","gallery","promotions"]:
  for track in ["staff","speed","value"]:gs.set_dept_level(gs.current_venue,dept,track,8)
 VF=load("res://scenes/venue/floor/venue_floor.gd")
 floor_node=load("res://scenes/venue/floor/venue_floor.tscn").instantiate()
 floor_node.set_size(Vector2(720,760));root.add_child(floor_node)
 for n in root.get_children():n.process_mode=Node.PROCESS_MODE_DISABLED
 floor_node.set_rates(root.get_node("Economy").venue_rates(gs.current_venue))
 var p: Variant=floor_node._porters[0];floor_node._cart_dispatch.configure(floor_node)
 floor_node._porters=[p];p.pos=Vector2(15,10.25);p.heading=Vector2.LEFT;p.motion_step={};p.route_steps=[];p.route_cursor=0;p.state="idle";p.staged=true
 var w:=1
 var ahead=guest(floor_node._slot_pos(w,0),1);ahead.window=w;ahead.queue_entered=true;ahead.state="queue";ahead.target=ahead.pos;ahead.path=[]
 var v=guest(Vector2(13.99,10.25),5);v.window=w;v.queue_entered=true;v.state="to_queue";v.target=floor_node._slot_pos(w,1);v.path=floor_node._nav_path(v.pos,v.target)
 floor_node._queues[w]=[ahead,v];floor_node._stacks[w]=0
 var target: Vector2=v.target
 check(floor_node._porter_layout.fits(p.pos,p.heading,false),"fixture cart has a physically legal pose")
 floor_node._crowd_traffic.begin_step()
 var found: bool=floor_node._crowd_traffic.try_detour(v)
 check(found and v.cart_refuge,"approaching queue guest can step into a refuge")
 if found:
  for tick in 200:
   floor_node._crowd_traffic.begin_step();floor_node._update_visitors(.05)
   if v.pos.distance_to(v.cart_refuge_at)<.001:break
  check(v.pos.distance_to(v.cart_refuge_at)<.001,"guest walks to refuge without teleporting")
  check(v.state=="to_queue" and v.target==target and v.window==w and floor_node._queues[w]==[ahead,v],"refuge keeps FIFO membership, window, target and unready state")
  floor_node._serve_t[w]=100;floor_node._update_serve(.01)
  check(floor_node._stacks[w]==1 and ahead.state=="browse" and floor_node._queues[w][0]==v,"only the physically ready customer ahead is served")
  check(v.state=="to_queue" and v.target==floor_node._slot_pos(w,0),"front departure refreshes the refugee's assigned slot")
  floor_node._serve_t[w]=100;floor_node._update_serve(.01)
  check(floor_node._stacks[w]==1,"refugee cannot receive service at the off-counter refuge")
  var bay: Dictionary=floor_node._porter_bay(p);p.pos=bay.at;p.heading=bay.heading
  for tick in 800:
   floor_node._crowd_traffic.begin_step();floor_node._update_visitors(.05)
   if v.state=="queue":break
  check(v.state=="queue" and v.pos.distance_to(floor_node._slot_pos(w,0))<.03 and v.path.is_empty(),"guest rejoins its updated slot after cart clearance")
  floor_node._serve_t[w]=100;floor_node._update_serve(.01)
  check(floor_node._stacks[w]==2 and v.state=="browse","refugee is served exactly once after the prior customer")
 print("Queue cart refuge failures: ",failures);quit(1 if failures else 0)
