extends SceneTree
## Run twelve fresh processes with the SAME disposable XDG_DATA_HOME:
## --script res://tests/venue/test_graduation_reopen.gd -- 0 (then 1 through 11).
## Each process reloads the previous process's save, buys through new UI, then
## graduates with existing UI alive. Never uses or resets the player profile.
var failures := 0
const DEPARTMENTS := ["ticket", "gallery", "archive", "promotions"]
func check(ok: bool, message: String) -> void:
 if not ok: failures += 1
 print("PASS " if ok else "FAIL ", message)
func _initialize() -> void: call_deferred("run")
func run() -> void:
 var args := OS.get_cmdline_user_args()
 if args.is_empty():
  run_processes();return
 if args.size()!=1 or not args[0].is_valid_int():
  printerr("FAIL expected process index 0 through 11");quit(2);return
 var hop := int(args[0])
 var gs: Node = root.get_node("GameState")
 var ss: Node = root.get_node("SaveSystem")
 var ec: Node = root.get_node("Economy")
 var dl: Node = root.get_node("DataLoader")
 ss.set_process(false);ec.set_process(false)
 var order: Array = dl.venue_order()
 if hop<0 or hop>=order.size():quit(2);return
 if hop==0:
  check(not ss.has_save(), "initial process requires an empty disposable profile")
  gs.reset_to_new_game()
 else:
  check(ss.load_game(), "fresh process loads previous graduation save")
 gs.ready_flag=true
 check(gs.current_venue==order[hop], "reopened game selects expected museum")
 if failures>0:quit(1);return
 var view: Control = load("res://scenes/venue/venue_view.tscn").instantiate()
 view.size=Vector2(720,980);root.add_child(view)
 await process_frame
 var current: String = gs.current_venue
 for earlier in range(hop):
  var old: String = order[earlier]
  check(gs.venue_is_closed(old), old+" stays closed after reopening")
  for dept in DEPARTMENTS:
   check(gs.item_level(old,dept,0)==ec.item_max_level() and gs.dept_level(old,dept,"speed")==ec.track_max_level(old,"speed"), old+" "+dept+" retains completed upgrades")
 if hop>0:
  for dept in DEPARTMENTS:
   check(gs.item_level(current,dept,0)==2 and gs.dept_level(current,dept,"speed")==2, current+" "+dept+" saves only its own purchased levels")
   view._open_item_sheet(dept,0)
   var panel: Node = view._panels[dept]
   check(panel.venue_id==current and not panel._item_btn.disabled, current+" "+dept+" reopens an upgradeable station")
   panel._item_btn.pressed.emit();panel._row_btn["speed"].pressed.emit()
   check(gs.item_level(current,dept,0)==3 and gs.dept_level(current,dept,"speed")==3, current+" "+dept+" accepts purchases after a process restart")
 if hop<order.size()-1:
  var ids: Array = []
  for milestone in dl.milestones.get(current,[]):ids.append(str(milestone["id"]))
  gs.venue_state(current)["milestones"]=ids
  for dept in DEPARTMENTS:
   for track in ["staff","speed","value"]:gs.set_dept_level(current,dept,track,8 if track=="staff" else ec.track_max_level(current,track))
   if gs.dept_items(current,dept).is_empty():gs.add_dept_item(current,dept)
   gs.set_item_level(current,dept,0,ec.item_max_level())
   view._open_item_sheet(dept,0)
  gs.cash=BigNumber.from_parts(1.0,200)
  furnish(gs,dl,gs.current_venue)
  check(load("res://scripts/meta/prestige_system.gd").graduate(), current+" graduates with cached panels alive")
  var next: String = gs.current_venue
  for dept in DEPARTMENTS:
   view._open_sheet(dept)
   var panel: Node = view._panels[dept]
   if gs.dept_items(next,dept).is_empty():panel._row_btn["staff"].pressed.emit()
   view._open_item_sheet(dept,0)
   check(panel.venue_id==next and not panel._item_btn.disabled, next+" "+dept+" targets a fresh station")
   panel._item_btn.pressed.emit();panel._row_btn["speed"].pressed.emit()
   check(gs.item_level(next,dept,0)==2 and gs.dept_level(next,dept,"speed")==2, next+" "+dept+" upgrades independently before saving")
  check(ss.save_now(), "graduation and purchases persist to disk")
 view.queue_free();await process_frame
 print("graduation reopen process %d: %d failure(s)" % [hop,failures])
 quit(0 if failures==0 else 1)

func run_processes() -> void:
 # Ordinary suite invocation creates a private profile shared only by these
 # child processes. Children inherit the test isolation flag explicitly.
 var previous_xdg := OS.get_environment("XDG_DATA_HOME")
 var previous_test := OS.get_environment("GRAND_EXHIBIT_TEST_RUN")
 var scratch := ProjectSettings.globalize_path("user://test_run/graduation-reopen-%d" % Time.get_ticks_usec())
 DirAccess.make_dir_recursive_absolute(scratch)
 OS.set_environment("XDG_DATA_HOME",scratch)
 OS.set_environment("GRAND_EXHIBIT_TEST_RUN","1")
 for hop in root.get_node("DataLoader").venue_order().size():
  var output: Array = []
  var code := OS.execute(OS.get_executable_path(),["--headless","--audio-driver","Dummy","--path",ProjectSettings.globalize_path("res://"),"--script",get_script().resource_path,"--",str(hop)],output,true)
  var log := "\n".join(output)
  print(log)
  check(code==0 and not "SCRIPT ERROR" in log and not "FAIL " in log,"fresh process %d completes" % hop)
  if failures>0:break
 if previous_xdg.is_empty():OS.unset_environment("XDG_DATA_HOME")
 else:OS.set_environment("XDG_DATA_HOME",previous_xdg)
 if previous_test.is_empty():OS.unset_environment("GRAND_EXHIBIT_TEST_RUN")
 else:OS.set_environment("GRAND_EXHIBIT_TEST_RUN",previous_test)
 print("graduation reopen campaign: %d failure(s)" % failures)
 quit(0 if failures==0 else 1)

## The graduation gate also asks for a furnished museum; stand up the richest
## pieces through the real shop path until it is met.
func furnish(gs: Node, dl: Node, vid: String) -> void:
 var ps: GDScript = load("res://scripts/meta/prestige_system.gd")
 var ds: GDScript = load("res://scripts/meta/decor_system.gd")
 gs.gems = 1 << 30
 var ids: Array = dl.decor.keys()
 ids.sort_custom(func(a, b) -> bool: return ds.piece_decor_points(a) > ds.piece_decor_points(b))
 for id in ids:
  if ps.decor_met(vid):break
  ds.buy_decor(vid, id)
