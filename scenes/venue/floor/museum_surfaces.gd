extends RefCounted
## Architectural finish kits. Pure drawing: no simulation or save state changes.
const Iso := preload("res://scenes/venue/floor/iso.gd")
const KITS := {
 "whispering_pines": ["parquet", "#d9c7a4", "#66816b", "#b39358", "leaf"],
 "copper_kettle": ["wave", "#dce9e5", "#599ba5", "#e1aa84", "tide"],
 "grand_river": ["plank", "#be956f", "#675944", "#e2c593", "compass"],
 "sunspire": ["mosaic", "#e3c9a0", "#516e91", "#b57b48", "sun"],
 "cloudrest": ["slate", "#cbd4d4", "#6b8490", "#dfd5b8", "compass"],
 "aurora_world": ["crystal", "#d9e5e7", "#849bb1", "#afd8cb", "snow"],
 "celestial_conservatory": ["slate", "#dedec6", "#6d856c", "#bda56a", "leaf"],
 "ironwood_citadel": ["slate", "#bfc0ae", "#677167", "#b89458", "shield"],
 "pelagic_crown": ["wave", "#bed6d7", "#4e7a8b", "#bbbd9a", "shell"],
 "chronos_spire": ["plank", "#c6ad8e", "#736657", "#b98d4c", "gear"],
 "empyrean_palace": ["mosaic", "#e6dacb", "#957877", "#bc995f", "star"],
 "infinite_museum": ["crystal", "#d7d5e1", "#84879e", "#bba89b", "orbit"],
}

static func paint(ci: CanvasItem, r: Rect2, venue: String, room: Dictionary) -> void:
 if not KITS.has(venue):
  Iso.floor_patch(ci,r.position,r.size,room["floor"])
  return
 var kit: Array = KITS[venue]
 if venue == "celestial_conservatory" and str(room.get("id","")) in ["east_arc","west_arc"]:
  kit=["mosaic","#c5cfae","#70896c","#bda56a","leaf"]
 if venue == "empyrean_palace":
  if str(room.get("id","")) == "west_palace":kit=["parquet","#C4AD94","#866E69","#C8AE74","star"]
  elif str(room.get("id","")) == "east_palace":kit=["slate","#C3C7B5","#819389","#C8AE74","star"]
 if venue=="copper_kettle" and str(room.get("id",""))=="promenade":
  kit=["plank","#b9beb2","#688b91","#d3ba8d","tide"]
 elif venue=="copper_kettle" and str(room.get("id",""))=="salt_garden":
  kit=["slate","#c9d3bc","#739785","#d3ba8d","leaf"]
 if venue=="grand_river" and str(room.get("id","")) in ["scholars_court","portico"]:
  kit=["slate","#d2c9b0","#7e8063","#b99b62","compass"]
 var base := Color(kit[1])
 var ink := Color(kit[2])
 var brass := Color(kit[3])
 var is_gallery: bool = str(room.get("dept", "")) == "gallery" or str(room.get("id", "")) == "gallery"
 Iso.floor_patch(ci,r.position,r.size,base)
 # Narrow links and stairs remain quiet and clear.
 if r.size.x < 2.5 or r.size.y < 2.5 or int(room.get("rise_to", 0)) != int(room.get("level", 0)):
  return
 var inset := r.grow(-0.22)
 var ring := Iso.quad(inset.position,inset.size)
 ring.append(ring[0])
 ci.draw_polyline(ring,ink.lightened(.18),2.0,true)
 var inner := r.grow(-0.34)
 var ring2 := Iso.quad(inner.position,inner.size)
 ring2.append(ring2[0])
 ci.draw_polyline(ring2,brass,1.0,true)
 var fill := r.grow(-0.45)
 match str(kit[0]):
  "plank", "parquet":
   var y := fill.position.y
   var row := 0
   while y < fill.end.y:
    var x := fill.position.x
    while x < fill.end.x:
     var width := minf(1.25 if row % 2 == 0 else 1.65,fill.end.x-x)
     var height := minf(.42,fill.end.y-y)
     var shade := base.darkened(.055 if row%2==0 else .015)
     Iso.floor_patch(ci,Vector2(x,y),Vector2(width,height),shade,Color(ink,.12))
     if str(kit[0]) == "parquet":
      ci.draw_line(Iso.to_screen(Vector2(x,y)),Iso.to_screen(Vector2(x+width,y+height)),Color(ink,.14),1,true)
     x += width
    y += .42
    row += 1
  "wave":
   for band in range(5):
    var points := PackedVector2Array()
    for step in range(49):
     var t := float(step)/48.0
     var p := Vector2(fill.position.x+t*fill.size.x,fill.position.y+fill.size.y*(.12+.19*band)+sin(t*TAU+band*.45)*minf(.16,fill.size.y*.025))
     points.append(Iso.to_screen(p))
    ci.draw_polyline(points,Color(ink,.28),2.5,true)
  "mosaic", "crystal", "slate":
   var step := 1.1 if str(kit[0]) == "slate" else .9
   var x := fill.position.x
   var ix := 0
   while x < fill.end.x:
    var y := fill.position.y
    var iy := 0
    while y < fill.end.y:
     var size := Vector2(minf(step,fill.end.x-x),minf(step,fill.end.y-y))
     var shade := base.darkened(.04 if (ix+iy)%2 else 0)
     Iso.floor_patch(ci,Vector2(x,y),size,shade,Color(ink,.10))
     if str(kit[0]) != "slate" and (ix+iy)%2 == 0 and size.x > .6 and size.y > .6:
      var c := Vector2(x,y)+size*.5
      polygon(ci,[c+Vector2(0,-.14),c+Vector2(.14,0),c+Vector2(0,.14),c+Vector2(-.14,0)],Color(ink,.32))
     y += step
     iy += 1
    x += step
    ix += 1
 if is_gallery or str(room.get("id", "")) in ["lobby","central_atrium"]:
  medallion(ci,fill.get_center(),minf(1.1,minf(fill.size.x,fill.size.y)*.27),str(kit[4]),base,ink,brass)
 elif venue=="ironwood_citadel" and str(room.get("id",""))=="lower_court":
  medallion(ci,fill.position+Vector2(fill.size.x*.27,fill.size.y*.5),.8,"shield",base,ink,brass)

