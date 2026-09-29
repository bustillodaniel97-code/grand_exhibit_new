extends RefCounted
## Original venue-specific neighborhood architecture using the city's triangle batch.
## Ground contacts stay in nominal grid space and share its footprint remap.
const Character:=preload("res://scenes/venue/floor/character.gd")
const Businesses=preload("res://scenes/venue/floor/city_businesses.gd")
var city: Node2D
var design: Dictionary={}
static var plans: Dictionary={}
func _init(host: Node2D) -> void:city=host
static func plan(venue: String) -> Dictionary:
 if plans.is_empty():
  var parsed: Variant=JSON.parse_string(FileAccess.get_file_as_string("res://data/city_districts.json"))
  if parsed is Dictionary:plans=parsed
 return plans.get(venue,{})
func select(venue: String) -> void:
 design=plan(venue)
 apply_palette()
 if city.is_node_ready():build_life()
func apply_palette() -> void:
 if design.is_empty() or city._pal.is_empty():return
 city._pal.road=Color("414c51").lerp(Color(design.ground),.12)
 city._pal.lawn_dim=Color(design.ground).darkened(.05)

static func rect(a: Array) -> Rect2:return Rect2(float(a[0]),float(a[1]),float(a[2]),float(a[3]))
func patch(r: Rect2,col: Color,drop: float=13.0) -> void:city._patch(r.position,r.size,col,drop)
func ground() -> void:
 if design.is_empty():return
 var paving:=Color(design.paving);var road: Color=city._pal.road
 # Continuous street ground, then connected road surfaces: intersecting curb
 # bands cannot leave a raised pavement strip across a junction.
 for row in design.roads:patch(rect(row).grow(.65),paving)
 for row in design.roads:patch(rect(row).grow(.10),paving.darkened(.22),16)
 for row in design.roads:patch(rect(row),road,18)
 # Open the side-street mouths onto the foreground avenue. Its curb skirts
 # must not leave a raised rectangular border across the drivable junction.
 for row in design.roads:
  var r:=rect(row)
  if r.size.y>r.size.x and r.end.y>=city.KERB_B:
   patch(Rect2(r.position.x-.65,city.KERB_B,r.size.x+1.3,city.ROAD_B-city.KERB_B),road,18)
 for row in design.roads:
  var r:=rect(row);var along_x:=r.size.x>r.size.y
  var length: float=r.size.x if along_x else r.size.y
  for j in range(int(length/1.6)):
   var at:=r.position+(Vector2(j*1.6+.3,r.size.y*.5) if along_x else Vector2(r.size.x*.5,j*1.6+.3))
   var mark:=Rect2(at,Vector2(.7,.04) if along_x else Vector2(.04,.7))
   var crossing:=false
   for other in design.roads:
    if other==row:continue
    if rect(other).grow(.3).has_point(at):crossing=true
   if not crossing:patch(mark,Color("c7c6b5"),18)
 # Back-block footway and a direct link to the museum-side avenue.
 var ny: float=design.north_axis
 patch(Rect2(-19,ny-8.5,55,.8),paving)
 patch(Rect2(-2.15,ny-8.5,.65,8.5),paving)
 if design.network=="east":patch(Rect2(float(design.west_axis),ny,2.3,21.25-ny),paving)
 for row in design.gardens:
  var r:=rect(row);patch(r.grow(.10),paving.darkened(.22));patch(r,Color(design.ground).darkened(.12))
 feature_ground()
 # Door approaches connect front-row buildings to their adjacent sidewalk.
 for b in design.buildings:
  var r:=rect(b.rect)
  if b.face=="east":
   patch(Rect2(r.end.x,r.position.y+r.size.y*.49-.21,float(design.west_axis)-r.end.x,.42),paving)
  elif r.end.y<ny and r.end.y>ny-5:
   patch(Rect2(r.position.x+r.size.x*.51-.25,r.end.y,.5,ny-r.end.y),paving)
  elif r.end.y<ny-5:
   patch(Rect2(r.position.x+r.size.x*.51-.25,r.end.y,.5,ny-7.8-r.end.y),paving)
  elif r.position.x>21:
   patch(Rect2(21,r.end.y+.15,r.end.x-21,.65),paving)
   patch(Rect2(21,ny,.65,18.8-ny),paving)
