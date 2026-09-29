extends "res://tools/world_edges_campaign.gd"
## Visual evidence only: early and funded/busy states of every authored museum.
## Independent saves required; this is not normal-player balance validation.
func run() -> void:
 output=OS.get_cmdline_user_args()[0]
 DirAccess.make_dir_recursive_absolute(output)
 root.get_node("SaveSystem").set_process(false)
 var gs: Node=root.get_node("GameState")
 gs.reset_to_new_game();seed(917)
 vp=SubViewport.new();vp.size=Vector2i(720,1280)
 vp.render_target_update_mode=SubViewport.UPDATE_ALWAYS
 root.add_child(vp);vp.add_child(load("res://scenes/main.tscn").instantiate())
 await create_timer(2).timeout
 for i in 4:load("res://scripts/ui/popup_manager.gd").close_top()
 var floor_node: Node=find_floor(vp)
 for node in root.get_children():
  if node!=vp:node.process_mode=Node.PROCESS_MODE_DISABLED
 vp.get_child(0).process_mode=Node.PROCESS_MODE_DISABLED
 var records: Array=[]
 for vid in root.get_node("DataLoader").venue_order():
  gs.current_venue=vid
  floor_node.retheme(vid)
  floor_node.set_rates(root.get_node("Economy").venue_rates(vid))
  floor_node._user_zoom=1.0;floor_node._fit_canvas()
  refresh_frozen_view(vp)
  await capture(output+"/"+vid+"-early.png")
  for dept in ["ticket","archive","promotions","gallery"]:
   for track in ["staff","speed","value"]:gs.set_dept_level(vid,dept,track,8)
  floor_node.set_rates(root.get_node("Economy").venue_rates(vid))
  floor_node.advance_sim(75)
  floor_node._fit_canvas()
  refresh_frozen_view(vp)
  await capture(output+"/"+vid+"-busy.png")
  records.append({"venue":vid,"visitors":floor_node._visitors.size(),"porter_trips":floor_node._porter_trips,"simulation_seconds":75})
  print("LAYOUT_CAPTURE ",vid)
 var file:=FileAccess.open(output+"/capture-manifest.json",FileAccess.WRITE)
 file.store_string(JSON.stringify(records,"\t"));file.close()
 quit(0)

func refresh_frozen_view(node: Node) -> void:
 var script: Script=node.get_script()
 if script!=null and script.resource_path in ["res://scenes/ui/hud.gd","res://scenes/meta/quests_bar.gd"]:node.refresh()
 if script!=null and script.resource_path=="res://scenes/venue/floor/character.gd":node._process(0)
 for child in node.get_children():refresh_frozen_view(child)
