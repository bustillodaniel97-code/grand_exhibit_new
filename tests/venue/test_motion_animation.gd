extends SceneTree
const Roster:=preload("res://scripts/characters/npc_roster.gd")
const Motion:=preload("res://scripts/characters/motion_sprites.gd")
const Character:=preload("res://scenes/venue/floor/character.gd")
var failures:=0
func check(ok: bool,label: String) -> void:
 if not ok:failures+=1;printerr("FAIL: ",label)
func _initialize() -> void:call_deferred("run")
func run() -> void:
 var ids: Array=[]
 for i in range(24):ids.append(Roster.visitor(i))
 for role in ["ticket","docent","promotions","porter"]:
  for i in range(3):ids.append(Roster.employee(role,i))
 for identity in ids:
  var packet:=Motion.get_set(identity)
  check(not packet.is_empty(),"directional packet exists for "+str(identity.id))
  if packet.is_empty():continue
  check(packet.front.size()==packet.walk_frames and packet.back.size()==packet.walk_frames,"complete walk cycles")
  check(packet.front[0].get_size()==Vector2(192,288),"front trimmed margin restores master canvas")
  check(packet.back[0].get_size()==Vector2(144,216),"back trimmed margin restores master canvas")
  check(packet.front[0].get_image().get_data()!=packet.back[0].get_image().get_data(),"back is a distinct render")
  check(packet.idle_front.get_image().get_data()!=packet.front[0].get_image().get_data(),"dedicated planted idle pose")
  check(float(packet.stride_grid)>.3 and float(packet.stride_grid)<.8,"bounded rig stride")
 var fake:=Roster.employee("ticket",0);fake.gender="female"
 check(Motion.get_set(fake).is_empty(),"warm cache rejects mismatched staff identity")
 check(Motion.get_set(Roster.RESERVED_HOST).is_empty(),"host excluded from motion pool")
 var c:=Character.new();c.set_look_slot(2);root.add_child(c);c.set_process(false)
 c.walking=true;c.set_motion_vector(Vector2(1,0),c.preferred_walk_speed(2.0));c._process(.0625)
 check(not c._view_back and c.facing==1 and c.scale.x<0,"toward-camera right uses front and correct mirror")
 check(c._frame==Motion.phase_frame(.125,c._walk_frame_count()),"cadence follows distance per stride")
 c.set_motion_vector(Vector2(-1,0),c.preferred_walk_speed(2.0));c._process(0)
 check(c._view_back and c.facing==-1 and c.scale.x<0,"away left uses the back view")
 c.set_motion_vector(Vector2(0,-1),c.preferred_walk_speed());c._process(0)
 check(c._view_back and c.facing==1 and c.scale.x>0,"away right uses unmirrored back")
 c.set_motion_vector(Vector2(0,1),c.preferred_walk_speed());c._process(0)
 check(not c._view_back and c.facing==-1 and c.scale.x>0,"toward left uses unmirrored front")
 c.set_motion_vector(Vector2(-1,0),c.preferred_walk_speed());c._process(0)
 var frame:=c._frame
 c.set_motion_vector(Vector2.ZERO,0);c._process(0)
 check(c._view_back and c.facing==-1 and c._frame==frame,"zero displacement does not flip or advance")
 c.walking=false;var phase:=c._cycle_phase;c._process(Character.STOP_DEBOUNCE*.5)
 check(c._frame==frame and is_equal_approx(c._cycle_phase,phase),"short block holds the current gait without advancing")
 c._process(Character.STOP_DEBOUNCE)
 check(c._frame==-1 and is_equal_approx(c._cycle_phase,phase),"bounded stop settles to rest art without changing phase")
 c.free()
 var manifest: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://art/npc_motion/motion.json"))
 var expected_textures:=0
 for raw in manifest.sets.values():
  expected_textures+=Motion.walk_frame_count(raw)*2+2+(1 if raw.has("seated") else 0)
 check(int(manifest.budget.textures)==expected_textures,"complete legacy view and seated art budget")
 check(int(manifest.budget.decoded_mip_bytes)<=64*1024*1024,"cropped legacy-view set stays within 64 MiB decoded budget")
 print("Motion animation failures: ",failures)
 quit(1 if failures else 0)