func scenery() -> void:
 if design.is_empty():return
 var items: Array=[]
 for b in design.buildings:
  var r:=rect(b.rect);items.append({"depth":city._depth(r.end),"building":b})
 for f in design.get("features",[]):
  items.append({"depth":city._depth(rect(f.rect).end),"feature":f})
 for row in design.gardens:
  var r:=rect(row)
  var along_x:=r.size.x>r.size.y;var count:=int(maxf(r.size.x,r.size.y)/1.7)
  for j in count:
   var at:=r.position+r.size*.5+(Vector2((j-(count-1)*.5)*1.7,0) if along_x else Vector2(0,(j-(count-1)*.5)*1.7))
   items.append({"depth":city._depth(at),"tree":at})
 items.sort_custom(func(a: Dictionary,b: Dictionary) -> bool:return float(a.depth)<float(b.depth))
 for item in items:
  if item.has("building"):building(item.building)
  elif item.has("feature"):feature_scenery(item.feature)
  else:city._tree(item.tree,.8)
func face(a: Vector2,b: Vector2,bottom: float,height: float,color: Color) -> void:
 city._skirt(a,b,height,color,13-bottom-height)
func lit_face(a: Vector2,b: Vector2,bottom: float,height: float,top: Color,low: Color) -> void:
 var pa: Vector2=city._p(a,13-bottom-height)
 var pb: Vector2=city._p(b,13-bottom-height)
 var down:=Vector2(0,height)
 city._fill_shaded(PackedVector2Array([pa,pb,pb+down,pa+down]),PackedColorArray([top,top,low,low]))
func building(b: Dictionary) -> void:
 var r:=rect(b.rect);var g:=r.position;var s:=r.size
 var color:=Color(design.brick).lerp(Color(design.paving),float(b.tone)*.17)
 var trim:=Color(design.paving).lightened(.18);var roof:=Color(design.brick).darkened(.35)
 var height:=float(b.floors)*52.0+4.0
 var kind: String=b.kind
 if kind=="courtyard":
  courtyard(r,color,trim)
  return
 if kind in ["glass","observatory"]:color=Color(design.paving).lerp(Color("548398"),.55)
 if kind=="greenhouse":height=56; color=Color("73988b")
 # A grounded foundation, modest cast shadow, and full facade planes.
 patch(r.grow(.15),Color(design.paving).darkened(.2))
 patch(Rect2(g+Vector2(.25,.3),s),Color(0.06,.09,.11,.20))
 city._prism(g,s,height,color,13)
 city._slab(g-Vector2(.06,.06),s+Vector2(.12,.12),3,3,trim.darkened(.2),13)
 # Cornices and vertical pilasters frame distinct floors instead of blue stripes.
 for floor_index in int(b.floors):
  var base:=float(floor_index)*52.0
  if floor_index>0:city._slab(g-Vector2(.04,.04),s+Vector2(.08,.08),base,2.4,trim,13)
  windows(g+Vector2(0,s.y),g+s,base,52,trim,kind,maxi(2,int(s.x/.85)))
  windows(g+s,g+Vector2(s.x,0),base,52,trim.darkened(.07),kind,maxi(2,int(s.y/.85)))
 for corner in [g+Vector2(0,s.y),g+s,g+Vector2(s.x,0)]:
  city._prism(corner-Vector2(.035,.035),Vector2(.07,.07),height,trim.darkened(.10),13)
 # Each entrance is cut into the facade that faces its approach.
 var a:=g+Vector2(0,s.y);var z:=g+s
 if b.face=="east":a=g+s;z=g+Vector2(s.x,0)
 var door_a:=a.lerp(z,.39);var door_b:=a.lerp(z,.63)
 face(door_a,door_b,3,46,Color("334c50"))
 face(door_a.lerp(door_b,.13),door_a.lerp(door_b,.87),12,33,Color("83aeb4"))
 face(door_a,door_b,49,3,trim)
 if kind in ["shop","arcade","townhouse","courtyard"]:
  awning(a.lerp(z,.10),a.lerp(z,.92),52,Color(design.brick).lerp(Color("c17c5e"),.35))
 if kind in ["cottage","lodge","townhouse","warehouse","clock"]:
  pitched(g,s,height,roof,kind=="lodge")
 elif kind=="greenhouse":
  pitched(g,s,height,Color("81b7b1"),false,false)
 elif kind in ["courtyard","terrace"]:
  city._slab(g-Vector2(.12,.12),s+Vector2(.24,.24),height,4,trim,13)
  var inset:=r.grow(-.36);city._prism(inset.position,inset.size,8,Color(design.ground),13-height-4)
  city._prism(g+s*.3,s*.42,16,color.lightened(.10),13-height-4)
  city._slab(g+s*.3,s*.42,16,3,trim,13-height-4)
 elif kind=="observatory":
  city._slab(g-Vector2(.12,.12),s+Vector2(.24,.24),height,4,trim,13)
  dome(g+s*.5,minf(s.x,s.y)*.48,height+4,Color("7b9ba8"))
 elif kind=="clock":pass
 else:
  city._slab(g-Vector2(.10,.10),s+Vector2(.20,.20),height,4,trim,13)
  city._prism(g+s*.27,s*.37,10,color.darkened(.13),13-height-4)
 if kind in ["clock","civic"]:
  var tower:=g+s*.32;var ts:=s*.35
  city._prism(tower,ts,30,trim.darkened(.08),13-height-4)
  city._slab(tower-Vector2(.05,.05),ts+Vector2(.1,.1),30,3,roof,13-height-4)
  var p: Vector2=city._p(tower+Vector2(ts.x*.5,ts.y),13-height-21)
  city._disc(p,7,9,trim);city._disc(p,5.5,7.5,Color("f0dfac"))
  city._fill(PackedVector2Array([p+Vector2(-.7,-5),p+Vector2(.7,-5),p+Vector2(.7,1),p+Vector2(-.7,1)]),roof)
  city._fill(PackedVector2Array([p,p+Vector2(4,1),p+Vector2(4,2),p+Vector2(0,1)]),roof)
