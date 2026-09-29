extends SceneTree
const Roster := preload("res://scripts/characters/npc_roster.gd")
const Staff := preload("res://scripts/characters/staff_sprites.gd")
const Visitors := preload("res://scripts/characters/visitor_sprites.gd")
const Character := preload("res://scenes/venue/floor/character.gd")
var failures := 0
func check(ok: bool,label: String) -> void:
 if ok:print("PASS: ",label)
 else:failures+=1;printerr("FAIL: ",label)
func _initialize() -> void:call_deferred("run")
func run() -> void:
 var looks := {}
 for role in ["ticket","docent","promotions","porter"]:
  for variant in range(3):
   var identity := Roster.employee(role,variant)
   var frames: Array = Staff.frames(identity)
   check(frames.size()==8,"%s %d has eight poses" % [role,variant])
   if frames.size()==8:looks[hash(frames[0].get_image().get_data())]=true
   check(Visitors.frames(identity).is_empty(),"employee excluded from visitor pool")
   var c:=Character.new();c.set_uniform(Color.BLUE,variant,role)
   check(c._uses_approved_art and c._approved_seated==null,"employee uses approved staff art")
   c.set_look_slot(0)
   check(c.actor_role==role,"visitor setter cannot replace employee")
   c.free()
 check(looks.size()==12,"twelve distinct role/appearance combinations")
 check(Staff.frames(Roster.visitor(2)).is_empty(),"visitor excluded from employee pool")
 var child := Roster.employee("ticket",0);child.age_group="child"
 check(Staff.frames(child).is_empty(),"child cannot use employee pool")
 check(Staff.frames(Roster.RESERVED_HOST).is_empty(),"Ellis excluded from employee pool")
 print("Staff sprite failures: ",failures)
 quit(1 if failures else 0)
