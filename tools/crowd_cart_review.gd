extends "res://tools/walking_campaign_review.gd"
const CartGeometry:=preload("res://scenes/venue/floor/cart_traffic_geometry.gd")
func run() -> void:
 var args:=OS.get_cmdline_user_args();output=args[0];DirAccess.make_dir_recursive_absolute(output)
 root.get_node("SaveSystem").set_process(false)
 var gs: Node=root.get_node("GameState");gs.reset_to_new_game()
 vp=SubViewport.new();vp.size=Vector2i(720,1280);vp.render_target_update_mode=SubViewport.UPDATE_ALWAYS
 root.add_child(vp);vp.add_child(load("res://scenes/main.tscn").instantiate());await create_timer(2).timeout
 for i in 4:load("res://scripts/ui/popup_manager.gd").close_top()
 var f: Node=find_floor(vp)
 for n in root.get_children():
  if n!=vp:n.process_mode=Node.PROCESS_MODE_DISABLED
 vp.get_child(0).process_mode=Node.PROCESS_MODE_DISABLED
 gs.current_venue=args[1] if args.size()>1 else "cloudrest"
 for dept in ["ticket","archive","gallery","promotions"]:
  for track in ["staff","speed","value"]:gs.set_dept_level(gs.current_venue,dept,track,8)
 f.retheme(gs.current_venue);f.set_rates(root.get_node("Economy").venue_rates(gs.current_venue));seed(918)
 var warm:=float(args[2]) if args.size()>2 else 60.0
 for tick in int(warm*60):f.advance_sim(1.0/60.0)
 update_characters(vp,0)
 f._user_zoom=1.0;f._fit_canvas();await capture(output+"/overview.png")
 var focus: Vector2=f._porters[0].pos;var longest:=0.0
 for v in f._visitors:
  if v.cart_wait>longest:longest=v.cart_wait;focus=v.pos
 f._user_zoom=2.0;f._fit_canvas()
 var point: Vector2=f._lifted(focus)*f._canvas.scale+f._canvas.position;f._pan_camera(f.size*.5-point)
 var records: Array=[]
 for frame in 100:
  for tick in 3:f.advance_sim(1.0/60.0);update_characters(vp,1.0/60.0)
  var actors: Array=[];var collisions:=0
  for p in f._porters:
   actors.append({"at":str(p.pos),"state":p.state,"walking":p.node.walking})
   for v in f._visitors+f._rejected:
    if absf(f._theme.lift_at(v.pos)-f._theme.lift_at(p.pos))>=73:continue
    if CartGeometry.point_distance(v.pos,p.pos,CartGeometry.heading(p))<.22:collisions+=1
  records.append({"frame":frame,"porters":actors,"cart_visitor_overlaps":collisions,"deposits":f._porter_trips})
  await capture(output+"/frame-%03d.png"%frame)
 var file:=FileAccess.open(output+"/motion.json",FileAccess.WRITE);file.store_string(JSON.stringify(records,"\t"));file.close()
 print("CROWD_CART_CAPTURE 100 frames with live guests and default planning budget");quit(0)
