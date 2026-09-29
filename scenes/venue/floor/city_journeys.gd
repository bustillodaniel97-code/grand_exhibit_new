extends RefCounted
## Visitors keep their identity after leaving the museum. Removal happens only
## inside an actual business entrance or after boarding a stopped vehicle.
const Businesses=preload("res://scenes/venue/floor/city_businesses.gd")
const MAX_DEPARTURES=16
var floor_node: Node
var people: Array=[]
var businesses: Array=[]
var sequence:=0
var elapsed:=0.0
var completed:={"business":0,"taxi":0,"shuttle":0,"park":0}
func _init(host: Node) -> void:floor_node=host
func clear() -> void:
 for person in people:
  _retire(person)
 people.clear();businesses.clear();sequence=0;elapsed=0
 completed={"business":0,"taxi":0,"shuttle":0,"park":0}
func configure() -> void:
 businesses=Businesses.connected(floor_node._city)
 floor_node._plaza.journeys=self
func arrival_route() -> Array:
 var city: Node=floor_node._city
 for kind in ["shuttle","taxi"]:
  if city.transit.take_arrival(kind):
   var curb: Vector2=city.transit.curb(kind)
   return [city.transit.door(kind),curb,Vector2(city._entrance.x,curb.y),city.ramp_bottom(),city.street_point()]
 if not businesses.is_empty():
  var b: Dictionary=businesses[posmod(sequence+floor_node._visitors.size(),businesses.size())]
  var path: Array=b.path.duplicate();path.reverse()
  path.append_array(city.near_sidewalk_route(b.right).slice(1))
  return path
 # Through pedestrians enter from beyond the district, not a visible sidewalk midpoint.
 var path: Array=city.arrival_route(bool(randi()&1))
 path[0]=city.map_point(Vector2(-25 if bool(randi()&1) else 34,21.62))
 return path
func plan(_v: RefCounted,allow_park: bool=true) -> Dictionary:
 sequence+=1
 var choice:=sequence%5
 var out: Dictionary={"kind":"shuttle","park":-1}
 if choice in [0,3] and not businesses.is_empty():
  out={"kind":"business","business":businesses[sequence%businesses.size()],"park":-1}
 elif choice==1:out.kind="taxi"
 var city: Node=floor_node._city
 out.entry=city.map_point(city.NEAR_WALK_RIGHT if out.kind=="business" and out.business.right else city.NEAR_WALK_LEFT)
 # The existing bird garden is a genuine stop on the journey, not a new actor.
 if choice==2 and allow_park:
  var plaza=floor_node._plaza
  for i in plaza.activities.size():
   if plaza.activities[i].kind!="feed" or not plaza.activity_available(i):continue
   plaza.reserved_activities[i]=true;out.park=i;out.entry=plaza.activities[i].at;break
 return out
func accept(v: RefCounted) -> bool:
 if people.size()>=MAX_DEPARTURES:return false
 var p: Dictionary={"v":v,"plan":v.city_plan,"state":"park" if int(v.city_plan.get("park",-1))>=0 else "travel","wait":10.0,"slot":-1}
 people.append(p);v.state="city";v.node.reaction=""
 if p.state=="park":v.node.walking=false;v.node.prepare_bird_feeding()
 else:_start_destination(p)
 return true
func public_count() -> int:
 var count:=0
 for p in people:
  if p.has("public"):count+=1
 return count
func _public_guest(person: Dictionary):
 var v=floor_node.get_script().Visitor.new()
 v.node=person.node;v.pos=person.pos;v.speed=person.node.preferred_walk_speed();v.state="city"
 return v
func arrive_public(person: Dictionary) -> bool:
 var route:=arrival_route()
 # The last three points lead into the museum. Park visitors branch from
 # the same public pavement to their own reserved activity instead.
 route.resize(route.size()-3)
 var plaza=floor_node._plaza
 var curb: Vector2=route.back()
 curb.y=floor_node._city.map_point(floor_node._city.NEAR_WALK_LEFT).y
 if not curb.is_equal_approx(route.back()):route.append(curb)
 var left: Vector2=floor_node._city.map_point(floor_node._city.NEAR_WALK_LEFT)
 var right: Vector2=floor_node._city.map_point(floor_node._city.NEAR_WALK_RIGHT)
 var activity_at: Vector2=plaza.activities[person.activity_index].at
 person.home=left if activity_at.distance_to(left)<activity_at.distance_to(right) else right
 var approach: Array=plaza.route(route.back(),person.home)
 if approach.is_empty():return false
 route.append_array(approach)
 var v=_public_guest(person);v.pos=route.pop_front();v.target=route.pop_back();v.path=route
 person.pos=v.pos;person.trail=[v.pos];person.trail_distance=0.0;person.companion_pos=v.pos
 v.node.modulate.a=0
 floor_node._place(v.node,v.pos)
 plaza.reserved_activities[person.activity_index]=true
 people.append({"v":v,"public":person,"state":"public_arriving","plan":{"kind":"public"},"slot":-1,"wait":0.0})
 return true
func depart_public(person: Dictionary) -> bool:
 if people.size()>=MAX_DEPARTURES+4:return false
 var v=_public_guest(person);v.city_plan=person.city_plan
 var p: Dictionary={"v":v,"public":person,"plan":v.city_plan,"state":"travel","slot":-1,"wait":0.0}
 people.append(p);_start_destination(p);return true
