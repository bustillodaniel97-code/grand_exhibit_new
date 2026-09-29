extends "res://tools/world_edges_campaign.gd"
func run() -> void:
 output=OS.get_cmdline_user_args()[0];DirAccess.make_dir_recursive_absolute(output)
 root.get_node("SaveSystem").set_process(false)
 var gs: Node=root.get_node("GameState");gs.reset_to_new_game();seed(817)
 vp=SubViewport.new();vp.size=Vector2i(720,1280);vp.render_target_update_mode=SubViewport.UPDATE_ALWAYS
 root.add_child(vp);vp.add_child(load("res://scenes/main.tscn").instantiate());await create_timer(2).timeout
 for i in 4:load("res://scripts/ui/popup_manager.gd").close_top()
 var floor_node: Node=find_floor(vp)
 for node in root.get_children():
  if node!=vp:node.process_mode=Node.PROCESS_MODE_DISABLED
 vp.get_child(0).process_mode=Node.PROCESS_MODE_DISABLED
 for vid in root.get_node("DataLoader").venue_order():
  gs.current_venue=vid
  for dept in ["ticket","archive","promotions","gallery"]:
   for track in ["staff","speed","value"]:gs.set_dept_level(vid,dept,track,8)
  floor_node.retheme(vid);floor_node.set_rates(root.get_node("Economy").venue_rates(vid))
  floor_node._user_zoom=1.0;floor_node._fit_canvas()
  await capture(output+"/"+str(vid)+".png")
  print("WALL_CAMPAIGN ",vid)
 quit(0)
