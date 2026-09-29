extends SceneTree
const Router:=preload("res://scenes/venue/floor/porter_router.gd")
const Snapshot:=preload("res://scenes/venue/floor/cart_dispatch_geometry.gd")
const RouteJob:=preload("res://scenes/venue/floor/porter_route_job.gd")
const D:=[Vector2.DOWN,Vector2.RIGHT,Vector2.UP,Vector2.LEFT]
var failures:=0
var report:={}
func check(ok:bool,label:String)->void:
 if not ok:failures+=1;printerr("FAIL: ",label)
func _initialize()->void:call_deferred("run")
func _pose(floor_node:Node,at:Vector2,heading:Vector2)->Dictionary:
 return {"at":at,"heading":heading,"height":floor_node._porter_layout._height_at(at)}
func _sweep(floor_node:Node,start:Dictionary,steps:Array)->Dictionary:
 var at:Vector2=start.at;var heading:Vector2=start.heading;var poses:Array=[];var turns:=0;var min_h:=INF;var max_h:=-INF
 for step in steps:
  var samples:=33 if step.turn else 5
  if step.turn:turns+=1
  for i in samples:
   var t:=i/float(samples-1);var p:=at.lerp(step.at,t);var h:=heading.rotated(heading.angle_to(step.heading)*t);var pose:=_pose(floor_node,p,h)
   poses.append(pose);min_h=minf(min_h,pose.height);max_h=maxf(max_h,pose.height)
  at=step.at;heading=step.heading
 return {"poses":poses,"turns":turns,"min_height":min_h,"max_height":max_h}
func _route(geometry:RefCounted,start:Dictionary,finish:Dictionary)->Array:
 var job:=RouteJob.new();job.begin(geometry,start.at,start.heading,finish.at,finish.heading)
 while job.pending():job.advance(4096,0)
 return job.result
func _validate(floor_node:Node,spec:Dictionary)->Dictionary:
 var base:=Router.new();base.configure(floor_node._porter_layout)
 var baseline:Array=base.route(spec.start.at,spec.start.heading,spec.finish.at,spec.finish.heading)
 check(not baseline.is_empty(),spec.id+": baseline opposing route exists")
 var traversals:Array=[];var cursor:Vector2=spec.start.at;var nearest:={"distance":INF}
 for i in baseline.size():
  var step:Dictionary=baseline[i];var distance:float=step.at.distance_to(spec.natural)
  if distance<float(nearest.distance):nearest={"distance":distance,"index":i,"at":str(step.at),"heading":str(step.heading),"turn":step.turn}
  if step.at.is_equal_approx(spec.natural):
   var prior:Vector2=cursor;var next_at:Vector2=baseline[i+1].at if i+1<baseline.size() else step.at
   traversals.append({"index":i,"heading":str(step.heading),"turn":step.turn,"approach_from":str(prior),"depart_to":str(next_at)})
  cursor=step.at
 var accepted:Array=[];var rejected:Array=[]
 for heading in D:
  if not floor_node._porter_layout.fits(spec.park,heading,false):continue
  var parked:=[_pose(floor_node,spec.park,heading)];var geometry:=Snapshot.new();geometry.configure(base,parked)
  var route:Array=_route(geometry,spec.start,spec.finish);var reverse:Array=_route(geometry,spec.finish,spec.start)
  if route.is_empty() or reverse.is_empty():rejected.append(str(heading));continue
  var sweep:=_sweep(floor_node,spec.start,route);var reverse_sweep:=_sweep(floor_node,spec.finish,reverse);var clear:=true
  for pose in sweep.poses+reverse_sweep.poses:
   if not geometry.clear_poses(parked,pose.at,pose.heading):clear=false;break
  if clear:accepted.append({"heading":str(heading),"steps":route.size(),"turns":sweep.turns,"reverse_steps":reverse.size(),"reverse_turns":reverse_sweep.turns,"height_range":[minf(sweep.min_height,reverse_sweep.min_height),maxf(sweep.max_height,reverse_sweep.max_height)]})
  else:rejected.append(str(heading))
 check(not accepted.is_empty(),spec.id+": parked boundary leaves protected opposing route")
 var unchanged:=not traversals.is_empty()
 return {"id":spec.id,"passing_refuge":str(spec.park),"natural_route_exit":str(spec.natural),"opposing_from":str(spec.start.at),"opposing_to":str(spec.finish.at),"passing_refuge_accepted":accepted,"rejected_fit_headings":rejected,"park_height":floor_node._porter_layout._height_at(spec.park),"baseline_steps":baseline.size(),"subject_route_traversals":traversals,"unchanged_route_exit":unchanged,"nearest_subject_pose":nearest,"passing_refuge_requires_waypoint_detour":spec.park!=spec.natural}

func _has_path(graph:Dictionary,from:String,to:String,seen:Dictionary={})->bool:
 if from==to:return true
 if seen.has(from):return false
 seen[from]=true
 for next in graph.get(from,[]):
  if _has_path(graph,str(next),to,seen):return true
 return false
