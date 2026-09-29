extends SceneTree
const Motion:=preload("res://scripts/characters/motion_sprites.gd")
const Roster:=preload("res://scripts/characters/npc_roster.gd")
const Character:=preload("res://scenes/venue/floor/character.gd")
var failures:=0
var checks:=0
func _initialize() -> void:call_deferred("run")
func check(ok: bool,label: String) -> void:
 checks+=1
 if not ok:failures+=1;printerr("FAIL: ",label)
func run() -> void:
 var ids: Array=[]
 for slot in 24:ids.append(Roster.visitor(slot))
 for role in ["ticket","docent","promotions","porter"]:
  for variant in 3:ids.append(Roster.employee(role,variant))
 var held: Dictionary={}
 for identity in ids:
  var packet:=Motion.get_set(identity)
  check(packet.has("directions"),"complete identity "+str(identity.id))
  if not packet.has("directions"):continue
  for heading in 8:
   var section:=Motion.direction_set(identity,heading)
   check(not section.is_empty(),"decoded heading "+str(heading))
   if section.is_empty():continue
   if held.is_empty():held=section
   check(section.walk.size()==packet.direction_walk_frames,"complete authored gait phases")
   check(section.idle.get_size()==Vector2(192,288),"fixed canvas anchor")
   check(section.has("idle_hand") and section.walk_hands.size()==section.walk.size(),"all hand anchors")
   check(section.idle_hand.is_finite(),"finite idle hand")
   for i in section.walk.size():
    check(section.walk[i].get_size()==Vector2(192,288),"phase canvas anchor")
    check(section.walk_hands[i].is_finite(),"finite phase hand")
   check(Motion._direction_cache.size()<=Motion.DIRECTION_CACHE_LIMIT,"bounded LRU on every load")
  for previous in 8:
   for heading in 8:
    check(Motion.direction_index(Vector2.RIGHT.rotated(heading*PI/4),previous)==heading,"heading independent of history")
 check(not held.is_empty() and held.idle.get_size()==Vector2(192,288),"active packet survives global eviction")
 check(Motion._direction_cache.size()==Motion.DIRECTION_CACHE_LIMIT,"all cast fills bounded cache")
 var counterfeit:=Roster.employee("promotions",0);counterfeit.gender="female"
 check(Motion.direction_set(counterfeit,0).is_empty(),"role identity validation before warm cache")
 check(Motion.direction_set(Roster.RESERVED_HOST,0).is_empty(),"host never borrowed from NPC bank")
 var c:=Character.new();c.set_look_slot(19);root.add_child(c);c.set_process(false)
 c.walking=true
 for heading in 8:
  var direction:=Vector2.RIGHT.rotated(heading*PI/4)
  var phase: float=c._cycle_phase
  c.set_motion_vector(direction,c.preferred_walk_speed());c._process(0)
  check(c._motion_heading==heading,"character body heading")
  check(is_equal_approx(c._cycle_phase,phase),"turn preserves gait phase")
  c.record_motion(direction*.01,.01);c._process(0)
  check(c._cycle_phase!=phase,"real displacement advances phase")
  c.set_motion_vector(Vector2.ZERO,0)
  check(c._motion_heading==heading,"zero displacement retains direction")
 c.free()
 var porter:=Character.new();porter.set_uniform(Color.WHITE,0,"porter");root.add_child(porter);porter.set_process(false)
 var cart_before: Dictionary=porter._cart_set
 porter.with_cart=true
 var lru_before: Array=Motion._direction_lru.duplicate()
 for heading in 8:porter.set_motion_vector(Vector2.RIGHT.rotated(heading*PI/4),1)
 check(porter._heading_set.is_empty(),"cart steering does not hold unused ordinary packet")
 check(Motion._direction_lru==lru_before,"cart turn headings do not churn ordinary LRU")
 check(porter._motion_heading==7,"cart still tracks its actual heading")
 porter.with_cart=false
 check(not porter._heading_set.is_empty(),"removing cart restores ordinary motion packet")
 check(porter._heading_set==Motion.direction_set(porter.identity,7),"restored packet matches current heading")
 check(porter._cart_set==cart_before,"cart steering packet unchanged")
 porter.free()
 print("DIRECTIONAL_BANKS checks=",checks," failures=",failures)
 quit(1 if failures else 0)
