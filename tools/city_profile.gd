extends SceneTree
## Desktop-only comparison of the district and retained legacy backdrop in one scene.
var vp: SubViewport
func _initialize() -> void:call_deferred("run")
func find_floor(n: Node) -> Node:
 if n.name=="VenueFloor":return n
 for c in n.get_children():
  var found:=find_floor(c)
  if found!=null:return found
 return null
func sample() -> Dictionary:
 var calls: Array=[];var times: Array=[];var objects: Array=[]
 for i in range(120):
  await process_frame
  calls.append(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
  times.append(Performance.get_monitor(Performance.TIME_PROCESS)*1000)
  objects.append(Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME))
 calls.sort();times.sort();objects.sort()
 return {"frames":120,"median_draw_calls":calls[60],"median_process_ms":times[60],"median_render_objects":objects[60]}
func run() -> void:
 root.get_node("SaveSystem").set_process(false)
 var gs: Node=root.get_node("GameState");gs.reset_to_new_game()
 vp=SubViewport.new();vp.size=Vector2i(720,1280);vp.render_target_update_mode=SubViewport.UPDATE_ALWAYS
 vp.msaa_2d=ProjectSettings.get_setting("rendering/anti_aliasing/quality/msaa_2d",0) as Viewport.MSAA
 root.add_child(vp);vp.add_child(load("res://scenes/main.tscn").instantiate())
 await create_timer(2).timeout
 for i in range(4):load("res://scripts/ui/popup_manager.gd").close_top()
 var floor_node: Node=find_floor(vp)
 for dept in ["ticket","archive","promotions","gallery"]:
  for track in ["staff","speed","value"]:gs.set_dept_level(gs.current_venue,dept,track,8)
 floor_node.set_rates(root.get_node("Economy").venue_rates(gs.current_venue));floor_node.advance_sim(45)
 # Same museum population/layout for both snapshots. This isolates backdrop
 # rendering more closely, but is deliberately not an end-to-end device test.
 floor_node.time_scale=0
 await create_timer(1).timeout
 var current:=await sample()
 floor_node._city.venue_id=""
 floor_node._city._pal=floor_node._city.palette_for(floor_node._city.style)
 floor_node._city.queue_redraw()
 await create_timer(1).timeout
 var legacy:=await sample()
 print("CITY_PROFILE ",JSON.stringify({"venue":"whispering_pines","district":current,"legacy_backdrop":legacy,"scope":"desktop renderer; museum simulation frozen; not Android performance"}))
 quit(0)
