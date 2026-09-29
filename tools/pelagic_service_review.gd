extends "res://tools/walking_campaign_review.gd"
const Geometry:=preload("res://scenes/venue/floor/cart_traffic_geometry.gd")
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
 gs.current_venue="pelagic_crown"
 for dept in ["ticket","archive","gallery","promotions"]:
  for track in ["staff","speed","value"]:gs.set_dept_level(gs.current_venue,dept,track,8)
 f.retheme(gs.current_venue);f.set_rates(root.get_node("Economy").venue_rates(gs.current_venue));f._stacks.fill(2)
 var found:=false
 for tick in 18000:
  f._update_porters(1.0/60.0);update_characters(vp,1.0/60.0)
  for p in f._porters:
   if p.node.walking and p.pos.distance_to(Vector2(4.5,7))<1.5:found=true;break
  if found:break
 if not found:printerr("FAIL no porter in the reef service aisle");quit(1);return
 f._user_zoom=2.4;f._fit_canvas()
 var point: Vector2=f._lifted(Vector2(3.3,7))*f._canvas.scale+f._canvas.position;f._pan_camera(f.size*.5-point)
 var records: Array=[]
 for frame in 100:
  for tick in 3:f._update_porters(1.0/60.0);update_characters(vp,1.0/60.0)
  var poses: Array=[]
  for i in f._porters.size():
   var p: Variant=f._porters[i];var heading:=Geometry.heading(p)
   var fits: bool=f._porter_layout.fits(p.pos,heading,false)
   if not fits:printerr("FAIL cart clips fixed geometry");quit(1);return
   for j in range(i+1,f._porters.size()):
    var other: Variant=f._porters[j]
    if Geometry.overlap(p.pos,heading,other.pos,Geometry.heading(other)):printerr("FAIL carts overlap");quit(1);return
   poses.append({"at":str(p.pos),"heading":str(heading),"state":p.state,"fits":fits})
  records.append({"frame":frame,"porters":poses,"active_routes":f._cart_dispatch.leases.size()})
  await capture(output+"/frame-%03d.png"%frame)
 var file:=FileAccess.open(output+"/motion.json",FileAccess.WRITE);file.store_string(JSON.stringify(records,"\t"));file.close()
 print("PELAGIC_SERVICE_CAPTURE 100 frames, 3 real porters, default planning budget; visitors frozen");quit(0)
