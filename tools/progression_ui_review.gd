extends SceneTree
var output: String
var failures:=0
var popups: GDScript
func _initialize() -> void:call_deferred("run")
func check(ok: bool,label: String) -> void:
 if not ok:failures+=1;printerr("FAIL: ",label)
func find_script(n: Node,path: String) -> Node:
 if n.get_script()!=null and n.get_script().resource_path==path:return n
 for child in n.get_children():
  var found:=find_script(child,path)
  if found!=null:return found
 return null
func settle() -> void:await create_timer(.3).timeout
func snap(name: String) -> void:
 await RenderingServer.frame_post_draw
 root.get_texture().get_image().save_png(output+"/"+name+".png")
func run() -> void:
 if OS.get_environment("GRAND_EXHIBIT_TEST_RUN")!="1":quit(2);return
 output=OS.get_cmdline_user_args()[0];DirAccess.make_dir_recursive_absolute(output)
 root.size=Vector2i(720,1280);root.content_scale_size=root.size
 var gs: Node=root.get_node("GameState");var dl: Node=root.get_node("DataLoader");var saves: Node=root.get_node("SaveSystem")
 saves.set_process(false);gs.reset_to_new_game();gs.ready_flag=true;gs.cash=BigNumber.from_parts(9.99,300)
 gs.reputation_xp=BigNumber.from_float(100000)
 saves.save_now()
 var main=load("res://scenes/main.tscn").instantiate();root.add_child(main);await create_timer(1).timeout
 popups=load("res://scripts/ui/popup_manager.gd")
 while popups.is_open():popups.close_top();await settle()
 var ps=load("res://scripts/meta/prestige_system.gd");var ds=load("res://scripts/meta/decor_system.gd")
 var vid: String=gs.current_venue
 for ms in dl.milestones[vid]:
  if ms.id not in gs.venue_state(vid).milestones:gs.venue_state(vid).milestones.append(ms.id)
 for track in ps.core_tracks():gs.set_dept_level(vid,track[0],track[1],int(dl.get_venue(vid).track_level_cap))
 gs.venue_state(vid).active_quests=[]
 var view=main.find_child("VenueView",true,false)
 view._open_sheet("ticket");await settle()
 var panel: Node=view._panels.ticket
 panel._decor_tab.pressed.emit();await settle();check(panel._decor_view.visible,"decor tab inside department")
 await snap("department-decor")
 panel._manager_tab.pressed.emit();await settle();check(panel._manager_view.visible,"manager tab still works");await snap("department-managers")
 view._close_sheet();await settle()
 popups.open("res://scenes/meta/prestige_screen.tscn");await settle();await snap("completion-blocked")
 check(not ps.can_graduate(),"no decor cannot complete")
 popups.close_top();popups.open("res://scenes/meta/decor_screen.tscn");await settle();await snap("decor-target")
 var shop=find_script(main,"res://scenes/meta/decor_screen.gd")
 shop._on_buy("oak_bench");await settle();check(not popups.is_open(),"purchase reveals museum")
 await snap("decor-installed")
 for did in ["heritage_arch","velvet_rope"]:ds.buy_decor(vid,did)
 check(ps.can_graduate(),"cash decor satisfies gate")
 await settle();await snap("furnished-ready")
 var ms=load("res://scripts/managers/manager_system.gd");var econ: Node=root.get_node("Economy")
 var before: float=econ.dept_stat(vid,"promotions","speed")
 ms.add_cards("barker_theo",1);check(ms.assign("barker_theo","promotions"),"manager assigns")
 var after: float=econ.dept_stat(vid,"promotions","speed")
 check(after>before,"assigned manager raises real department stat")
 FileAccess.open(output+"/review.json",FileAccess.WRITE).store_string(JSON.stringify({"failures":failures,"manager_speed_before":before,"manager_speed_after":after,"decor":ps.decor_summary(vid)},"\t"))
 print("PROGRESSION_UI failures=",failures);quit(0 if failures==0 else 1)
