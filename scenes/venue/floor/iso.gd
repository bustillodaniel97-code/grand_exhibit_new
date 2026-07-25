extends RefCounted
## Iso — the museum's isometric projection and its drawing primitives.
##
## Everything about the floor lives in GRID space (tiles, +x to the upper-right,
## +y to the lower-right) and is projected to canvas space only at draw time.
## Keeping the simulation in grid units is what let the visitor FSM survive the
## move from the old flat plan to this diorama untouched — only the waypoint
## constants changed units.
##
## Projection is a standard 2:1-ish dimetric:
##   screen.x = (g.x - g.y) * TILE.x/2
##   screen.y = (g.x + g.y) * TILE.y/2
## so screen.y increases with depth, which means Godot's built-in Y-sorting
## orders actors and props correctly for free.

## An iso diamond's bounding box is always (grid.x + grid.y) * TILE/2 on BOTH
## axes, so its aspect is fixed by the tile ratio alone — you cannot make it
## fill a portrait screen by reshaping the floor plan. The reference games solve
## this by drawing the floor larger than the viewport and letting the left and
## right corners run off the edges, which is what these numbers do: the diamond
## is 960 wide against a 720 canvas, and VenueFloor clips the overflow.
const TILE := Vector2(60.0, 40.0)     # one floor tile, projected
const ORIGIN := Vector2(390.0, 80.0)  # grid (0,0) in canvas space
const GRID := Vector2(15.0, 17.0)     # museum footprint, in tiles
const WALL_H := 52.0                  # wall extrusion height, px

static func to_screen(g: Vector2) -> Vector2:
	return ORIGIN + Vector2((g.x - g.y) * TILE.x * 0.5, (g.x + g.y) * TILE.y * 0.5)

## Inverse projection — canvas point back to grid coords (used by tap routing).
static func to_grid(s: Vector2) -> Vector2:
	var p: Vector2 = s - ORIGIN
	var a: float = p.x / (TILE.x * 0.5)
	var b: float = p.y / (TILE.y * 0.5)
	return Vector2((b + a) * 0.5, (b - a) * 0.5)

## The four canvas corners of a grid-space rect, in draw order.
static func quad(g: Vector2, size: Vector2) -> PackedVector2Array:
	return PackedVector2Array([
		to_screen(g),
		to_screen(g + Vector2(size.x, 0.0)),
		to_screen(g + size),
		to_screen(g + Vector2(0.0, size.y)),
	])

## Filled floor patch with an optional darker seam around it.
static func floor_patch(ci: CanvasItem, g: Vector2, size: Vector2,
		col: Color, seam: Color = Color(0, 0, 0, 0)) -> void:
	var q := quad(g, size)
	ci.draw_colored_polygon(q, col)
	if seam.a > 0.0:
		var ring := q.duplicate()
		ring.append(q[0])
		ci.draw_polyline(ring, seam, 1.5)

## Grout grid inside a room, drawn tile by tile along both axes.
static func floor_tiles(ci: CanvasItem, g: Vector2, size: Vector2, seam: Color) -> void:
	for i in range(1, int(size.x)):
		ci.draw_line(to_screen(g + Vector2(i, 0.0)), to_screen(g + Vector2(i, size.y)), seam, 1.0)
	for j in range(1, int(size.y)):
		ci.draw_line(to_screen(g + Vector2(0.0, j)), to_screen(g + Vector2(size.x, j)), seam, 1.0)

## An extruded box: two lit side faces plus a top. The workhorse for counters,
## desks, plinths, shelving and benches — everything solid on the floor.
static func box(ci: CanvasItem, g: Vector2, size: Vector2, height: float,
		col: Color, outline: Color = Color(0, 0, 0, 0.30)) -> void:
	var back := to_screen(g)
	var right := to_screen(g + Vector2(size.x, 0.0))
	var front := to_screen(g + size)
	var left := to_screen(g + Vector2(0.0, size.y))
	var up := Vector2(0.0, -height)
	# Left face is turned away from the key light, right face catches it.
	ci.draw_colored_polygon(PackedVector2Array([left, front, front + up, left + up]),
		col.darkened(0.30))
	ci.draw_colored_polygon(PackedVector2Array([front, right, right + up, front + up]),
		col.darkened(0.14))
	ci.draw_colored_polygon(PackedVector2Array([back + up, right + up, front + up, left + up]), col)
	if outline.a > 0.0:
		ci.draw_polyline(PackedVector2Array([
			left + up, back + up, right + up, front + up, left + up, left, front, right]),
			outline, 1.4)
		ci.draw_line(front, front + up, outline, 1.4)

## A wall running along one grid edge, extruded upward. `axis` is "x" for a wall
## spanning the x direction (the north/back wall) or "y" for the west wall.
static func wall(ci: CanvasItem, g: Vector2, length: float, axis: String,
		col: Color, height: float = WALL_H) -> void:
	var a := to_screen(g)
	var b := to_screen(g + (Vector2(length, 0.0) if axis == "x" else Vector2(0.0, length)))
	var up := Vector2(0.0, -height)
	# Face, with a gradient so the wall reads as lit from above.
	ci.draw_polygon(PackedVector2Array([a + up, b + up, b, a]),
		PackedColorArray([col.darkened(0.30), col.darkened(0.30), col, col]))
	# Cap rail along the top edge.
	ci.draw_line(a + up, b + up, col.lightened(0.28), 2.4)
	ci.draw_line(a, b, col.darkened(0.45), 1.6)

## Soft contact shadow on the floor plane, shaped as a squashed iso diamond.
static func shadow(ci: CanvasItem, g: Vector2, size: Vector2, alpha: float = 0.16) -> void:
	ci.draw_colored_polygon(quad(g, size), Color(0.10, 0.06, 0.18, alpha))

## Upright flat panel standing on a wall — paintings, poster boards, signage.
## Drawn in the plane of the given axis so it sits flush against the wall face.
static func panel(ci: CanvasItem, g: Vector2, length: float, axis: String,
		bottom: float, top: float, col: Color, outline: Color = Color(0, 0, 0, 0.35)) -> void:
	var a := to_screen(g)
	var b := to_screen(g + (Vector2(length, 0.0) if axis == "x" else Vector2(0.0, length)))
	var lo := Vector2(0.0, -bottom)
	var hi := Vector2(0.0, -top)
	var poly := PackedVector2Array([a + hi, b + hi, b + lo, a + lo])
	ci.draw_colored_polygon(poly, col)
	if outline.a > 0.0:
		var ring := poly.duplicate()
		ring.append(poly[0])
		ci.draw_polyline(ring, outline, 1.6)