func _request(graph:Dictionary,requester:String,holders:Array)->Dictionary:
 var trial:Dictionary=graph.duplicate(true);trial[requester]=holders.duplicate()
 for holder in holders:
  if _has_path(trial,str(holder),requester,{}):
   return {"accepted":false,"victim":requester,"action":"retreat to prior certified boundary while retaining current segment, then release it","graph":graph.duplicate(true)}
 return {"accepted":true,"victim":"","action":"wait or acquire when holders release","graph":trial}
func _cycle_cases()->Dictionary:
 var two:={"A":["B"]};var two_result:=_request(two,"B",["A"])
 check(not two_result.accepted and two_result.victim=="B","two-cart wait cycle is rejected")
 var three:={"A":["B"],"B":["C"]};var three_result:=_request(three,"C",["A"])
 check(not three_result.accepted and three_result.victim=="C","three-cart wait cycle is rejected")
 var chain:={"A":["B"]};var disjoint:=_request(chain,"C",["D"])
 check(disjoint.accepted,"disjoint next-segment request remains eligible")
 var progress:={"A":["B"]};var after_retreat:=_request({},"A",["B"])
 check(after_retreat.accepted,"older cart can wait safely after cycle victim retreats/releases")
 return {"rule":"Before recording a next-segment wait, add requester-to-holder edges and reject if any holder already reaches requester. The rejected requester retains its current segment only while reversing to its prior certified boundary, then releases; retreat must have been included in that segment envelope.","two_cart":{"existing":two,"attempt":{"requester":"B","holders":["A"]},"result":two_result},"three_cart":{"existing":three,"attempt":{"requester":"C","holders":["A"]},"result":three_result},"disjoint":{"existing":chain,"attempt":{"requester":"C","holders":["D"]},"result":disjoint},"post_retreat_progress":after_retreat}
func run()->void:
 root.get_node("SaveSystem").set_process(false)
 var gs:Node=root.get_node("GameState");gs.reset_to_new_game();gs.ready_flag=true
 var floor_node:Node=load("res://scenes/venue/floor/venue_floor.tscn").instantiate();floor_node.set_size(Vector2(720,760));root.add_child(floor_node)
 for n in root.get_children():n.process_mode=Node.PROCESS_MODE_DISABLED
 var specs:={
  "pelagic_crown":[
    {"id":"P-vault-west","park":Vector2(3.25,6),"natural":Vector2(4.25,6),"start":{"at":Vector2(4.25,1.75),"heading":Vector2.RIGHT},"finish":{"at":Vector2(1.75,11.25),"heading":Vector2.DOWN}},
    {"id":"P-lagoon-west","park":Vector2(4.5,10.75),"natural":Vector2(1.75,11.25),"start":{"at":Vector2(1.75,11.25),"heading":Vector2.DOWN},"finish":{"at":Vector2(1.75,16.25),"heading":Vector2.UP}},
    {"id":"P-lagoon-south","park":Vector2(6.5,16.5),"natural":Vector2(5.25,16.5),"start":{"at":Vector2(1.75,16.25),"heading":Vector2.UP},"finish":{"at":Vector2(9.25,18.5),"heading":Vector2.UP}}
  ],
  "grand_river":[
    {"id":"G-vault-apron","park":Vector2(8,3.75),"natural":Vector2(8.75,3.75),"start":{"at":Vector2(9.5,1.5),"heading":Vector2.RIGHT},"finish":{"at":Vector2(17.25,9),"heading":Vector2.DOWN}},
    {"id":"G-queue-south","park":Vector2(13.25,14.5),"natural":Vector2(14.5,14.25),"start":{"at":Vector2(14.5,13.75),"heading":Vector2.UP},"finish":{"at":Vector2(17.25,13.75),"heading":Vector2.UP}},
    {"id":"G-east-aisle","park":Vector2(16,5),"natural":Vector2(16,5.75),"start":{"at":Vector2(17.25,9),"heading":Vector2.DOWN},"finish":{"at":Vector2(10,2.25),"heading":Vector2.LEFT}}
  ]}
 for venue in specs:
  gs.current_venue=venue
  for dept in ["ticket","archive","gallery","promotions"]:
   for track in ["staff","speed","value"]:gs.set_dept_level(venue,dept,track,8)
  floor_node.retheme(venue);floor_node.set_rates(root.get_node("Economy").venue_rates(venue))
  var rows:Array=[]
  for spec in specs[venue]:rows.append(_validate(floor_node,spec))
  report[venue]=rows
 report["dependency_cycle_cases"]=_cycle_cases()
 var args:=OS.get_cmdline_user_args();var out:=str(args[0]) if not args.is_empty() else "/tmp/cart-segment-boundaries.json"
 var f:=FileAccess.open(out,FileAccess.WRITE);f.store_string(JSON.stringify(report,"\t"));f.close()
 print("CART_SEGMENT_BOUNDARIES failures=",failures," output=",out);quit(1 if failures else 0)
