extends SceneTree
## Keep the real upgrade sheets alive through each graduation, then buy through
## their buttons. A fresh GameState-only test cannot detect stale UI venue ids.
var failures := 0
func check(ok: bool, message: String) -> void:
 if not ok:failures += 1
 print("PASS " if ok else "FAIL ",message)
func _initialize() -> void:call_deferred("run")
func run() -> void:
 var gs: Node = root.get_node("GameState")
 var dl: Node = root.get_node("DataLoader")
 var ec: Node = root.get_node("Economy")
 root.get_node("SaveSystem").set_process(false)
 ec.set_process(false)
 gs.reset_to_new_game();gs.ready_flag=true
 var ps: GDScript = load("res://scripts/meta/prestige_system.gd")
 # This suite drives the 2D floor's internals; the 3D floor has test_floor_3d.
 (load("res://scenes/venue/venue_view.gd") as GDScript).set("use_3d", false)
 var view: Control = load("res://scenes/venue/venue_view.tscn").instantiate()
 view.size=Vector2(720,980);root.add_child(view)
 await process_frame
 var order: Array = dl.venue_order()
 for hop in range(order.size()-1):
  var old: String = gs.current_venue
  var cap: int = ec.track_max_level(old,"speed")
  var ids: Array = []
  for ms in dl.milestones.get(old,[]):ids.append(str(ms["id"]))
  gs.venue_state(old)["milestones"]=ids
  for dept in ["ticket","gallery","archive","promotions"]:
   gs.set_dept_level(old,dept,"staff",8)
   gs.set_dept_level(old,dept,"speed",cap)
   gs.set_dept_level(old,dept,"value",cap)
   if gs.dept_items(old,dept).is_empty():gs.add_dept_item(old,dept)
   gs.set_item_level(old,dept,0,ec.item_max_level())
   view._open_item_sheet(dept,0)
  view._poll_rates() # Include transitions from a full bank to a smaller one.
  var old_chips: Array = view._floor._station_chips.duplicate()
  gs.cash=BigNumber.from_parts(1.0,200)
  check(ps.graduate(),"graduation succeeds from "+old)
  var next: String = gs.current_venue
  for chip in old_chips:check(not chip.is_inside_tree(),next+" retires the previous station controls before laying out the new bank")
  for dept in ["ticket","gallery","archive","promotions"]:
   view._open_sheet(dept)
   var panel: Node = view._panels[dept]
   if gs.dept_items(next,dept).is_empty():
    panel._row_btn["staff"].pressed.emit()
    check(gs.dept_items(next,dept).size()==1,next+" "+dept+" hires its first unit through the new panel")
   view._open_item_sheet(dept,0)
   check(panel.venue_id==next,next+" "+dept+" sheet targets new venue")
   check(not panel._item_btn.disabled,next+" "+dept+" fresh item is upgradeable")
   panel._item_btn.pressed.emit()
   check(gs.item_level(next,dept,0)==2,next+" "+dept+" actual button upgrades new item")
   panel._row_btn["speed"].pressed.emit()
   check(gs.dept_level(next,dept,"speed")==2,next+" "+dept+" actual button upgrades new track")
   check(gs.item_level(old,dept,0)==ec.item_max_level() and gs.dept_level(old,dept,"speed")==cap,old+" frozen build preserved")
  await process_frame
  if failures>0:break
 view.queue_free()
 await process_frame
 print("station graduation: %d failure(s)" % failures)
 quit(0 if failures==0 else 1)