func _retire(p: Dictionary) -> void:
 var plaza=floor_node._plaza
 if p.has("public"):
  for key in ["companion","leash"]:
   var n=p.public.get(key)
   if is_instance_valid(n):plaza.nodes.erase(n);n.queue_free()
  plaza.nodes.erase(p.v.node)
 if is_instance_valid(p.v.node):p.v.node.queue_free()
func _start_destination(p: Dictionary) -> void:
 var v=p.v;var plan: Dictionary=p.plan;var city: Node=floor_node._city
 var path: Array=[]
 var target: Vector2
 if plan.kind=="business":target=plan.business.path[0]
 else:
  if p.slot<0:
   var occupied: Array=[]
   for other in people:
    if other!=p and other.plan.kind==plan.kind:occupied.append(int(other.slot))
   p.slot=0
   while occupied.has(int(p.slot)):p.slot+=1
  # Each passenger owns a distinct curb position until their trip completes.
  target=city.transit.curb(plan.kind)+Vector2(p.slot*.52*(1 if plan.kind=="shuttle" else -1),-.18)
 if v.pos.distance_to(target)>.01:
  path.assign(floor_node._plaza.route(v.pos,target))
  if path.is_empty():
   p.state="route_wait";p.wait=1.0;v.node.walking=false;return
 if plan.kind=="business":path.append_array(plan.business.path.slice(1))
 if path.is_empty():v.target=v.pos
 else:v.target=path.pop_back()
 v.path=path;p.state="travel";v.node.set_bird_feeding(false)
func advance(dt: float) -> void:
 elapsed+=dt
 var finished: Array=[]
 var resumed: Array=[]
 for p in people:
  var v=p.v
  var before: Vector2=v.pos
  match str(p.state):
   "public_arriving":
    v.node.modulate.a=minf(1,v.node.modulate.a+dt*2.5)
    var handoff_clear:=true
    if v.pos.distance_to(v.target)<1.2:
     for other in floor_node._plaza.people:
      if other.pos.distance_to(v.target)<1.1:handoff_clear=false
     for other in people:
      if other==p:break
      if other.state=="public_arriving" and other.v.target.distance_to(v.target)<.7:handoff_clear=false
    if not handoff_clear:v.node.walking=false;continue
    if floor_node._move(v,dt):
     var plaza=floor_node._plaza
     p.public.pos=v.pos;p.public.path=plaza.route(v.pos,plaza.activities[p.public.activity_index].at)
     plaza.reserved_activities.erase(int(p.public.activity_index))
     plaza.people.append(p.public);resumed.append(p)
   "route_wait":
    p.wait-=dt
    if p.wait<=0:_start_destination(p)
   "park":
    v.node.walking=false;v.node.set_motion_vector(Vector2(.6,.4),0);v.node.set_bird_feeding(true,elapsed);p.wait-=dt
    if p.wait<=0:
     floor_node._plaza.reserved_activities.erase(int(p.plan.park));completed.park+=1
     _start_destination(p)
   "travel":
    if floor_node._move(v,dt):
     v.node.walking=false
     p.state="entering" if p.plan.kind=="business" else "waiting"
     p.wait=.9 if p.has("public") and is_instance_valid(p.public.get("companion")) else .6
   "waiting":
    v.node.walking=false
    var city: Node=floor_node._city
    # One passenger approaches a vehicle at a time; others keep their place.
    var boarding:=false
    for other in people:
     if other==p:break
     if other.plan.kind==p.plan.kind:boarding=true
    if not boarding and city.transit.board(p.plan.kind):
     var curb: Vector2=city.transit.curb(p.plan.kind)
     v.path=[curb];v.target=city.transit.door(p.plan.kind);p.state="boarding"
   "boarding":
    # Hold the vehicle until the reserved passenger reaches its curb-side door.
    var car: Dictionary=floor_node._city.transit.vehicle(p.plan.kind)
    if not car.is_empty():car.dwell=maxf(float(car.dwell),4.0)
    if floor_node._move(v,dt):
     p.state="entering";p.wait=.9 if p.has("public") and is_instance_valid(p.public.get("companion")) else .45
   "entering":
    p.wait-=dt;v.node.walking=false;v.node.modulate.a=clampf(p.wait/.45,0,1)
    if p.wait<=0:
     if p.plan.kind in ["taxi","shuttle"]:
      var car: Dictionary=floor_node._city.transit.vehicle(p.plan.kind)
      if not car.is_empty():car.boarding=false
     completed[p.plan.kind]+=1;finished.append(p)
  if p.has("public") and is_instance_valid(p.public.get("companion")):
   p.public.pos=v.pos
   floor_node._plaza._update_companion(p.public,dt,before)
   if p.state=="entering":
    p.public.companion_pos=p.public.companion_pos.move_toward(v.pos,dt*v.speed*1.4)
    floor_node._plaza._place(p.public.companion,p.public.companion_pos)
    p.public.leash.position=p.public.companion.position
   p.public.companion.modulate.a=v.node.modulate.a
   p.public.leash.modulate.a=v.node.modulate.a
 for p in resumed:people.erase(p)
 for p in finished:
  people.erase(p);_retire(p)
