extends RefCounted
## Finish geometry follows authored wall segments and their existing storey.
const Iso := preload("res://scenes/venue/floor/iso.gd")

static func wall_details(ci: CanvasItem, venue: String, at: Vector2, length: float, axis: String, height: float, glass: bool) -> void:
 if venue == "infinite_museum":
  _worlds_wall(ci,at,length,axis,height,glass)
  return
 if venue == "empyrean_palace":
  _palace_wall(ci,at,length,axis,height)
  return
 if venue == "chronos_spire":
  _clock_wall(ci,at,length,axis,height,glass)
  return
 if venue == "pelagic_crown":
  _ocean_wall(ci,at,length,axis,height,glass)
  return
 if venue == "ironwood_citadel" and not glass:
  _keep_wall(ci,at,length,axis,height)
  return
 if venue != "sunspire" or glass or height < 30 or length < .6:return
 var along := Vector2.RIGHT if axis == "x" else Vector2.DOWN
 var stone := Color("#CDB68D")
 var lapis := Color("#516E91")
 # A narrow lapis frieze is embedded below the cap, with a repeating carved zigzag.
 var strip := PackedVector2Array([
  Iso.to_screen(at)+Vector2(0,-height+7),
  Iso.to_screen(at+along*length)+Vector2(0,-height+7),
  Iso.to_screen(at+along*length)+Vector2(0,-height+13),
  Iso.to_screen(at)+Vector2(0,-height+13)])
 Iso.fill(ci, strip,lapis)
 var motif := PackedVector2Array()
 var steps := maxi(2,int(length*5))
 for i in range(steps+1):
  motif.append(Iso.to_screen(at+along*(length*i/steps))+Vector2(0,-height+(8.5 if i%2==0 else 11.5)))
 ci.draw_polyline(motif,Color("#DECB9F"),1,true)
 # Shallow engaged pilasters: existing wall anchors remain authoritative.
 var bays := maxi(1,int(length/2.4))
 for i in range(bays+1):
  var center := at+along*(length*i/bays)
  Iso.box(ci,center-Vector2(.085,.085),Vector2(.17,.17),5,stone.darkened(.08))
  Iso.box(ci,center-Vector2(.05,.05),Vector2(.10,.10),height,stone)
  var cap := Iso.quad(center-Vector2(.10,.10),Vector2(.20,.20))
  for j in range(cap.size()):cap[j].y -= height+2
  Iso.fill(ci, PackedVector2Array([cap[1],cap[2],cap[2]+Vector2(0,3),cap[1]+Vector2(0,3)]),stone.darkened(.12))
  Iso.fill(ci, PackedVector2Array([cap[2],cap[3],cap[3]+Vector2(0,3),cap[2]+Vector2(0,3)]),stone.darkened(.22))
  Iso.fill(ci, cap,stone.lightened(.13))

## Cast-iron greenhouse bays: arched ribs, warm stone sill and brass bosses.
## Follows real wall segments so the finish cannot seal authored doorways.
static func glasshouse(ci: CanvasItem,at: Vector2,length: float,axis: String,height: float) -> void:
 var along := Vector2.RIGHT if axis == "x" else Vector2.DOWN
 var bays := maxi(1,roundi(length/1.6))
 var width := length/bays
 var iron := Color("#365747")
 var brass := Color("#CCB57D")
 var point := func(t: float,z: float) -> Vector2:return Iso.to_screen(at+along*t)+Vector2(0,-z)
 Iso.fill(ci, PackedVector2Array([point.call(0,0),point.call(0,height),point.call(length,height),point.call(length,0)]),Color(.67,.82,.72,.30))
 for bay in range(bays):
  var left := bay*width+.10
  var right := (bay+1)*width-.10
  var mid := (left+right)*.5
  var arch := PackedVector2Array([point.call(left,8)])
  for i in range(25):
   var angle := PI-i*PI/24
   arch.append(point.call(mid+cos(angle)*(right-left)*.5,height-20+sin(angle)*15))
  arch.append(point.call(right,8))
  ci.draw_polyline(arch,iron,3,true)
  ci.draw_line(point.call(mid,9),point.call(mid,height-5),iron,1.6,true)
  ci.draw_line(point.call(left,height*.44),point.call(right,height*.44),iron,1.6,true)
  ci.draw_circle(point.call(mid,height*.44),2.3,brass,true,-1,true)
  ci.draw_line(point.call(left+.14,height*.67),point.call(mid-.08,height*.30),Color(.9,.97,.88,.40),2,true)
 for i in range(bays+1):
  var t := i*width
  ci.draw_line(point.call(t,0),point.call(t,height+2),iron,4,true)
  ci.draw_line(point.call(t,0),point.call(t,10),Color("#BCBEA3"),7,true)
 ci.draw_line(point.call(0,height+2),point.call(length,height+2),brass,2.5,true)
 ci.draw_line(point.call(0,5),point.call(length,5),Color("#BCBEA3"),5,true)

