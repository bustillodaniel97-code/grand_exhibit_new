extends "res://tools/world_edges_campaign.gd"
const Iso:=preload("res://scenes/venue/floor/iso.gd")
const Walls:=preload("res://scenes/venue/floor/wall_occlusion.gd")
const Character:=preload("res://scenes/venue/floor/character.gd")
class FixtureTheme extends RefCounted:
 var id:="cloudrest"
 var walls: Array=[]
 # Intentionally put a raised wall on a boundary whose neighboring room is
 # ground level: the wall's explicit storey must control both lift and depth.
 func level_at(_at: Vector2)->int:return 0
 func lift_at(_at: Vector2)->float:return 0.0
func run() -> void:
 output=OS.get_cmdline_user_args()[0];DirAccess.make_dir_recursive_absolute(output)
 root.get_node("SaveSystem").set_process(false)
 vp=SubViewport.new();vp.size=Vector2i(640,480);vp.transparent_bg=true
 vp.render_target_update_mode=SubViewport.UPDATE_ALWAYS;root.add_child(vp)
 var canvas:=Node2D.new();canvas.y_sort_enabled=true;vp.add_child(canvas)
 var c:=Character.new();c.set_uniform(Color.WHITE,0,"porter");c.with_cart=true;c.carry_stack=3;c.set_process(false)
 canvas.add_child(c)
 var nodes: Array[Node2D]=[]
 var records: Array=[]
 for level in [0,1]:
  canvas.scale=Vector2.ONE*2.3
  canvas.position=Vector2(320,300)-(Iso.to_screen(Vector2(4,4))+Vector2(0,Iso.level_lift(level)))*2.3
  for axis in ["x","y"]:
   var theme:=FixtureTheme.new()
   theme.walls=[{"at":[2,4] if axis=="x" else [4,2],"len":4,"axis":axis,"h":52,"col":"#788E81","level":level,"occludes":true}]
   Walls.rebuild(canvas,theme,nodes)
   c.set_motion_vector(Vector2.RIGHT if axis=="x" else Vector2.DOWN,0)
   for side in ["behind","front"]:
    var delta:= -1.0 if side=="behind" else 1.0
    var point:=Vector2(4,4)+ (Vector2(0,delta) if axis=="x" else Vector2(delta,0))
    c.position=Iso.to_screen(point)+Vector2(0,Iso.level_lift(level));c.z_index=level*Iso.LEVEL_Z
    var name:="%s-%s-level%d"%[axis,side,level]
    c.visible=true
    for n in nodes:n.visible=true
    await capture(output+"/"+name+"-combined.png")
    c.visible=false;await capture(output+"/"+name+"-wall.png")
    c.visible=true
    for n in nodes:n.visible=false
    await capture(output+"/"+name+"-actor.png")
    records.append({"name":name,"side":side,"axis":axis,"level":level,"position":str(point)})
 Walls.clear(nodes)
 var file:=FileAccess.open(output+"/cases.json",FileAccess.WRITE);file.store_string(JSON.stringify(records,"\t"));file.close()
 print("WALL_OCCLUSION_CAPTURE 8 actual loaded porter cases, front/back, both wall axes, ground/raised boundary");quit(0)