func windows(a: Vector2,b: Vector2,base: float,height: float,trim: Color,kind: String,count: int) -> void:
 for i in count:
  var x:=a.lerp(b,(i+.20)/count);var y:=a.lerp(b,(i+.80)/count)
  if kind=="arcade" and base<1:
   arch(x,y,base+3,43,trim)
   continue
  var glass:=Color("7094a2") if kind!="glass" else Color("83b9c5")
  face(x,y,base+12,height-21,trim.darkened(.2))
  var inner_a:=x.lerp(y,.09);var inner_b:=x.lerp(y,.91)
  lit_face(inner_a,inner_b,base+14,height-25,glass.lightened(.18),glass.darkened(.20))
  # A soft sky reflection sits within each pane, below the surrounding frame.
  var pa: Vector2=city._p(inner_a,13-base-height+11)
  var pb: Vector2=city._p(inner_b,13-base-height+11)
  city._fill_shaded(PackedVector2Array([pa,pb,pb+Vector2(0,6),pa+Vector2(0,12)]),PackedColorArray([Color(.88,.96,.95,.17),Color(.88,.96,.95,.13),Color(.88,.96,.95,0),Color(.88,.96,.95,0)]))
  face(x,y,base+10,2.5,trim)
  face(x.lerp(y,.48),x.lerp(y,.53),base+14,height-25,trim)
  if kind in ["townhouse","civic","lodge"]:
   face(x.lerp(y,-.12),x,base+14,height-25,Color(design.brick).darkened(.3))
   face(y,y.lerp(x,-.12),base+14,height-25,Color(design.brick).darkened(.3))