## A restored keep: irregular ashlar courses and recessed lancet windows.
## Shallow finish only; wall heights and door clearances remain authored data.
static func _keep_wall(ci: CanvasItem,at: Vector2,length: float,axis: String,height: float) -> void:
 if length<.6:return
 var along := Vector2.RIGHT if axis=="x" else Vector2.DOWN
 var stone := Color("#BDB39C")
 var mortar := Color("#6B6255")
 var point := func(t: float,z: float) -> Vector2:return Iso.to_screen(at+along*t)+Vector2(0,-z)
 for row in range(1,int(height/12)):
  var z := row*12.0
  ci.draw_line(point.call(0,z),point.call(length,z),Color(mortar,.30),1,true)
  var x := .7 if row%2 else .2
  while x<length:
   ci.draw_line(point.call(x,z),point.call(x,minf(z+12,height)),Color(mortar,.28),1,true)
   x+=1.2
 ci.draw_line(point.call(0,height),point.call(length,height),stone,4,true)
 if height<40:return
 var bays := maxi(1,int(length/2.2))
 for bay in range(bays):
  var mid := length*(bay+.5)/bays
  var half := minf(.40,length/bays*.27)
  var bottom := 14.0
  var shoulder := height-24.0
  var outline := PackedVector2Array([point.call(mid-half,bottom),point.call(mid-half,shoulder),point.call(mid,height-10),point.call(mid+half,shoulder),point.call(mid+half,bottom)])
  Iso.fill(ci, outline,Color("#3B4A47"))
  outline.append(outline[0]);ci.draw_polyline(outline,stone,3,true)
  ci.draw_line(point.call(mid,bottom),point.call(mid,height-13),Color("#BD9B61"),1.8,true)
  ci.draw_line(point.call(mid-half,bottom+9),point.call(mid+half,bottom+9),Color("#BD9B61"),1.8,true)
 for edge in [0.0,length]:
  ci.draw_line(point.call(edge,0),point.call(edge,height),stone.darkened(.12),5,true)

## Ocean-liner pearl pillars, portholes and a panoramic reef observation wall.
static func _ocean_wall(ci: CanvasItem,at: Vector2,length: float,axis: String,height: float,glass: bool) -> void:
 if length<.6:return
 var along := Vector2.RIGHT if axis=="x" else Vector2.DOWN
 var point := func(t: float,z: float) -> Vector2:return Iso.to_screen(at+along*t)+Vector2(0,-z)
 var pearl := Color("#C7DCD3")
 var metal := Color("#BFB28D")
 ci.draw_line(point.call(0,height),point.call(length,height),pearl,5,true)
 if height<40:return
 var bays := maxi(1,int(length/2.0))
 if glass:
  Iso.fill(ci, PackedVector2Array([point.call(0,8),point.call(0,height-5),point.call(length,height-5),point.call(length,8)]),Color("#336D80"))
  for i in range(bays*3):
   var x := length*(i+.5)/(bays*3)
   var z := 22.0+float(i%3)*12
   var c: Vector2=point.call(x,z)
   Iso.fill(ci, PackedVector2Array([c+Vector2(-6,0),c+Vector2(0,-3),c+Vector2(5,0),c+Vector2(0,3)]),Color("#A6CCC2"))
   Iso.fill(ci, PackedVector2Array([c+Vector2(-5,0),c+Vector2(-9,-3),c+Vector2(-9,3)]),Color("#A6CCC2"))
  for i in range(bays+1):ci.draw_line(point.call(length*i/bays,5),point.call(length*i/bays,height),pearl,4,true)
 else:
  for bay in range(bays):
   var mid := length*(bay+.5)/bays
   var radius := minf(.36,length/bays*.25)
   var ring := PackedVector2Array()
   for i in range(49):
    var a := i*TAU/48
    ring.append(point.call(mid+cos(a)*radius,height*.58+sin(a)*11))
   Iso.fill(ci, ring,Color("#2E6478"))
   ci.draw_polyline(ring,metal,3,true)
   ci.draw_line(point.call(mid-radius*.55,height*.58-3),point.call(mid+radius*.55,height*.58+5),Color("#9CC9CE"),1.5,true)
 for edge in [0.0,length]:ci.draw_line(point.call(edge,0),point.call(edge,height),pearl,5,true)
 ci.draw_line(point.call(0,5),point.call(length,5),pearl,4,true)