static func polygon(ci: CanvasItem, points: Array, color: Color) -> void:
 var projected := PackedVector2Array()
 for p in points:projected.append(Iso.to_screen(p))
 Iso.fill(ci, projected,color)

static func medallion(ci: CanvasItem, center: Vector2, radius: float, motif: String, base: Color, ink: Color, brass: Color) -> void:
 var ring := PackedVector2Array()
 for i in range(65):ring.append(Iso.to_screen(center+Vector2.from_angle(i*TAU/64.0)*radius))
 Iso.fill(ci, ring,base.lightened(.08))
 ci.draw_polyline(ring,brass,2,true)
 if motif=="shield":
  polygon(ci,[center+Vector2(-.45,-.50)*radius,center+Vector2(.45,-.50)*radius,center+Vector2(.40,.15)*radius,center+Vector2(0,.62)*radius,center+Vector2(-.40,.15)*radius],ink)
  ci.draw_line(Iso.to_screen(center+Vector2(0,-.40)*radius),Iso.to_screen(center+Vector2(0,.35)*radius),brass,2,true)
  ci.draw_line(Iso.to_screen(center+Vector2(-.28,-.12)*radius),Iso.to_screen(center+Vector2(.28,-.12)*radius),brass,2,true)
  return
 var count := 12 if motif in ["sun","gear","shell"] else 8
 for i in range(count):
  var angle := i*TAU/count
  var a := Vector2.from_angle(angle)
  var b := Vector2.from_angle(angle+.16)
  if motif in ["leaf","tide","orbit","shell"]:
   var points := PackedVector2Array()
   for j in range(13):
    var t := j/12.0
    var p := center+Vector2.from_angle(angle+t*.55)*radius*(.22+.62*t)
    points.append(Iso.to_screen(p))
   ci.draw_polyline(points,Color(ink,.62),2,true)
  else:
   polygon(ci,[center+a*radius*.20,center+a*radius*.82,center+b*radius*.42],Color(ink,.65))
