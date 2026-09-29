extends SceneTree
## Actual Character renderer, isolated by the caller. Native sprite-scale review.
const Character := preload("res://scenes/venue/floor/character.gd")
var vp: SubViewport
var out := "/tmp/grand-exhibit-cast.png"
var sequence := ""
func _initialize() -> void:
 for arg in OS.get_cmdline_user_args():
  if arg.begins_with("out="):out=arg.trim_prefix("out=")
  if arg.begins_with("sequence="):sequence=arg.trim_prefix("sequence=")
 call_deferred("run")
func label(parent: Node, text: String, at: Vector2, width: float = 152.0) -> void:
 var l:=Label.new();l.text=text;l.position=at;l.size.x=width
 l.add_theme_color_override("font_color",Color("24343a"));l.add_theme_font_size_override("font_size",13)
 parent.add_child(l)
func run() -> void:
 var ss:=root.get_node_or_null("SaveSystem")
 if ss!=null:ss.set_process(false)
 vp=SubViewport.new();vp.size=Vector2i(960,1160);vp.render_target_update_mode=SubViewport.UPDATE_ALWAYS;root.add_child(vp)
 var stage:=Node2D.new();vp.add_child(stage)
 var bg:=Polygon2D.new();bg.polygon=PackedVector2Array([Vector2.ZERO,Vector2(960,0),Vector2(960,1160),Vector2(0,1160)]);bg.color=Color("e2e6e6");stage.add_child(bg)
 label(stage,"Grand Exhibit | actual game character renderer | full cast snapshot" if sequence.is_empty() else "Grand Exhibit | actual game character renderer | choreographed bank review",Vector2(18,12),920)
 label(stage,"Visitors: 24 identities. Columns continue across age, gender and the three variants.",Vector2(18,35),920)
 for slot in range(24):
  var c:=Character.new();c.set_look_slot(slot);stage.add_child(c)
  c.position=Vector2(80+(slot%6)*160,190+(slot/6)*165);c.scale=Vector2.ONE*c.age_scale();c.walking=true
  var text: String=str(c.identity.age_group).replace("_"," ")+" / "+str(c.identity.gender)
  label(stage,text,Vector2((slot%6)*160+8,198+(slot/6)*165))
  label(stage,"variant "+str(c.identity.variant),Vector2((slot%6)*160+8,216+(slot/6)*165))
 label(stage,"Adult staff: ticket / docent / promotions / porter. Ellis has a separate host pool.",Vector2(18,756),920)
 for slot in range(12):
  var role: String=["ticket","docent","promotions","porter"][slot/3]
  var c:=Character.new();c.set_uniform(Color.BLUE,slot%3,role);stage.add_child(c)
  c.position=Vector2(80+(slot%6)*160,924+(slot/6)*165);c.scale=Vector2.ONE*c.age_scale();c.walking=true
  label(stage,role+" / "+str(c.identity.gender),Vector2((slot%6)*160+8,932+(slot/6)*165))
  label(stage,str(c.identity.age_group).replace("_"," "),Vector2((slot%6)*160+8,950+(slot/6)*165))
 await create_timer(.15).timeout
 for c in stage.get_children():
  if c is Character:c.set_process(false)
 if not sequence.is_empty():
  DirAccess.make_dir_recursive_absolute(sequence)
  var records: Array=[]
  for view in ["front","back"]:
   var heading:=Vector2.DOWN if view=="front" else Vector2.UP
   for frame in 8:
    var count:=0
    for c in stage.get_children():
     if c is Character:
      c.walking=true;c._distance_driven=true;c._cycle_phase=float(frame)/8
      c.set_motion_vector(heading,c.preferred_walk_speed());c._process(0);count+=1
    await process_frame
    await RenderingServer.frame_post_draw
    var path:=sequence.path_join("walk-%s-%d.png"%[view,frame])
    assert(vp.get_texture().get_image().save_png(path)==OK)
    records.append({"file":path,"actors":count,"kind":"walk","view":view,"frame":frame})
   for c in stage.get_children():
    if c is Character:
     c.walking=false;c._frame=-1
     if c.actor_role=="visitor":assert(c.begin_seating(heading,Vector2.ZERO))
     c._process(0)
   for frame in 9:
    var count:=0
    for c in stage.get_children():
     if c is Character and c.actor_role=="visitor":
      c.advance_seating(0 if frame==0 else .1,true);c._process(0);count+=1
    await process_frame
    await RenderingServer.frame_post_draw
    var path:=sequence.path_join("seat-%s-%d.png"%[view,frame])
    assert(vp.get_texture().get_image().save_png(path)==OK)
    records.append({"file":path,"actors":count,"kind":"seating","view":view,"frame":frame})
   for c in stage.get_children():
    if c is Character:c.end_seating()
  var file:=FileAccess.open(sequence.path_join("review.json"),FileAccess.WRITE)
  file.store_string(JSON.stringify({"frames":records,"scope":"36 role-bound identities through actual Character drawing. 576 walking actor poses and 432 seating actor poses; choreographed playback, no navigation or physical-bench claim."},"\t"));file.close()
  print("CAST_SEQUENCE_COMPLETE ",records.size())
  quit(0);return
 await RenderingServer.frame_post_draw
 var err:=vp.get_texture().get_image().save_png(out)
 print("CAST_CAPTURE ",out," error=",err)
 quit(0 if err==OK else 1)