func pitched(g: Vector2,s: Vector2,h: float,color: Color,steep: bool,chimney: bool=true) -> void:
 var lift:=18.0 if steep else 12.0
 var a: Vector2=city._p(g-Vector2(.12,.12),13-h)
 var b: Vector2=city._p(g+Vector2(s.x+.12,-.12),13-h)
 var c: Vector2=city._p(g+s+Vector2(.12,.12),13-h)
 var d: Vector2=city._p(g+Vector2(-.12,s.y+.12),13-h)
 var ridge_a: Vector2=city._p(g+Vector2(-.12,s.y*.5),13-h-lift)
 var ridge_b: Vector2=city._p(g+Vector2(s.x+.12,s.y*.5),13-h-lift)
 city._fill_shaded(PackedVector2Array([b,c,ridge_b]),PackedColorArray([color.darkened(.25),color.darkened(.30),color.darkened(.14)]))
 city._fill_shaded(PackedVector2Array([a,b,ridge_b,ridge_a]),PackedColorArray([color.lightened(.08),color.lightened(.04),color.lightened(.19),color.lightened(.24)]))
 city._fill_shaded(PackedVector2Array([ridge_a,ridge_b,c,d]),PackedColorArray([color.lightened(.14),color.lightened(.09),color.darkened(.08),color.darkened(.03)]))
 # Roof seams, chimney and cap provide useful silhouette/detail at phone scale.
 for i in range(1,5):
  var t:=float(i)/5
  city._fill(PackedVector2Array([ridge_a.lerp(d,t),ridge_b.lerp(c,t),ridge_b.lerp(c,t)+Vector2(0,.7),ridge_a.lerp(d,t)+Vector2(0,.7)]),color.darkened(.13))
 if chimney:city._prism(g+s*Vector2(.72,.35),Vector2(.22,.23),16,Color(design.brick).darkened(.08),13-h-lift*.7)
func awning(a: Vector2,b: Vector2,h: float,col: Color,projection: float=.34) -> void:
 var out:=Vector2(projection,0) if is_equal_approx(a.x,b.x) else Vector2(0,projection)
 for i in 7:
  var aa:=a.lerp(b,float(i)/7);var bb:=a.lerp(b,float(i+1)/7)
  var color:=col if i%2==0 else Color(design.paving).lightened(.22)
  city._fill(PackedVector2Array([city._p(aa,13-h),city._p(bb,13-h),city._p(bb+out,17-h),city._p(aa+out,17-h)]),color)
  face(aa+out,bb+out,h-7,3,color.darkened(.12))
func dome(g: Vector2,r: float,h: float,col: Color) -> void:
 for ring in range(8):
  var t0:=float(ring)/8*PI*.5;var t1:=float(ring+1)/8*PI*.5
  for j in range(32):
   var a:=TAU*j/32;var b:=TAU*(j+1)/32
   var q:=PackedVector2Array()
   var colors:=PackedColorArray()
   for spec in [[a,t0],[b,t0],[b,t1],[a,t1]]:
    var p:=g+Vector2(cos(spec[0]),sin(spec[0]))*r*cos(spec[1]);q.append(city._p(p,13-h-sin(spec[1])*r*24))
    var light:=clampf(Vector3(cos(spec[0])*cos(spec[1]),sin(spec[0])*cos(spec[1]),sin(spec[1])).dot(Vector3(-.45,-.50,.74)),0,1)
    colors.append(col.darkened(.26).lerp(col.lightened(.25),light))
   city._fill_shaded(q,colors)

var walkers: Array=[]
var traffic: Array=[]
var life_time:=0.0
func clear_life() -> void:
 for person in walkers:
  if is_instance_valid(person.node):person.node.get_parent().remove_child(person.node);person.node.queue_free()
 walkers.clear();traffic.clear();life_time=0