## Recessed structural facades on the existing raised-room masses. These are
## architectural surfaces, not new walkable rooms or changed navigation holes.
const STRUCTURES := {
 "whispering_pines": ["glass", "#536C61", "#B9C5AC", "#B39358"],
 "grand_river": ["arch", "#645245", "#BA936E", "#79998B"],
 "sunspire": ["arch", "#846448", "#CDB68D", "#516E91"],
 "cloudrest": ["truss", "#536B77", "#BECBD0", "#E0D5B7"],
 "aurora_world": ["glass", "#647D94", "#D3E2E2", "#A8CDBD"],
 "celestial_conservatory": ["glass", "#456C56", "#ABC197", "#C4AC69"],
 "ironwood_citadel": ["arch", "#4D584F", "#9C9F86", "#B99760"],
 "pelagic_crown": ["arch", "#355774", "#7EAFB9", "#B6D7C8"],
 "chronos_spire": ["clock", "#3D505A", "#B6B8AC", "#C7A875"],
 "empyrean_palace": ["arch", "#74676B", "#D4C5AE", "#C8AE74"],
 "infinite_museum": ["glass", "#4F6071", "#C6C9BB", "#C8B17A"],
}
static func support_details(ci: CanvasItem,venue: String,r: Rect2,height: float) -> void:
 if not STRUCTURES.has(venue) or height < 35:return
 var kit: Array=STRUCTURES[venue]
 var recess:=Color(kit[1]).darkened(.28)
 var stone:=Color(kit[2])
 var trim:=Color(kit[3])
 for face in range(2):
  var start:=Vector2(r.position.x,r.end.y) if face==0 else Vector2(r.end.x,r.position.y)
  var along:=Vector2.RIGHT if face==0 else Vector2.DOWN
  var length:=r.size.x if face==0 else r.size.y
  var bays:=maxi(1,int(length/1.8))
  var width:=length/bays
  if width < .7:continue
  var point:=func(t: float,z: float) -> Vector2:return Iso.to_screen(start+along*t)+Vector2(0,-z)
  for storey in range(ceili(height/Iso.LEVEL_H)):
   var base:=storey*Iso.LEVEL_H
   var ceiling:=minf(height,base+Iso.LEVEL_H)
   for bay in range(bays):
    var left:=bay*width+.16
    var right:=(bay+1)*width-.16
    var bottom:=base+9.0
    var top:=ceiling-12.0
    if top-bottom < 16:continue
    var outline:=PackedVector2Array()
    if str(kit[0]) in ["arch","clock"]:
     outline.append(point.call(left,bottom))
     for i in range(17):
      var angle:=PI-i*PI/16
      outline.append(point.call((left+right)*.5+cos(angle)*(right-left)*.5,top-12+sin(angle)*12))
     outline.append(point.call(right,bottom))
    else:
     outline=PackedVector2Array([point.call(left,bottom),point.call(left,top),point.call(right,top),point.call(right,bottom)])
    Iso.fill(ci, outline,recess)
    outline.append(outline[0]);ci.draw_polyline(outline,stone,3,true)
    if str(kit[0])=="truss":
     ci.draw_line(point.call(left,bottom),point.call(right,top),trim,3,true)
     ci.draw_line(point.call(right,bottom),point.call(left,top),trim,3,true)
    elif str(kit[0])=="clock":
     var mid := (left+right)*.5
     ci.draw_line(point.call(mid,top-7),point.call(mid,bottom+10),trim,2,true)
     var bob := PackedVector2Array()
     for i in range(33):
      var angle := TAU*i/32
      bob.append(point.call(mid+cos(angle)*(right-left)*.21,bottom+10+sin(angle)*7))
     Iso.fill(ci, bob,trim)
     ci.draw_line(point.call(left+.05,bottom+3),point.call(right-.05,bottom+3),stone,3,true)
    elif str(kit[0])=="glass":
     var mid:=(left+right)*.5
     ci.draw_line(point.call(mid,bottom),point.call(mid,top),trim,2,true)
     ci.draw_line(point.call(left,(top+bottom)*.5),point.call(right,(top+bottom)*.5),trim,2,true)
     ci.draw_line(point.call(left+.12,top-6),point.call(mid-.08,bottom+8),Color(.8,.93,.92,.32),2,true)
    else:
     # Raised keystone and a quiet inset plinth make a niche read as masonry.
     var key: Vector2 = point.call((left+right)*.5,top)
     ci.draw_line(key+Vector2(0,-3),key+Vector2(0,4),trim,4,true)
     ci.draw_line(point.call(left+.08,bottom+4),point.call(right-.08,bottom+4),trim,2,true)
   ci.draw_line(point.call(.05,ceiling-3),point.call(length-.05,ceiling-3),trim,3,true)


