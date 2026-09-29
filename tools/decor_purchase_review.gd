extends SceneTree
var output: String
var failures := 0
var receipts: Array = []
var Popups: GDScript
func _initialize() -> void: call_deferred("run")
func check(ok: bool, text: String) -> void:
 if not ok: failures += 1;printerr("FAIL ",text)
func find_script(n: Node, path: String) -> Node:
 if n.get_script()!=null and n.get_script().resource_path==path:return n
 for c in n.get_children():
  var result:=find_script(c,path)
  if result!=null:return result
 return null
func settle() -> void: await create_timer(.18).timeout
func snap(name: String) -> void:
 await RenderingServer.frame_post_draw
 check(root.get_texture().get_image().save_png(output+"/"+name+".png")==OK,"capture "+name)
func run() -> void:
 if OS.get_environment("GRAND_EXHIBIT_TEST_RUN")!="1" or OS.get_environment("XDG_DATA_HOME").is_empty():quit(2);return
 output=OS.get_cmdline_user_args()[0];DirAccess.make_dir_recursive_absolute(output)
 root.size=Vector2i(720,1280);root.content_scale_size=root.size
 root.get_node("SaveSystem").set_process(false)
 root.get_node("Economy").set_process(false)
 var gs: Node=root.get_node("GameState");var dl: Node=root.get_node("DataLoader")
 gs.reset_to_new_game();gs.ready_flag=true;gs.cash=BigNumber.from_parts(9,300);gs.gems=1000000
 gs.decor_owned=dl.decor.keys()
 Popups=load("res://scripts/ui/popup_manager.gd")
 var ds: GDScript=load("res://scripts/meta/decor_system.gd")
 var main: Node=load("res://scenes/main.tscn").instantiate();root.add_child(main)
 await create_timer(1.0).timeout
 while Popups.is_open():Popups.close_top();await settle()
 var floor_node: Control=main.find_child("VenueFloor",true,false);floor_node.set_process(false)
 var starting: bool=OS.get_cmdline_user_args().size()>1 and OS.get_cmdline_user_args()[1]=="starting"
 var venues: Array=dl.venue_order()
 if starting:venues=venues.slice(0,1)
 for vid in venues:
  gs.cash=BigNumber.from_parts(9,300);gs.gems=1000000;gs.decor_owned=dl.decor.keys()
  gs.current_venue=vid;gs.venue_state(vid)["decor"]={};gs.venue_state(vid)["decor_bought"]=[]
  for dept in ["ticket","gallery","archive","promotions"]:
   for track in ["speed","value","staff"]:gs.set_dept_level(vid,dept,track,1 if starting else int(dl.get_venue(vid).track_level_cap))
  floor_node.retheme(vid);await settle();await snap(vid+"-before")
  Popups.open("res://scenes/meta/decor_screen.tscn",{"venue_id":vid});await settle()
  var shop: Node=find_script(main,"res://scenes/meta/decor_screen.gd")
  check(shop!=null,"shop is present")
  shop._on_buy("brass_fountain");await settle()
  check(not Popups.is_open(),vid+" purchase returns to floor")
  check(floor_node._decor_anchor_by_id.has("brass_fountain"),vid+" purchase adds real prop")
  var labels:=0
  for child in floor_node._canvas.get_children():
   if child.has_meta("u") and child.get_child_count()>0:labels+=1
  check(labels>0,vid+" labelled reveal visible after popup dismissal")
  await snap(vid+"-installed")
  Popups.open("res://scenes/meta/decor_screen.tscn",{"venue_id":vid});await settle()
  shop=find_script(main,"res://scenes/meta/decor_screen.gd");shop._on_remove("brass_fountain");await settle()
  check(not floor_node._decor_anchor_by_id.has("brass_fountain"),vid+" removal removes real prop")
  check(Popups.is_open(),vid+" removal keeps shop open")
  var gems: int=gs.gems
  shop._on_place("brass_fountain");await settle()
  check(gs.gems==gems,vid+" storage replacement costs nothing")
  check(not Popups.is_open() and floor_node._decor_anchor_by_id.has("brass_fountain"),vid+" replacement closes and respawns")
  receipts.append({"venue":vid,"placed":ds.owned(vid,"brass_fountain"),"anchor":str(floor_node._decor_anchor_by_id.brass_fountain)})
 FileAccess.open(output+"/receipts.json",FileAccess.WRITE).store_string(JSON.stringify({"failures":failures,"venues":receipts}," "))
 print("DECOR_PURCHASE_REVIEW failures=",failures)
 quit(0 if failures==0 else 1)
