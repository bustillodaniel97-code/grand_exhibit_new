extends RefCounted
## Finite journeys through the district, in the same nominal grid as the roads.
## Pools are recycled only after a whole trip, never at a viewport boundary.
static func main_route(city: Node, forward: bool) -> PackedVector2Array:
 var d: Dictionary=city.district.design
 var west:=NAN;var east:=NAN
 for row in d.get("roads",[]):
  var r:=Rect2(row[0],row[1],row[2],row[3])
  if r.size.y>r.size.x and r.end.y>=city.ROAD_B-.01:
   if r.position.x<0:west=r.position.x
   else:east=r.position.x
 var north:=float(d.get("north_axis",-4.3))
 var west_exit: bool=d.get("roads",[]).is_empty() or float(d.roads[0][0])<=-20
 var p:=PackedVector2Array()
 if forward:
  if is_finite(west):p.append(Vector2(-20 if west_exit else 35,north+.65 if west_exit else north+1.65));p.append(Vector2(west+.65,north+.65 if west_exit else north+1.65));p.append(Vector2(west+.65,city.LANE_OUT))
  else:p.append(Vector2(-30,city.LANE_OUT))
  if is_finite(east):p.append(Vector2(east+1.65,city.LANE_OUT));p.append(Vector2(east+1.65,north+.65));p.append(Vector2(35,north+.65))
  else:p.append(Vector2(36,city.LANE_OUT))
 else:
  if is_finite(east):p.append(Vector2(35,north+1.65));p.append(Vector2(east+.65,north+1.65));p.append(Vector2(east+.65,city.LANE_IN))
  else:p.append(Vector2(36,city.LANE_IN))
  if is_finite(west):p.append(Vector2(west+1.65,city.LANE_IN));p.append(Vector2(west+1.65,north+1.65 if west_exit else north+.65));p.append(Vector2(-20 if west_exit else 35,north+1.65 if west_exit else north+.65))
  else:p.append(Vector2(-30,city.LANE_IN))
 return rounded(p)

static func rounded(points: PackedVector2Array) -> PackedVector2Array:
 var out:=PackedVector2Array([points[0]])
 for i in range(1,points.size()-1):
  var p:=points[i];var incoming:=(p-points[i-1]).normalized();var outgoing:=(points[i+1]-p).normalized()
  var radius:=minf(.45,minf(p.distance_to(points[i-1]),p.distance_to(points[i+1]))*.4)
  if absf(incoming.dot(outgoing))>.99:out.append(p);continue
  var a:=p-incoming*radius;var b:=p+outgoing*radius
  out.append(a)
  for j in range(1,9):
   var t:=float(j)/8;out.append(a*(1-t)*(1-t)+p*2*(1-t)*t+b*t*t)
 out.append(points[-1]);return out

static func position_car(car: Dictionary,at: Vector2,delta: Vector2) -> void:
 car.gx=at.x;car.gy=at.y
 car.axis=Vector2.RIGHT if absf(delta.x)>absf(delta.y) else Vector2.DOWN
 car.dir=signf(delta.dot(car.axis))

static func start(car: Dictionary,points: PackedVector2Array,from_current: bool=false) -> void:
 car.route=points;car.segment=0;car.wait=0.0
 if from_current:
  var at:=Vector2(car.gx,car.gy)
  for i in range(points.size()-1):
   if absf(points[i].y-at.y)<.001 and absf(points[i+1].y-at.y)<.001 and at.x>=minf(points[i].x,points[i+1].x) and at.x<=maxf(points[i].x,points[i+1].x):car.segment=i;position_car(car,at,points[i+1]-points[i]);return
 position_car(car,points[0],points[1]-points[0])

static func step(car: Dictionary,distance: float) -> bool:
 var points: PackedVector2Array=car.route
 var at:=Vector2(car.gx,car.gy)
 while distance>0:
  var target: Vector2=points[int(car.segment)+1];var delta:=target-at;var length:=delta.length()
  if length>distance:
   position_car(car,at+delta/length*distance,delta);return false
  distance-=length;at=target;position_car(car,at,delta)
  car.segment+=1
  if int(car.segment)>=points.size()-1:return true
 return false
