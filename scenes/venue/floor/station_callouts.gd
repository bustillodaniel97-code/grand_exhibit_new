extends RefCounted
## Compact station action pairs retain real touch sizes while the world zooms.
## A deterministic layout changes only when station anchors or the viewport do.
const CARD := Vector2(100,48)
const GAP := 6.0
static func arrange(anchors: Array[Vector2], bounds: Rect2, exclusions: Array[Rect2]) -> Array[Rect2]:
 var result: Array[Rect2]=[]
 result.resize(anchors.size())
 var occupied: Array[Rect2]=exclusions.duplicate()
 var center:=Vector2.ZERO
 for point in anchors:center+=point
 if not anchors.is_empty():center/=anchors.size()
 var order: Array[int]=[]
 for i in anchors.size():
  if bounds.has_point(anchors[i]):order.append(i)
 order.sort_custom(func(a: int,b: int) -> bool:
  return anchors[a].x<anchors[b].x if is_equal_approx(anchors[a].y,anchors[b].y) else anchors[a].y<anchors[b].y)
 for index in order:
  var anchor: Vector2=anchors[index]
  var outward: Vector2=(anchor-center).normalized()
  if outward.is_zero_approx():outward=Vector2.UP
  var preferred:=anchor+outward*54.0
  var candidates: Array[Vector2]=[]
  for y in range(-3,4):
   for x in range(-3,4):candidates.append(preferred+Vector2(x*76,y*56)-CARD*.5)
  # Bounded fallback covers narrow and short views without shrinking controls.
  for y in range(int(bounds.position.y),int(bounds.end.y-CARD.y)+1,56):
   for x in range(int(bounds.position.x),int(bounds.end.x-CARD.x)+1,76):candidates.append(Vector2(x,y))
  var best:=Rect2()
  var score:=INF
  for pos in candidates:
   var rect:=Rect2(pos,CARD)
   if not bounds.encloses(rect):continue
   var clear:=true
   for obstacle in occupied:
    if rect.grow(GAP).intersects(obstacle):clear=false;break
   if not clear:continue
   # Keep desk anchors visible so the numbered leader still has a clear owner.
   for point in anchors:
    if rect.grow(10).has_point(point):clear=false;break
   if not clear:continue
   var cost:=rect.get_center().distance_squared_to(preferred)
   for other in range(result.size()):
    if not result[other].has_area():continue
    var a:=nearest_edge(rect,anchor)
    var b:=nearest_edge(result[other],anchors[other])
    if Geometry2D.segment_intersects_segment(anchor,a,anchors[other],b)!=null:cost+=2500.0
   if cost<score:score=cost;best=rect
  result[index]=best
  if best.has_area():occupied.append(best)
 return result

static func nearest_edge(rect: Rect2, point: Vector2) -> Vector2:
 return point.clamp(rect.position,rect.end)