## A real open span: slender end piers support a thin deck rather than a
## facade painted on a solid room-sized block. Existing navigation stays above.
static func bridge_support(ci: CanvasItem, r: Rect2, height: float) -> void:
 var steel := Color("#536B77")
 var cap := Color("#BECBD0")
 for x in [r.position.x + .16, r.end.x - .40]:
  for y in [r.position.y + .14, r.end.y - .38]:
   Iso.box(ci, Vector2(x, y), Vector2(.24, .24), height - 6, steel)
   Iso.box(ci, Vector2(x - .07, y - .07), Vector2(.38, .38), 5, cap)
 # The draw transform positions the underside six pixels below the floor.
 ci.draw_set_transform(Vector2(0, -height + 6))
 Iso.box(ci, r.position, r.size, 6, cap)
 ci.draw_set_transform(Vector2.ZERO)
 # Open diagonal steel bracing under the two long deck edges.
 for y in [r.position.y + .25, r.end.y - .25]:
  var left := Iso.to_screen(Vector2(r.position.x + .28, y))
  var right := Iso.to_screen(Vector2(r.end.x - .28, y))
  var middle := (left + right) * .5
  ci.draw_line(left + Vector2(0, -height + 8), middle + Vector2(0, -height * .40), steel, 3, true)
  ci.draw_line(middle + Vector2(0, -height * .40), right + Vector2(0, -height + 8), steel, 3, true)

## Enamel instrument panels and narrow brass mullions follow each real wall.
static func _clock_wall(ci: CanvasItem,at: Vector2,length: float,axis: String,height: float,glass: bool) -> void:
 if length<.5:return
 var along := Vector2.RIGHT if axis=="x" else Vector2.DOWN
 var point := func(t: float,z: float) -> Vector2:return Iso.to_screen(at+along*t)+Vector2(0,-z)
 var brass := Color("#C7A875")
 var enamel := Color("#B6B8AC")
 var slate := Color("#3D505A")
 ci.draw_line(point.call(0,height),point.call(length,height),brass,3,true)
 ci.draw_line(point.call(0,5),point.call(length,5),enamel,4,true)
 if height<35:return
 var bays := maxi(1,int(length/1.7))
 for i in range(bays+1):
  var t := length*i/bays
  ci.draw_line(point.call(t,0),point.call(t,height),enamel,4,true)
  ci.draw_line(point.call(t,height-12),point.call(t,height-3),brass,5,true)
 for bay in range(bays):
  var left := length*bay/bays+.14
  var right := length*(bay+1)/bays-.14
  var mid := (left+right)*.5
  if glass:
   ci.draw_line(point.call(mid,8),point.call(mid,height-4),brass,1.5,true)
   ci.draw_line(point.call(left,height*.45),point.call(right,height*.45),brass,1.5,true)
  else:
   var panel := PackedVector2Array([point.call(left,12),point.call(left,height-12),point.call(right,height-12),point.call(right,12),point.call(left,12)])
   ci.draw_polyline(panel,Color(slate,.6),1.3,true)
   if height>=48:
    var ring := PackedVector2Array()
    var radius := minf(.32,(right-left)*.30)
    var z := height*.55
    for i in range(49):
     var a := TAU*i/48
     ring.append(point.call(mid+cos(a)*radius,z+sin(a)*10))
    Iso.fill(ci, ring,enamel)
    ci.draw_polyline(ring,brass,2,true)
    ci.draw_line(point.call(mid,z),point.call(mid-radius*.55,z+4),slate,1.5,true)
    ci.draw_line(point.call(mid,z),point.call(mid+radius*.65,z+5),slate,1.2,true)

