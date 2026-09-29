extends "res://tests/venue/test_visitor_continuity.gd"
const Recovery:=preload("res://tools/crowd_traffic_contact_escape_qa.gd")
func contact_behind(v)->void:
 floor_node._crowd_traffic.cart_poses=[{"at":v.pos-Vector2(.541663,0),"heading":Vector2.RIGHT,"height":floor_node._porter_layout._height_at(v.pos)}]
func run()->void:
 root.get_node("SaveSystem").set_process(false)
 var gs=root.get_node("GameState");gs.reset_to_new_game();gs.ready_flag=true
 VF=load("res://scenes/venue/floor/venue_floor.gd")
 floor_node=load("res://scenes/venue/floor/venue_floor.tscn").instantiate();root.add_child(floor_node)
 for n in root.get_children():n.process_mode=Node.PROCESS_MODE_DISABLED
 floor_node._crowd_traffic=Recovery.new();floor_node._crowd_traffic.configure(floor_node)
 var v=guest(Vector2(4.458337,16.5));v.target=v.pos-Vector2(1,0);v.speed=1
 floor_node._crowd_traffic.cart_poses=[{"at":Vector2(5,16.5),"heading":Vector2.LEFT,"height":floor_node._porter_layout._height_at(v.pos)}]
 for frame in 24:
  var old:Vector2=v.pos
  floor_node._move(v,.02)
  check(v.pos.distance_to(old)>.0199 and v.pos.x<old.x,"real mover advances outward footstep %d"%frame)
 check(floor_node._crowd_traffic.Geometry.point_distance(v.pos,Vector2(5,16.5),Vector2.LEFT)>=.245,"real mover exits captured contact")
 discard(v)
 v=guest(Vector2(100,100));v.speed=3;v.window=0;v.target+=Vector2(2,0);v.path=[v.pos+Vector2(.25,0)];contact_behind(v)
 var other=guest(Vector2(101,100));other.window=0;floor_node._visitors.append(other)
 check(not floor_node._move(v,1),"recovery cannot bypass queue after first waypoint")
 check(v.pos.x>100.24 and v.pos.x<=100.40001,"queue blocks recovery at personal-space boundary")
 floor_node._visitors.erase(other);discard(other);discard(v)
 v=guest(Vector2(100,100));v.speed=3;v.state="to_queue_entry";v.window=0;v.seating_detour_retry=10;v.target+=Vector2(2,0);v.path=[v.pos+Vector2(.25,0)];contact_behind(v)
 other=guest(Vector2(101,100));other.seat=0;other.state="rest";floor_node._visitors.append(other)
 check(not floor_node._move(v,1),"recovery cannot bypass seat approach after first waypoint")
 check(v.pos.x>100.24 and v.pos.x<=100.40001,"seat footprint still stops recovery")
 floor_node._visitors.erase(other);discard(other);discard(v)
 floor_node.retheme("infinite_museum");floor_node._crowd_traffic=Recovery.new();floor_node._crowd_traffic.configure(floor_node)
 var target:=Vector2(15,6.5);var center:Vector2i=floor_node._nav_id(target)
 for y in range(center.y-1,center.y+2):
  for x in range(center.x-1,center.x+2):floor_node._nav.set_point_solid(Vector2i(x,y),true)
 v=guest(Vector2(13.75,6.5));v.target=target;v.speed=3;v.path=[Vector2(14,6.5)];contact_behind(v)
 check(not floor_node._move(v,1),"recovery stops at unreachable indoor segment")
 check(v.pos==Vector2(14,6.5),"recovery does not turn missing path into direct wall traversal")
 discard(v)
 # Isolated diagonal target has blocked orthogonal neighbors: anchoring a
 # detour there would silently cut the corner despite no legal A* connection.
 var nav:=AStarGrid2D.new();nav.region=Rect2i(398,398,7,7);nav.diagonal_mode=AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES;nav.update()
 nav.fill_solid_region(nav.region,true);nav.set_point_solid(Vector2i(400,400),false);nav.set_point_solid(Vector2i(401,401),false)
 v=guest(Vector2(100,100));contact_behind(v)
 check(floor_node._crowd_traffic._path_from_actual_position(v,nav,Vector2i(401,401)).is_empty(),"recovery route cannot anchor across blocked diagonal corner")
 # Either single open orthogonal cell must be used as an actual waypoint;
 # a diagonal target cannot replace that L-shaped route.
 var front:=Vector2(1,1).normalized()
 floor_node._crowd_traffic.cart_poses=[{"at":v.pos-front*.541663,"heading":front,"height":floor_node._porter_layout._height_at(v.pos)}]
 for side in [Vector2i(401,400),Vector2i(400,401)]:
  nav.set_point_solid(side,false)
  var route:Array=floor_node._crowd_traffic._path_from_actual_position(v,nav,Vector2i(401,401))
  check(not route.is_empty() and route[0]==Vector2(side)*.25,"single open corner side remains a real waypoint: %s"%side)
  nav.set_point_solid(side,true)
 nav.set_point_solid(Vector2i(401,400),false)
 var cardinal:Array=floor_node._crowd_traffic._path_from_actual_position(v,nav,Vector2i(401,400))
 check(not cardinal.is_empty() and cardinal[0]==Vector2(100.25,100),"valid cardinal recovery anchor remains available")
 nav.set_point_solid(Vector2i(401,400),true)
 nav.set_point_solid(Vector2i(401,402),false)
 nav.set_point_solid(Vector2i(401,403),false)
 check(floor_node._crowd_traffic._refuge_path(v,nav).is_empty(),"refuge initial frontier cannot cut the same blocked corner")
 discard(v)
 print("CART_RECOVERY_MOVEMENT checks=",checks," failures=",failures);quit(1 if failures else 0)
