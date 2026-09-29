extends "res://tools/walking_campaign_review.gd"
func run() -> void:
 output=OS.get_cmdline_user_args()[0];DirAccess.make_dir_recursive_absolute(output)
 root.get_node("SaveSystem").set_process(false)
 var gs: Node=root.get_node("GameState");gs.reset_to_new_game();seed(817)
 vp=SubViewport.new();vp.size=Vector2i(720,1280);vp.render_target_update_mode=SubViewport.UPDATE_ALWAYS
 root.add_child(vp);vp.add_child(load("res://scenes/main.tscn").instantiate());await create_timer(2).timeout
 for i in 4:load("res://scripts/ui/popup_manager.gd").close_top()
 var f: Node=find_floor(vp)
 for n in root.get_children():
  if n!=vp:n.process_mode=Node.PROCESS_MODE_DISABLED
 vp.get_child(0).process_mode=Node.PROCESS_MODE_DISABLED
 gs.current_venue="cloudrest"
 for dept in ["ticket","gallery","promotions"]:
  for track in ["staff","speed","value"]:gs.set_dept_level("cloudrest",dept,track,8)
 gs.set_dept_level("cloudrest","archive","staff",1)
 f.retheme("cloudrest");f.set_rates(root.get_node("Economy").venue_rates("cloudrest"));f._stacks.fill(1)
 var p: Variant=f._porters[0];var found:=false
 for tick in 18000:
  f._update_porters(1.0/60.0);update_characters(vp,1.0/60.0)
  if not p.motion_step.is_empty() and p.motion_step.turn and p.route_cursor>3:found=true;break
 if not found:printerr("FAIL no live steering sequence");quit(1);return
 f._user_zoom=2.8;f._fit_canvas()
 var point: Vector2=f._lifted(p.pos)*f._canvas.scale+f._canvas.position;f._pan_camera(f.size*.5-point)
 var records: Array=[]
 for frame in 80:
  for tick in 3:f._update_porters(1.0/60.0);update_characters(vp,1.0/60.0)
  var heading: Vector2=p.heading
  if not p.motion_step.is_empty() and p.motion_step.turn:heading=p.heading.rotated(p.heading.angle_to(p.motion_step.heading)*p.turn_progress)
  var fits: bool=f._porter_layout.fits(p.pos,heading,false)
  records.append({"frame":frame,"seconds":frame*.05,"position":str(p.pos),"heading":str(heading),"state":p.state,"turning":not p.motion_step.is_empty() and bool(p.motion_step.turn),"reversing":p.node.walk_backwards,"fits":fits})
  if not fits:printerr("FAIL live cart clips geometry");quit(1);return
  await capture(output+"/frame-%03d.png"%frame)
 var file:=FileAccess.open(output+"/motion.json",FileAccess.WRITE);file.store_string(JSON.stringify(records,"\t"));file.close();print("LIVE_CART_CAPTURE 80 frames at 20 fps; one porter, default planning budget");quit(0)
