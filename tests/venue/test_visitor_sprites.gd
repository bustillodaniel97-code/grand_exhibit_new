extends SceneTree
const Roster := preload("res://scripts/characters/npc_roster.gd")
const Sprites := preload("res://scripts/characters/visitor_sprites.gd")
const Character := preload("res://scenes/venue/floor/character.gd")
var failures := 0
func check(ok: bool,label: String) -> void:
 if not ok:failures+=1;printerr("FAIL: ",label)
 else:print("PASS: ",label)
func _initialize() -> void:call_deferred("run")
func run() -> void:
 var looks := {}
 for slot in range(24):
  var frames: Array=Sprites.frames(Roster.visitor(slot))
  check(frames.size()==9,"slot %d has walk and seated assets" % slot)
  if frames.size()!=9:continue
  looks[hash(frames[0].get_image().get_data())]=true
  check(frames[0].get_image().get_data()!=frames[8].get_image().get_data(),"slot %d seated pose differs" % slot)
 check(looks.size()==24,"24 visually distinct visitor looks")
 check(Sprites.frames(Roster.employee("ticket",0)).is_empty(),"staff cannot load visitor textures")
 var c:=Character.new();c.set_look_slot(0)
 check(c._approved_seated!=null and c._frames.size()==c._motion_set.walk_frames,"character selects the approved render path")
 check(is_equal_approx(c.age_scale(),.9),"child scale accounts for the already-shorter mesh")
 c.set_uniform(Color.BLUE,0,"ticket")
 check(c.actor_role=="visitor","sprite integration preserves role guard")
 c.free()
 print("Visitor sprite failures: ",failures)
 quit(1 if failures else 0)
