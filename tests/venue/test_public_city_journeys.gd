extends SceneTree
var failures:=0
func check(ok: bool,label: String) -> void:
 if not ok:failures+=1;printerr("FAIL: ",label)
func _initialize() -> void:call_deferred("run")
func run() -> void:
 if OS.get_environment("GRAND_EXHIBIT_TEST_RUN")!="1":quit(2);return
 seed(20260918)
 root.get_node("SaveSystem").set_process(false)
 var gs=root.get_node("GameState");gs.reset_to_new_game();gs.ready_flag=true
 var f: Node=load("res://scenes/venue/floor/venue_floor.gd").new();f.size=Vector2(720,760);root.add_child(f);f.set_process(false)
 var selected: Array=root.get_node("DataLoader").venue_order()
 if not OS.get_cmdline_user_args().is_empty():selected=[OS.get_cmdline_user_args()[0]]
 for vid in selected:
  gs.current_venue=vid;f.retheme(vid)
  var p=f._plaza;var j=f._journeys
  for tick in 14000:
   f._city.advance(.05,f._pedestrian_crossing());p.advance(.05);j.advance(.05)
   check(p.people.size()+j.public_count()<=p.MAX_PEOPLE,vid+" total park population remains bounded during errands")
  for actor in p.people:check(p.elapsed-float(actor.born)<450,vid+" no park guest remains stranded")
  for actor in j.people:
   if actor.has("public"):check(p.elapsed-float(actor.public.born)<450,vid+" city trip completes within bounded time")
  for actor in j.people:print("WORLD_ACTOR ",vid," ",actor.state," ",actor.v.pos," -> ",actor.v.target," path=",actor.v.path," activity=",actor.get("public",{}).get("activity_index",-1))
  for actor in p.people:print("PARK_ACTOR ",vid," ",actor.state," ",actor.pos," activity=",actor.activity_index," path=",actor.path)
  print("PUBLIC_WORLD ",vid," completed=",p.completed," destinations=",j.completed," invalid=",p.invalid_steps," failed=",p.failed_routes)
  check(p.completed.rest>0 and p.completed.feed>0 and p.completed.dog>0,vid+" real city arrivals complete all park activities")
  check(j.completed.business+j.completed.taxi+j.completed.shuttle>0,vid+" park visitors leave for real destinations")
  check(p.invalid_steps==0 and p.failed_routes==0,vid+" all park routes remain coherent")
 f.free();print("PUBLIC_CITY_JOURNEYS failures=",failures);quit(1 if failures else 0)
