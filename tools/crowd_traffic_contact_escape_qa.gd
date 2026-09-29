extends "res://scenes/venue/floor/crowd_traffic.gd"
## QA-only recovery. Never wired into the production venue.
## Signed distance preserves progress while a guest is inside a rectangle;
## production's unsigned distance is zero throughout that interior.
func _surface_distance(point:Vector2,pose:Dictionary)->float:
 var offset:=point-(pose.at as Vector2)
 var front:Vector2=pose.heading;var right:=Vector2(front.y,-front.x)
 var half:=(Geometry.FRONT-Geometry.REAR)*.5
 var q:=Vector2(absf(offset.dot(front)-(Geometry.FRONT+Geometry.REAR)*.5)-half,absf(offset.dot(right))-Geometry.HALF_WIDTH)
 return Vector2(maxf(q.x,0.0),maxf(q.y,0.0)).length()+minf(maxf(q.x,q.y),0.0)
func _separation_slope(point:Vector2,delta:Vector2,pose:Dictionary)->float:
 var front:Vector2=pose.heading;var right:=Vector2(front.y,-front.x)
 var offset:=point-(pose.at as Vector2)
 var local:=Vector2(offset.dot(front)-(Geometry.FRONT+Geometry.REAR)*.5,offset.dot(right))
 var velocity:=Vector2(delta.dot(front),delta.dot(right))
 var q:=local.abs()-Vector2((Geometry.FRONT-Geometry.REAR)*.5,Geometry.HALF_WIDTH)
 var slope:=Vector2(signf(local.x)*velocity.x if local.x!=0.0 else absf(velocity.x),signf(local.y)*velocity.y if local.y!=0.0 else absf(velocity.y))
 var outside:=Vector2(maxf(q.x,0.0),maxf(q.y,0.0))
 if outside.length_squared()>0.0:return outside.normalized().dot(slope)
 # The maximum of active face distances gives the exact one-sided derivative
 # inside/on a convex rectangle, including equal-distance corners and centre.
 if q.x>q.y:return slope.x
 if q.y>q.x:return slope.y
 return maxf(slope.x,slope.y)
func visitor_clear(v:Variant,next:Vector2)->bool:
 var height:float=floor_node._porter_layout._height_at(v.pos)
 for pose in cart_poses:
  if absf(height-pose.height)>=HEIGHT_CLEARANCE or v.pos.distance_squared_to(pose.at)>6.25:continue
  var current:=_surface_distance(v.pos,pose)
  if current>=RADIUS+MARGIN:
   # Recovering from another cart must never waive this cart's admission guard.
   if overlaps_segment(v.pos,next,pose):return false
   continue
  var delta:Vector2=next-v.pos
  if delta.length_squared()<.00000001:return false
  # A positive initial derivative and endpoint gain forbid passing through the
  # cart to a farther exit. Signed distance to this convex box is convex along
  # a straight step, so these conditions give monotonic outward separation.
  if _separation_slope(v.pos,delta,pose)<=.0000001:return false
  if _surface_distance(next,pose)<=current+.0000001:return false
 return true
