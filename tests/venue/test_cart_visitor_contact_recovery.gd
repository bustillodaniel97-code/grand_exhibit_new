extends SceneTree
const Crowd:=preload("res://scenes/venue/floor/crowd_traffic.gd")
class Guest:var pos:=Vector2.ZERO
var failures:=0
func check(ok:bool,label:String)->void:
 if not ok:failures+=1;printerr("FAIL: ",label)
func _initialize()->void:call_deferred("run")
func run()->void:
 root.get_node("SaveSystem").set_process(false)
 var gs:Node=root.get_node("GameState");gs.reset_to_new_game();gs.ready_flag=true;gs.current_venue="pelagic_crown"
 var floor_node:Node=load("res://scenes/venue/floor/venue_floor.tscn").instantiate();floor_node.set_size(Vector2(720,760));root.add_child(floor_node)
 for n in root.get_children():n.process_mode=Node.PROCESS_MODE_DISABLED
 var crowd:=Crowd.new();crowd.configure(floor_node)
 crowd.cart_poses=[{"at":Vector2(5,16.5),"heading":Vector2.LEFT,"height":floor_node._porter_layout._height_at(Vector2(5,16.5))}]
 var guest:=Guest.new();guest.pos=Vector2(4.458337,16.5)
 check(crowd.Geometry.point_distance(guest.pos,Vector2(5,16.5),Vector2.LEFT)<crowd.RADIUS,"captured seed2402 shapes overlap")
 check(not crowd.visitor_clear(guest,Vector2(4.55,16.5)),"toward-cart step remains blocked")
 check(crowd.visitor_clear(guest,Vector2(4.2,16.5)),"strict separation escape is permitted")
 check(crowd.visitor_clear(guest,guest.pos+Vector2(-.02,0)),"actual footstep can separate while still inside rectangle")
 check(not crowd.visitor_clear(guest,Vector2(6,16.5)),"farther endpoint cannot authorize crossing through cart")
 crowd.cart_poses.append({"at":Vector2(3.4,16.5),"heading":Vector2.RIGHT,"height":crowd.cart_poses[0].height})
 check(not crowd.visitor_clear(guest,Vector2(4.2,16.5)),"escape cannot enter a second cart")
 crowd.cart_poses[1].height+=crowd.HEIGHT_CLEARANCE
 check(crowd.visitor_clear(guest,Vector2(4.2,16.5)),"separated storeys do not invent a second blocker")
 crowd.cart_poses.pop_back()
 guest.pos=Vector2(4,16.5)
 check(not crowd.visitor_clear(guest,Vector2(4.3,16.5)),"ordinary visitor still cannot enter expanded footprint")
 check(crowd.visitor_clear(guest,Vector2(3.98,16.5)),"ordinary movement away stays available")
 guest.pos=Vector2(4.458337,16.5)
 check(not crowd.visitor_clear(guest,Vector2(4.458337,16.6)),"sideways step that keeps contact is blocked")
 var previous:float=crowd._surface_distance(guest.pos,crowd.cart_poses[0])
 for frame in 24:
  var next:=guest.pos+Vector2(-.02,0)
  check(crowd.visitor_clear(guest,next),"continuous recovery step %d admitted"%frame)
  guest.pos=next
  var separation:float=crowd._surface_distance(guest.pos,crowd.cart_poses[0])
  check(separation>previous,"continuous recovery step %d strictly separates"%frame)
  previous=separation
 check(previous>=crowd.RADIUS+crowd.MARGIN,"recovery ends outside expanded footprint without teleporting")
 for index in 16:
  var front:=Vector2.RIGHT.rotated(index*TAU/16.0)
  crowd.cart_poses=[{"at":Vector2(5,16.5),"heading":front,"height":0.0}]
  guest.pos=Vector2(5,16.5)+front*.541663
  crowd.cart_poses[0].height=floor_node._porter_layout._height_at(guest.pos)
  check(crowd.visitor_clear(guest,guest.pos+front*.02),"outward footstep at angle %d"%index)
  check(not crowd.visitor_clear(guest,guest.pos-front*.02),"inward footstep rejected at angle %d"%index)
  check(not crowd.visitor_clear(guest,guest.pos-front*2),"opposite-face crossing rejected at angle %d"%index)
 crowd.cart_poses=[{"at":Vector2(5,16.5),"heading":Vector2.RIGHT,"height":0.0}]
 guest.pos=Vector2(5.57995,16.36)
 crowd.cart_poses[0].height=floor_node._porter_layout._height_at(guest.pos)
 check(not crowd.visitor_clear(guest,guest.pos+Vector2(.02,.001)),"initial inward travel near equal face distances is rejected analytically")
 guest.pos=Vector2(4.1,16.5)
 var height:float=floor_node._porter_layout._height_at(guest.pos)
 crowd.cart_poses=[{"at":Vector2(5,16.5),"heading":Vector2.LEFT,"height":height},{"at":Vector2(3.22,16.5),"heading":Vector2.RIGHT,"height":height}]
 check(not crowd.visitor_clear(guest,guest.pos+Vector2(-.02,0)),"two contacting carts cannot authorize escape deeper into the second")
 check(not crowd.visitor_clear(guest,guest.pos+Vector2(.02,0)),"two contacting carts cannot authorize escape deeper into the first")
 print("CART_VISITOR_CONTACT_RECOVERY failures=",failures," cart=(5,16.5) left h=",crowd.cart_poses[0].height," guest=(4.458337,16.5) h=",floor_node._porter_layout._height_at(guest.pos));quit(1 if failures else 0)