func build_life() -> void:
 clear_life()
 if design.is_empty():return
 for i in design.walkers.size():
  var spec: Dictionary=design.walkers[i];var c:=Character.new();c.set_look_slot(int(spec.slot));city.add_child(c)
  c.scale=Vector2.ONE*c.age_scale()*.82
  var destinations:=Businesses.frontage(city)
  if destinations.size()<2:c.queue_free();continue
  var start: Dictionary=destinations[i%destinations.size()]
  walkers.append({"node":c,"pos":city.map_point(start.door),"inside":8.0+i*11.0,"door_id":start.id,"destinations":destinations,"path":[],"visits":0,"fade":0.0})
  c.visible=false
 for i in design.traffic.size():
  var spec: Dictionary=design.traffic[i]
  traffic.append({"gx":float(spec.a[0]),"gy":float(spec.a[1]),"dir":signf(float(spec.b[0])-float(spec.a[0])),"col":city._pal.cars[i%city._pal.cars.size()],"model":3 if i==1 and design.identity in ["metro","civic","night","royal"] else i,"u":float(spec.offset),"a":Vector2(spec.a[0],spec.a[1]),"b":Vector2(spec.b[0],spec.b[1]),"speed":float(spec.speed),"points":spec.points})
 for i in traffic.size():
  var car: Dictionary=traffic[i]
  city.Vehicles.assign(car,city.venue_id,i,true)
  var points:=PackedVector2Array()
  for p in car.points:points.append(Vector2(p[0],p[1]))
  # Turned background trips use the same directed side-street lanes.
  for j in range(points.size()-1):
   if absf(points[j].x-points[j+1].x)<.001:
    for row in design.roads:
     var r:=rect(row)
     if r.size.y>r.size.x and points[j].x>=r.position.x and points[j].x<=r.end.x:
      var lane:=r.position.x+(.65 if points[j+1].y>points[j].y else 1.65)
      points[j].x=lane;points[j+1].x=lane;break
  city.Routes.start(car,city.Routes.rounded(points))
  car.pool_id=i+4
  car.trip=i+4
  var length:=0.0
  for j in range(points.size()-1):length+=points[j].distance_to(points[j+1])
  city.Routes.step(car,length*float(car.u))
 advance(0)
func advance(dt: float) -> void:
 if design.is_empty():return
 life_time+=dt
 for person in walkers:
  var c: Node2D=person.node
  if person.inside>0:
   person.inside=maxf(0,float(person.inside)-dt);c.walking=false;c.visible=false
   if person.inside==0:
    var choices: Array=person.destinations.filter(func(entry: Dictionary) -> bool:return entry.id!=person.door_id)
    var target: Dictionary=choices[(int(person.visits)+walkers.find(person))%choices.size()]
    var start: Vector2=person.pos
    var goal: Vector2=city.map_point(target.door)
    var y: float=city.map_point(Vector2(0,float(design.north_axis)-.52)).y
    person.path=[Vector2(start.x,y),Vector2(goal.x,y),goal]
    person.door_id=target.id;person.fade=0.0;c.modulate.a=0;c.visible=true
   continue
  c.visible=true;person.fade=minf(1,float(person.fade)+dt*2);c.modulate.a=person.fade
  var before: Vector2=person.pos
  if not person.path.is_empty():
   person.pos=before.move_toward(person.path[0],c.preferred_walk_speed()*.82*dt)
   if person.pos.distance_to(person.path[0])<.001:person.path.pop_front()
  c.walking=person.pos.distance_to(before)>.00001
  c.position=city.Iso.to_screen(person.pos)+Vector2(0,city.DROP+city.Y_LIFT)
  c.record_motion(person.pos-before,dt)
  if person.path.is_empty():
   person.visits+=1;person.inside=22.0+float(person.visits%4)*9.0;c.walking=false;c.visible=false
 for car in traffic:
  if float(car.wait)>0:
   car.wait=maxf(0,float(car.wait)-dt)
   if car.wait==0:
    if not city.can_enter(car,car.route[0]):car.wait=.25;continue
    car.trip+=1;city.Vehicles.assign_trip(car,city.venue_id,int(car.trip))
    city.Routes.start(car,car.route)
   continue
  var distance:=dt*float(car.speed)
  var at:=Vector2(car.gx,car.gy);var heading: Vector2=car.axis*float(car.dir)
  for other in traffic+city._cars:
   if other==car or float(other.get("wait",0))>0:continue
   var offset:=Vector2(other.gx,other.gy)-at;var ahead:=offset.dot(heading)
   if ahead>0 and absf(offset.cross(heading))<.65 and (absf(heading.dot(other.axis))>.9 or int(car.pool_id)>int(other.pool_id)):
    distance=minf(distance,maxf(0,ahead-city.car_half_extent(car)-city.car_half_extent(other)-.55))
  if city.Routes.step(car,distance):car.wait=3.3+fmod(float(car.trip)*1.37,4.0)