## Palace boiserie: rose panels, curved gold mouldings and cream pilasters.
static func _palace_wall(ci: CanvasItem,at: Vector2,length: float,axis: String,height: float) -> void:
 if length<.5:return
 var along := Vector2.RIGHT if axis=="x" else Vector2.DOWN
 var point := func(t: float,z: float) -> Vector2:return Iso.to_screen(at+along*t)+Vector2(0,-z)
 var cream := Color("#D4C5AE")
 var gold := Color("#C8AE74")
 ci.draw_line(point.call(0,height),point.call(length,height),cream,5,true)
 ci.draw_line(point.call(0,5),point.call(length,5),cream,4,true)
 if height<35:return
 var bays := maxi(1,int(length/1.7))
 for bay in range(bays):
  var left := length*bay/bays+.17
  var right := length*(bay+1)/bays-.17
  var mid := (left+right)*.5
  var panel := PackedVector2Array([point.call(left,12)])
  for i in range(25):
   var a := PI-i*PI/24
   panel.append(point.call(mid+cos(a)*(right-left)*.5,height-20+sin(a)*10))
  panel.append(point.call(right,12));panel.append(panel[0])
  Iso.fill(ci, panel,Color("#9E7C80"))
  ci.draw_polyline(panel,gold,1.8,true)
  if height>=50:
   var center: Vector2=point.call(mid,height*.52)
   for i in range(4):
    var a := PI/4+i*PI/2
    ci.draw_circle(center+Vector2(cos(a)*2.8,sin(a)*2.8),2.5,cream,true,-1,true)
   ci.draw_circle(center,1.7,gold,true,-1,true)
 for i in range(bays+1):
  var t := length*i/bays
  ci.draw_line(point.call(t,0),point.call(t,height),cream,5,true)
  ci.draw_line(point.call(t-.08,height-5),point.call(t+.08,height-5),gold,3,true)

## Finale museum: silver-blue instrument panels and arched observatory ribs.
static func _worlds_wall(ci: CanvasItem,at: Vector2,length: float,axis: String,height: float,glass: bool) -> void:
 if length<.5:return
 var along := Vector2.RIGHT if axis=="x" else Vector2.DOWN
 var point := func(t: float,z: float) -> Vector2:return Iso.to_screen(at+along*t)+Vector2(0,-z)
 var stone := Color("#C6C9BB")
 var bronze := Color("#C8B17A")
 var blue := Color("#4F6071")
 ci.draw_line(point.call(0,height),point.call(length,height),stone,4,true)
 ci.draw_line(point.call(0,5),point.call(length,5),stone,4,true)
 if height<35:return
 var bays := maxi(1,int(length/1.9))
 for bay in range(bays):
  var left := length*bay/bays+.12
  var right := length*(bay+1)/bays-.12
  var mid := (left+right)*.5
  var panel := PackedVector2Array([point.call(left,9)])
  for i in range(25):
   var a := PI-i*PI/24
   panel.append(point.call(mid+cos(a)*(right-left)*.5,height-20+sin(a)*14))
  panel.append(point.call(right,9))
  if not glass:Iso.fill(ci, panel,blue)
  ci.draw_polyline(panel,stone,2.5,true)
  if glass:
   ci.draw_line(point.call(mid,9),point.call(mid,height-6),bronze,1.5,true)
   ci.draw_line(point.call(left,height*.45),point.call(right,height*.45),bronze,1.5,true)
  else:
   var ellipse := PackedVector2Array()
   for i in range(49):
    var a := i*TAU/48
    ellipse.append(point.call(mid+cos(a)*minf(.28,(right-left)*.3),height*.53+sin(a)*10))
   ci.draw_polyline(ellipse,bronze,1.6,true)
   var c: Vector2=point.call(mid,height*.53)
   ci.draw_line(c+Vector2(-4,0),c+Vector2(4,0),stone,1.3,true)
   ci.draw_line(c+Vector2(0,-6),c+Vector2(0,6),stone,1.3,true)
 for i in range(bays+1):
  var t := length*i/bays
  ci.draw_line(point.call(t,0),point.call(t,height),stone,4,true)

