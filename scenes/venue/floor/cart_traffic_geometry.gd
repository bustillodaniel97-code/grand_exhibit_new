extends RefCounted
## Ground-plane body/cart geometry. Height filtering belongs to the venue.
const REAR := -.20
const FRONT := .68
const HALF_WIDTH := .24
const VISITOR_RADIUS := .22

static func heading(porter: Variant) -> Vector2:
	if not porter.motion_step.is_empty() and bool(porter.motion_step.turn):
		return porter.heading.rotated(porter.heading.angle_to(porter.motion_step.heading)*porter.turn_progress)
	return porter.heading

static func polygon(at: Vector2,front: Vector2,padding: float=0.0) -> PackedVector2Array:
	var right:=Vector2(front.y,-front.x)
	return PackedVector2Array([at+front*(REAR-padding)-right*(HALF_WIDTH+padding),at+front*(FRONT+padding)-right*(HALF_WIDTH+padding),at+front*(FRONT+padding)+right*(HALF_WIDTH+padding),at+front*(REAR-padding)+right*(HALF_WIDTH+padding)])

static func point_distance(point: Vector2,at: Vector2,front: Vector2) -> float:
	var offset:=point-at
	var along:=offset.dot(front)
	var across:=absf(offset.dot(Vector2(front.y,-front.x)))
	return Vector2(maxf(maxf(REAR-along,along-FRONT),0.0),maxf(across-HALF_WIDTH,0.0)).length()

## Overlap depth for two oriented carts: 0 when separated, and the minimum
## separating-axis penetration otherwise. Sibling of overlap() that lets the
## runtime guard tell "already intersecting and getting worse" from "already
## intersecting and pulling apart" - a boolean cannot.
static func penetration(a: Vector2,ah: Vector2,b: Vector2,bh: Vector2,padding: float=0.0) -> float:
	var ac:=a+ah*((FRONT+REAR)*.5);var bc:=b+bh*((FRONT+REAR)*.5)
	var ar:=Vector2(ah.y,-ah.x);var br:=Vector2(bh.y,-bh.x)
	var half:=(FRONT-REAR)*.5+padding;var width:=HALF_WIDTH+padding
	var depth:=INF
	for axis in [ah,ar,bh,br]:
		var radius_a: float=half*absf(axis.dot(ah))+width*absf(axis.dot(ar))
		var radius_b: float=half*absf(axis.dot(bh))+width*absf(axis.dot(br))
		var gap: float=radius_a+radius_b-absf((bc-ac).dot(axis))
		if gap<=.000001:return 0.0
		depth=minf(depth,gap)
	return depth if depth!=INF else 0.0

static func overlap(a: Vector2,ah: Vector2,b: Vector2,bh: Vector2,padding: float=0.0) -> bool:
	# Separating-axis test avoids allocating intersection polygons per pair.
	var ac:=a+ah*((FRONT+REAR)*.5);var bc:=b+bh*((FRONT+REAR)*.5)
	var ar:=Vector2(ah.y,-ah.x);var br:=Vector2(bh.y,-bh.x)
	var half:=(FRONT-REAR)*.5+padding;var width:=HALF_WIDTH+padding
	for axis in [ah,ar,bh,br]:
		var radius_a: float=half*absf(axis.dot(ah))+width*absf(axis.dot(ar))
		var radius_b: float=half*absf(axis.dot(bh))+width*absf(axis.dot(br))
		if absf((bc-ac).dot(axis))>=radius_a+radius_b-.000001:return false
	return true