func feature_ground() -> void:
 for f in design.get("features",[]):
  var r:=rect(f.rect);var paving:=Color(design.paving)
  patch(r.grow(.25),paving)
  if f.kind=="water":
   patch(r,Color("426f80"),17)
   for i in range(int(r.size.y*3)):
    var y:=r.position.y+.2+i*.32
    var x:=r.position.x+.18+fmod(i*.57,maxf(r.size.x-.6,.1))
    patch(Rect2(x,y,minf(.45,r.end.x-x-.1),.022),Color("739aa0"),17)
  elif f.kind in ["grove","garden","parterre"]:patch(r.grow(-.15),Color(design.ground).darkened(.06))
  else:patch(r,Color(design.paving).lightened(.06))
func feature_scenery(f: Dictionary) -> void:
 var r:=rect(f.rect);var g:=r.position;var s:=r.size;var trim:=Color(design.paving).lightened(.1)
 if f.kind=="water":
  # Solid timber piers reach land, with piles down to the water rather than
  # unsupported floating platforms. The narrow canal keeps its towpath clear.
  var count:=2 if s.x<4 else 3
  for j in count:
   var at:=g+Vector2(-.28,2+j*(s.y-4)/count)
   var size:=Vector2(minf(s.x*.65,3),.36)
   city._prism(at,size,5,Color("827668"),13)
   for end in [at+Vector2(.08,.04),at+size-Vector2(.14,.14)]:city._prism(end,Vector2(.12,.12),9,Color("5d5e57"),17)
 elif f.kind in ["grove","garden"]:
  patch(Rect2(g.x+s.x*.42,g.y,.55,s.y),trim)
  for j in range(4):
   var at:=g+Vector2(.6+(j%2)*(s.x-1.2),1+j*(s.y-2)/4)
   city._tree(at,1.1 if design.identity=="ridge" else .9)
  if f.kind=="garden":
   building({"rect":[g.x+.6,g.y+3.5,2.3,2.3],"kind":"greenhouse","floors":1,"face":"south","tone":1})
 elif f.kind=="market":
  for j in range(4):
   var at:=g+Vector2(.15,.6+j*2.9)
   city._prism(at,Vector2(1.65,.7),22,Color(design.brick),13)
   for corner in [at,at+Vector2(1.6,0),at+Vector2(0,.7),at+Vector2(1.6,.7)]:city._prism(corner,Vector2(.08,.08),50,trim,13)
   awning(at,at+Vector2(1.7,0),51,Color("a56854") if j%2 else Color("738e89"),.75)
   for k in range(4):city._disc(city._p(at+Vector2(.23+k*.35,.4),-11),3.7,2.6,Color("e2b975") if k%2 else Color("bb765e"))
 elif f.kind=="parterre":
  patch(Rect2(g.x+s.x*.45,g.y,.65,s.y),trim)
  for x in [.7,s.x-2.4]:
   for y in [.6,5.1,9.6]:
    var at:=g+Vector2(x,y);city._prism(at,Vector2(1.5,2.7),4,Color("617d60"),13)
    patch(Rect2(at+Vector2(.18,.18),Vector2(1.14,2.34)),Color("b9a987"),8)
  fountain(g+s*.5,1.1)
 elif f.kind=="clock_square":
  building({"rect":[g.x+.3,g.y+2,2.35,2.4],"kind":"clock","floors":1,"face":"south","tone":1})
  fountain(g+Vector2(s.x*.5,s.y*.72),.8)
 else:
  var center:=g+s*.5
  if f.kind=="reading_square":
   fountain(center,1.4)
   for x in [-2.3,2.3]:city._prism(center+Vector2(x,-1.2),Vector2(.28,2.4),8,Color(design.brick).darkened(.2),13)
  elif f.kind=="solar_square":
   city._prism(center-Vector2(.6,.6),Vector2(1.2,1.2),9,trim,13)
   dome(center,1.05,9,Color("8eaeba"))
  else:
   city._prism(center-Vector2(.5,.5),Vector2(1,1),9,trim,13)
   city._prism(center-Vector2(.1,.1),Vector2(.2,.2),45,Color("697e89"),4)
   var p: Vector2=city._p(center,-40)
   city._disc(p,17,20,Color("b8a46e"));city._disc(p,10,12,Color(design.paving))
  for j in range(3):city._tree(g+Vector2(.55,1.5+j*3.3),.85)
