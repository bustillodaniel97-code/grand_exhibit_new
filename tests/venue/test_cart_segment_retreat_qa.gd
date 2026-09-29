extends SceneTree
const Router:=preload("res://scenes/venue/floor/porter_router.gd")
const Snapshot:=preload("res://scenes/venue/floor/cart_dispatch_geometry.gd")
var failures:=0
func check(ok:bool,label:String)->void:
 if not ok:failures+=1;printerr("FAIL: ",label)
func _initialize()->void:call_deferred("run")
func run()->void:
 root.get_node("SaveSystem").set_process(false)
 var gs:Node=root.get_node("GameState");gs.reset_to_new_game();gs.ready_flag=true;gs.current_venue="pelagic_crown"
 for dept in ["ticket","archive","gallery","promotions"]:
  for track in ["staff","speed","value"]:gs.set_dept_level("pelagic_crown",dept,track,8)
 var floor_node:Node=load("res://scenes/venue/floor/venue_floor.tscn").instantiate();floor_node.set_size(Vector2(720,760));root.add_child(floor_node)
 for n in root.get_children():n.process_mode=Node.PROCESS_MODE_DISABLED
 var router:=Router.new();router.configure(floor_node._porter_layout)
 # An adjacent owner may legally occupy the prior pose before a wait cycle is
 # discovered. That full cart makes reverse retreat from the natural exit fail.
 for pair in [[Vector2(4.25,6),Vector2.DOWN,Vector2(4.25,5.75)],[Vector2(5.25,16.5),Vector2.RIGHT,Vector2(5,16.5)]]:
  var geometry:=Snapshot.new();geometry.configure(router,[{"at":pair[2],"heading":pair[1],"height":floor_node._porter_layout._height_at(pair[2])}])
  var a:=geometry.key(pair[0],pair[1]);var b:=geometry.key(pair[2],pair[1])
  check(not geometry.can_move(a,b),"adjacent segment owner can block physical retreat at "+str(pair[0]))
 print("CART_SEGMENT_RETREAT_QA failures=",failures," conclusion=release-before-request");quit(1 if failures else 0)
