extends SceneTree
## Reproducible native Character motion preview; caller must isolate user data.
const Character:=preload("res://scenes/venue/floor/character.gd")
var vp: SubViewport
var out:="/tmp/grand-exhibit-motion"
var actors: Array=[]
var gameplay:=false
func _initialize() -> void:
 for arg in OS.get_cmdline_user_args():
  if arg.begins_with("out="):out=arg.trim_prefix("out=")
  if arg=="pace=gameplay":gameplay=true
 call_deferred("run")
func label(parent: Node,text: String,at: Vector2) -> void:
 var l:=Label.new();l.text=text;l.position=at;l.add_theme_font_size_override("font_size",16);l.add_theme_color_override("font_color",Color("213640"));parent.add_child(l)
func run() -> void:
 var ss:=root.get_node_or_null("SaveSystem")
 if ss!=null:ss.set_process(false)
 DirAccess.make_dir_recursive_absolute(out)
 vp=SubViewport.new();vp.size=Vector2i(720,680);vp.render_target_update_mode=SubViewport.UPDATE_ALWAYS
 vp.msaa_2d=ProjectSettings.get_setting("rendering/anti_aliasing/quality/msaa_2d",0) as Viewport.MSAA
 root.add_child(vp)
 var stage:=Node2D.new();vp.add_child(stage)
 var bg:=Polygon2D.new();bg.polygon=PackedVector2Array([Vector2.ZERO,Vector2(720,0),Vector2(720,680),Vector2(0,680)]);bg.color=Color("dce4e5");stage.add_child(bg)
 label(stage,"Grand Exhibit | actual game renderer | 2x character view",Vector2(20,16))
 label(stage,"Gameplay travel pace: toward camera, pause, turn away" if gameplay else "Public plaza pace: toward camera, pause, turn away",Vector2(20,42))
 var slots:=[2,9,23,18]
 for i in range(4):
  var origin:=Vector2(210+(i%2)*330,245+(i/2)*255)
  var c:=Character.new();c.set_look_slot(slots[i]);stage.add_child(c);c.set_process(false);c.scale=Vector2.ONE*c.age_scale()*2
  c.position=origin;c.walking=false;c._process(0)
  actors.append({"node":c,"origin":origin,"distance":0.0})
  label(stage,str(c.identity.age_group).replace("_"," ")+" / "+str(c.identity.gender),Vector2(24+(i%2)*340,316+(i/2)*255))
  for j in range(-2,3):
   var line:=Line2D.new();line.width=1;line.default_color=Color("b8cace");line.add_point(origin+Vector2(-120,j*20));line.add_point(origin+Vector2(90,j*20));stage.add_child(line);stage.move_child(line,1)
 var fps:=24.0
 for frame in range(120):
  var t:=fposmod(frame/fps,2.5)
  var direction:=Vector2(0,1) if t<1 else Vector2(0,-1)
  var walking:=t<.75 or (t>=1.25 and t<2.0)
  for a in actors:
   var c: Node2D=a.node
   var speed: float=2.1 if gameplay else c.preferred_walk_speed(1.6)
   if walking:
    a.distance+=speed/fps*(1 if direction.y>0 else -1)
    c.set_motion_vector(direction,speed)
   c.walking=walking;c._process(1/fps)
   c.position=a.origin+Vector2(-30,20)*float(a.distance)*2
  await RenderingServer.frame_post_draw
  var err:=vp.get_texture().get_image().save_png(out.path_join("frame-%03d.png"%frame))
  if err!=OK:printerr("MOTION_CAPTURE_ERROR ",err);quit(1);return
 print("MOTION_CAPTURE ",out," frames=120 fps=24")
 quit(0)