## A raised flight spans between supported landings. Treads and sloping steel
## stringers have their own thickness; none extrudes down to the pavement.
## Heights are absolute so upper-floor callers can cancel their storey offset.
static func raised_stair_flight(ci: CanvasItem,r: Rect2,bottom: float,top: float,along_x: bool,reverse: bool,stone: Color,runner: Color) -> void:
 var along := Vector2.RIGHT if along_x else Vector2.DOWN
 var across := Vector2.DOWN if along_x else Vector2.RIGHT
 var length := r.size.x if along_x else r.size.y
 var width := r.size.y if along_x else r.size.x
 var height_at := func(t: float) -> float:return lerpf(bottom,top,1.0-t if reverse else t)
 var point := func(t: float,cross_: float,z: float) -> Vector2:
  return Iso.to_screen(r.position+along*length*t+across*cross_)+Vector2(0,-z)
 var steel := stone.darkened(.48)
 # Twin stringers carry the entire run into the adjacent landing edges.
 for cross_ in [.16,width-.16]:
  var a: Vector2 = point.call(0,cross_,height_at.call(0)-3)
  var b: Vector2 = point.call(1,cross_,height_at.call(1)-3)
  Iso.fill(ci, PackedVector2Array([a,b,b+Vector2(0,7),a+Vector2(0,7)]),steel)
 for i in Iso.STAIR_TREADS:
  var t := float(i)/Iso.STAIR_TREADS
  var z: float = height_at.call(float(i if reverse else i+1)/Iso.STAIR_TREADS)
  var pos := r.position+along*length*t
  var size := Vector2(length/Iso.STAIR_TREADS,width) if along_x else Vector2(width,length/Iso.STAIR_TREADS)
  var q := Iso.quad(pos,size)
  for j in q.size():q[j].y -= z
  var thickness := absf(top-bottom)/Iso.STAIR_TREADS+1.0
  for face in [[1,2],[2,3]]:
   var a: Vector2 = q[face[0]]
   var b: Vector2 = q[face[1]]
   Iso.fill(ci, PackedVector2Array([a,b,b+Vector2(0,thickness),a+Vector2(0,thickness)]),Iso.shade(stone,.26))
  Iso.fill(ci, q,stone.lightened(.10))
  var carpet := Iso.quad(pos+across*width*.22,size-across*width*.44)
  for j in carpet.size():carpet[j].y -= z+.5
  Iso.fill(ci, carpet,runner)
  ci.draw_line(q[2],q[3],stone.lightened(.25),1.1,true)
 stair_handrails(ci,r,bottom,top,along_x,reverse,stone.lightened(.23))

static func stair_handrails(ci: CanvasItem,r: Rect2,bottom: float,top: float,along_x: bool,reverse: bool,col: Color) -> void:
 var along := Vector2.RIGHT if along_x else Vector2.DOWN
 var across := Vector2.DOWN if along_x else Vector2.RIGHT
 var length := r.size.x if along_x else r.size.y
 var width := r.size.y if along_x else r.size.x
 var height_at := func(t: float) -> float:return lerpf(bottom,top,1.0-t if reverse else t)
 var point := func(t: float,cross_: float,z: float) -> Vector2:
  return Iso.to_screen(r.position+along*length*t+across*cross_)+Vector2(0,-z)
 # Handrails finish at actual landing elevations and leave both ends open.
 for cross_ in [.08,width-.08]:
  for t in [0.0,.33,.67,1.0]:
   var z: float = height_at.call(t)
   ci.draw_line(point.call(t,cross_,z),point.call(t,cross_,z+19),col.darkened(.30),2.2,true)
  ci.draw_line(point.call(0,cross_,height_at.call(0)+19),point.call(1,cross_,height_at.call(1)+19),col,3,true)