func fountain(g: Vector2,r: float) -> void:
 var p: Vector2=city._p(g,13)
 city._disc(p,r*30,r*18,Color(design.paving).darkened(.24))
 city._disc(p+Vector2(0,-4),r*27,r*16,Color(design.paving).lightened(.13))
 city._disc(p+Vector2(0,-5),r*22,r*12,Color("739a9f"))
 city._prism(g-Vector2(.07,.07),Vector2(.14,.14),21,Color(design.paving).lightened(.16),13)
 city._disc(p+Vector2(0,-22),8,4,Color("b7d1c9"))
func draw_motion() -> void:
 for f in design.get("features",[]):
  if f.kind!="water":continue
  var r:=rect(f.rect)
  for i in range(2 if r.size.x<4 else 3):
   var g:=r.position+Vector2(r.size.x*.64,2.8+i*(r.size.y-5)/3)
   var p: Vector2=city._p(g,15+sin(life_time*1.1+i)*.8)
   var axis: Vector2=(city._p(g+Vector2(0,1))-city._p(g)).normalized()
   city._capsule(p,axis,29,11,Color("ddd5bc"),4)
   city._capsule(p+Vector2(0,-3),axis,18,7,Color("597b8d"),4)
   city._fill(PackedVector2Array([p+Vector2(0,-4),p+Vector2(1,-25),p+Vector2(12,-6)]),Color("f3e7ca"))

func arch(a: Vector2,b: Vector2,base: float,height: float,col: Color) -> void:
 var pa: Vector2=city._p(a,13-base);var pb: Vector2=city._p(b,13-base)
 var mid: Vector2=(pa+pb)*.5-Vector2(0,height-7)
 var half: Vector2=(pb-pa)*.5
 var q:=PackedVector2Array([pa,pb,pb-Vector2(0,height-7)])
 for i in range(1,13):
  var t:=float(i)/12*PI;q.append(mid+half*cos(t)-Vector2(0,sin(t)*8))
 city._fill(q,Color(design.brick).darkened(.48))
 face(a.lerp(b,-.12),a,base,height-6,col)
 face(b,b.lerp(a,-.12),base,height-6,col)
 # Wedge-shaped arch stones follow the curved opening rather than painting
 # a rectangular window on an "arcade" label.
 for i in range(12):
  var t0:=PI*i/12;var t1:=PI*(i+1)/12
  var p0:=mid+half*cos(t0)-Vector2(0,sin(t0)*8)
  var p1:=mid+half*cos(t1)-Vector2(0,sin(t1)*8)
  city._fill(PackedVector2Array([p0,p1,p1-Vector2(0,2.2),p0-Vector2(0,2.2)]),col)
func courtyard(r: Rect2,color: Color,trim: Color) -> void:
 var g:=r.position;var s:=r.size;var height:=56.0
 patch(r.grow(.15),trim.darkened(.15))
 patch(r.grow(-.45),Color(design.ground).darkened(.05))
 for wing in [Rect2(g,Vector2(s.x,.55)),Rect2(g,Vector2(.55,s.y)),Rect2(g+Vector2(s.x-.55,0),Vector2(.55,s.y))]:
  city._prism(wing.position,wing.size,height,color,13)
  city._slab(wing.position-Vector2(.04,.04),wing.size+Vector2(.08,.08),height,3,trim,13)
 var a:=g+Vector2(.55,s.y);var b:=g+Vector2(s.x-.55,s.y)
 for t in [0.0,1.0]:city._prism(a.lerp(b,t),Vector2(.10,.10),50,trim,13)
 city._slab(a,Vector2(s.x-1.0,.13),50,3,trim,13)
 city._disc(city._p(g+s*.5,12),6,3.5,Color("749794"))
