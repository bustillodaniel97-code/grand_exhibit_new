extends SceneTree
const Router=preload("res://scenes/venue/floor/porter_router.gd")
func _initialize() -> void:call_deferred("run")
func run() -> void:
 root.get_node("SaveSystem").set_process(false)
 var gs: Node=root.get_node("GameState");gs.reset_to_new_game();gs.ready_flag=true
 var floor_node: Node=load("res://scenes/venue/floor/venue_floor.tscn").instantiate();floor_node.set_size(Vector2(720,760));root.add_child(floor_node)
 for n in root.get_children():n.process_mode=Node.PROCESS_MODE_DISABLED
 var records: Array=[];var failures:=0
 var args:=OS.get_cmdline_user_args();var vid:=args[0];gs.current_venue=vid
 for dept in ["ticket","archive","gallery","promotions"]:
  for track in ["staff","speed","value"]:gs.set_dept_level(vid,dept,track,8)
 floor_node.retheme(vid);floor_node.set_rates(root.get_node("Economy").venue_rates(vid))
 # Ticket staffing is the independent geometry input: all three porter bays
 # are allocated regardless of hires; guide/promo footprints reserve all posts.
 for staffing in range(1,floor_node._max_windows+1):
  gs.set_dept_level(vid,"ticket","staff",staffing)
  floor_node.retheme(vid);floor_node.set_rates(root.get_node("Economy").venue_rates(vid))
  var layout: RefCounted=floor_node._porter_layout
  var router:=Router.new();router.configure(layout)
  var missing: Array=[];var checked:=0
  if not layout.failures.is_empty():missing.append({"allocation":layout.failures.duplicate()})
  else:
   for i in 3:
    for w in floor_node._windows_active:
     var bay: Dictionary=layout.drops[i];var dock: Dictionary=layout.counters[w]
     for reverse_trip in [false,true]:
      var start: Dictionary=dock if reverse_trip else bay
      var finish: Dictionary=bay if reverse_trip else dock
      checked+=1
      if router.route(start.at,start.heading,finish.at,finish.heading).is_empty():missing.append({"bay":i,"counter":w,"return":reverse_trip,"start":str(start),"finish":str(finish)})
  failures+=missing.size();records.append({"venue":vid,"ticket_staffing":staffing,"checked":checked,"missing":missing})
  var file:=FileAccess.open(args[1],FileAccess.WRITE);file.store_string(JSON.stringify(records,"\t"));file.close()
  print("STAFFING_ROUTES ",vid," staff=",staffing," checked=",checked," missing=",missing.size())
 quit(1 if failures else 0)
