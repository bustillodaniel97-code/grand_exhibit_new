extends SceneTree
var failures:=0
func check(ok:bool,message:String)->void:
 if not ok:failures+=1;printerr("FAIL: ",message)
func _initialize()->void:call_deferred("run")
func run()->void:
 root.get_node("SaveSystem").set_process(false)
 var gs=root.get_node("GameState");gs.reset_to_new_game();gs.ready_flag=true
 var floor_node=load("res://scenes/venue/floor/venue_floor.tscn").instantiate();root.add_child(floor_node)
 for n in root.get_children():n.process_mode=Node.PROCESS_MODE_DISABLED
 var vf=floor_node.get_script()
 var character=load("res://scenes/venue/floor/character.gd")
 # A guest owns each seat while approaching it, not only once seated.
 for i in floor_node._seats.size():
  var guest=vf.Visitor.new();guest.node=character.new();guest.node.set_look_slot(i)
  floor_node._canvas.add_child(guest.node);guest.pos=floor_node._seats[i]
  floor_node._visitors.append(guest)
  check(floor_node._begin_rest(guest),"claim original seat")
 var claims: int=floor_node._seat_taken.size()
 # Exercise the actual purchase callback, including the furniture rebuild.
 gs.venue_state(gs.current_venue).decor["0"]="oak_bench"
 root.get_node("EventBus").decor_purchased.emit(gs.current_venue,"oak_bench")
 check(floor_node._seat_taken.size()==claims,"decor purchase preserves occupied and approaching seats")
 for guest in floor_node._visitors:
  check(floor_node._seat_taken.has(guest.seat),"every resting guest still owns its seat")
  check(floor_node._seats[guest.seat]==guest.target,"claim still names the physical seat")
 var newcomer=vf.Visitor.new();newcomer.node=character.new();newcomer.node.set_look_slot(1)
 floor_node._canvas.add_child(newcomer.node)
 check(not floor_node._begin_rest(newcomer),"newcomer cannot claim another guest's occupied bench")
 floor_node._theme.props.reverse()
 floor_node._props_key="";floor_node._rebuild_props()
 for guest in floor_node._visitors:
  check(floor_node._seats[guest.seat]==guest.target,"reordered furniture rebinds seat indices")
  check(floor_node._seat_taken.has(guest.seat),"reordered furniture preserves claims")
 var leaving=floor_node._visitors.front();floor_node._release_seat(leaving)
 check(floor_node._begin_rest(newcomer),"released seat becomes available")
 check(floor_node._seat_taken.size()==claims,"release and reclaim preserve occupancy")
 floor_node._visitors.append(newcomer)
 # A real seated guest stands up when its furniture is removed; approaching
 # guests abandon the missing seat without freeing anybody else's claim.
 var seated=floor_node._visitors.back()
 check(seated.node.begin_seating(Vector2.DOWN,Vector2.ZERO),"seated guest has a real seating animation")
 floor_node._theme.props.clear();floor_node._props_key="";floor_node._rebuild_props()
 check(floor_node._seat_taken.is_empty(),"removed furniture has no stale claims")
 check(seated.state=="rise" and seated.node.seated,"removed seat starts standing before departure")
 for guest in floor_node._visitors:
  check(guest.seat==-1,"removed seat index cannot release a future reservation")
  if guest!=leaving and guest!=seated:check(guest.state=="linger","approaching guest abandons removed seat")
 floor_node.free()
 print("Seat reservation regression: ",failures," failures")
 quit(1 if failures else 0)
