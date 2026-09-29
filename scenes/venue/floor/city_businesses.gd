extends RefCounted
## Real doors and continuous, road-free sidewalk approaches in nominal city space.
static func door(building: Dictionary) -> Vector2:
 var r:=Rect2(building.rect[0],building.rect[1],building.rect[2],building.rect[3])
 return Vector2(r.end.x+.24,r.position.y+r.size.y*.49) if building.face=="east" else Vector2(r.position.x+r.size.x*.51,r.end.y+.24)
static func name_for(building: Dictionary,index: int) -> String:
 match str(building.kind):
  "shop","arcade":return "BOOKSHOP" if index%2==0 else "CAFE"
  "lodge","townhouse","cottage":return "GUESTHOUSE"
  "warehouse":return "WORKSHOP"
  "civic","clock":return "LIBRARY"
  "greenhouse":return "FLOWERS"
  "glass":return "OFFICES"
  "terrace":return "APARTMENTS"
  "observatory":return "SCIENCE CLUB"
 return "CITY HALL"
static func connected(city: Node2D) -> Array:
 var out: Array=[];var d: Dictionary=city.district.design
 for i in d.get("buildings",[]).size():
  var b: Dictionary=d.buildings[i];var at:=door(b);var path: Array=[];var right:=false
  if d.network=="west" and float(b.rect[0])>21:
   right=true
   path=[city.NEAR_WALK_RIGHT,Vector2(21.325,18.42),Vector2(21.325,at.y+.355),Vector2(at.x,at.y+.355),at]
  elif d.network=="east" and b.face=="east":
   var lane:=float(d.west_axis)+1.15
   path=[city.NEAR_WALK_LEFT,Vector2(lane,18.42),Vector2(lane,at.y),at]
  if path.is_empty():continue
  var mapped: Array=[]
  for p in path:mapped.append(city.map_point(p))
  out.append({"id":i,"name":name_for(b,i),"door":city.map_point(at),"nominal_door":at,"path":mapped,"right":right})
 return out
static func frontage(city: Node2D) -> Array:
 var out: Array=[];var d: Dictionary=city.district.design
 for i in d.get("buildings",[]).size():
  var b: Dictionary=d.buildings[i];var at:=door(b)
  if b.face=="south" and at.y<float(d.north_axis) and at.y>float(d.north_axis)-3:
   out.append({"id":i,"door":at,"name":name_for(b,i)})
 return out
