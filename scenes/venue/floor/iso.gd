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

## The canvas VenueFloor fits the diorama into and CLIPS to. Letting the diamond
## overhang it is deliberate; putting content out there is not. The archive's
## vault door (x=750), its money pile (x=756), the far half of its shelving
## (x=768) and one lobby planter (x=-30) were all drawn outside this rect and had
## never once been visible on a phone. `gx_window` is the placement rule that
## replaced eyeballing it, and tests/venue/test_geometry.gd holds the line.
const VIEW := Vector2(720.0, 760.0)

static func to_screen(g: Vector2) -> Vector2:
	return ORIGIN + Vector2((g.x - g.y) * TILE.x * 0.5, (g.x + g.y) * TILE.y * 0.5)

## Inverse projection — canvas point back to grid coords (used by tap routing).
static func to_grid(s: Vector2) -> Vector2:
	var p: Vector2 = s - ORIGIN
	var a: float = p.x / (TILE.x * 0.5)
	var b: float = p.y / (TILE.y * 0.5)
	return Vector2((b + a) * 0.5, (b - a) * 0.5)

## Is a grid point inside the visible canvas, keeping `inset` px clear of the edge?
static func on_canvas(g: Vector2, inset: float = 0.0) -> bool:
	var s := to_screen(g)
	return s.x >= inset and s.x <= VIEW.x - inset \
		and s.y >= inset and s.y <= VIEW.y - inset

## The gx range visible at a given depth row, as [min, max], with `inset` px of
## margin. Because the projection shears x by -gy, the visible window slides one
## tile right for every tile of depth: at the back of the hall only gx <= 11 is
## on screen, at the front only gx >= 3 is. Every prop and waypoint is placed
## against this, which is why the archive's furniture now steps forward as it
## runs east instead of marching off the edge.
static func gx_window(gy: float, inset: float = 0.0) -> Vector2:
	var half := TILE.x * 0.5
	return Vector2(gy + (inset - ORIGIN.x) / half, gy + (VIEW.x - inset - ORIGIN.x) / half)

## Stroke a path as a run of draw_line calls instead of one draw_polyline.
##
## MEASURED under GL Compatibility (tests/venue/_probe_prims.gd): 100
## draw_line calls cost ONE draw call and 100 draw_rect calls cost one, while
## 100 draw_polyline, draw_colored_polygon, draw_circle or draw_arc calls cost a
## hundred. Strokes are most of the ink on this floor — every outline, every
## velvet rope, every bunting string — so routing them through here is what let
## the prop count roughly double while the frame got cheaper. The only thing
## lost against draw_polyline is mitred joints, which are invisible at these
## widths.
static func stroke(ci: CanvasItem, pts: PackedVector2Array, col: Color, w: float) -> void:
	for i in range(1, pts.size()):
		ci.draw_line(pts[i - 1], pts[i], col, w)

## A small round-reading blob built from two crossed rects, for the same reason:
## draw_circle costs a draw call apiece and there are dozens of 3-5px highlights
## on this floor. Crossed rects batch, and at that size, upscaled to a phone, the
## silhouette is indistinguishable from a disc.
static func pip(ci: CanvasItem, c: Vector2, r: float, col: Color) -> void:
	ci.draw_rect(Rect2(c.x - r, c.y - r * 0.62, r * 2.0, r * 1.24), col)
	ci.draw_rect(Rect2(c.x - r * 0.62, c.y - r, r * 1.24, r * 2.0), col)

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
		stroke(ci, ring, seam, 1.5)

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
		stroke(ci, PackedVector2Array([
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
		stroke(ci, ring, outline, 1.6)

## A framed picture on a wall: brass frame, mount, then the picture. Three
## `panel` calls in a row, so consecutive frames batch into one draw call —
## which is why the walls can now carry a dozen of these for the price of one.
static func picture(ci: CanvasItem, g: Vector2, length: float, axis: String,
		bottom: float, top: float, art: Color, sky: Color = Color(0, 0, 0, 0)) -> void:
	var pad: float = length * 0.10
	panel(ci, g, length, axis, bottom, top, Color("#C08B33"))
	panel(ci, g + (Vector2(pad, 0.0) if axis == "x" else Vector2(0.0, pad)),
		length - pad * 2.0, axis, bottom + 3.0, top - 3.0,
		sky if sky.a > 0.0 else art.lightened(0.45), Color(0, 0, 0, 0))
	if sky.a > 0.0:
		panel(ci, g + (Vector2(pad, 0.0) if axis == "x" else Vector2(0.0, pad)),
			length - pad * 2.0, axis, bottom + 3.0, (bottom + top) * 0.5,
			art, Color(0, 0, 0, 0))

## Flat decal painted on the floor plane — rugs, runners, standing zones, mats.
## Occludes nothing, so it lives in the ground canvas item and costs no node.
static func rug(ci: CanvasItem, g: Vector2, size: Vector2, col: Color,
		border: Color = Color(0, 0, 0, 0)) -> void:
	ci.draw_colored_polygon(quad(g, size), col)
	if border.a > 0.0:
		var ring := quad(g + Vector2(0.16, 0.16), size - Vector2(0.32, 0.32))
		ring.append(ring[0])
		stroke(ci, ring, border, 2.0)

## Upright cylinder — bins, urns, columns, drums. `r` is a radius in tiles, so
## the footprint stays a proper iso ellipse instead of a screen-space circle.
static func cyl(ci: CanvasItem, g: Vector2, r: float, height: float, col: Color) -> void:
	var c := to_screen(g)
	var rx: float = r * TILE.x
	var ry: float = r * TILE.y
	var up := Vector2(0.0, -height)
	var side := PackedVector2Array()
	for i in 13:
		var an: float = PI * float(i) / 12.0
		side.append(c + Vector2(cos(an) * rx, sin(an) * ry))
	for i in range(12, -1, -1):
		var an: float = PI * float(i) / 12.0
		side.append(c + Vector2(cos(an) * rx, sin(an) * ry) + up)
	ci.draw_colored_polygon(side, col.darkened(0.24))
	var top := PackedVector2Array()
	for i in 24:
		var an: float = TAU * float(i) / 24.0
		top.append(c + Vector2(cos(an) * rx, sin(an) * ry) + up)
	ci.draw_colored_polygon(top, col)

## Bunting strung between two points at wall-top height, sagging in between.
## The reference hangs these across every room; they are the cheapest thing on
## the floor that reads as "somebody decorated this".
static func bunting(ci: CanvasItem, a: Vector2, b: Vector2, height: float,
		sag: float, cols: Array, flags: int = 9) -> void:
	var pa := to_screen(a) + Vector2(0.0, -height)
	var pb := to_screen(b) + Vector2(0.0, -height)
	var line := PackedVector2Array()
	for i in 17:
		var t: float = float(i) / 16.0
		line.append(pa.lerp(pb, t) + Vector2(0.0, sin(t * PI) * sag))
	stroke(ci, line, Color(0.20, 0.14, 0.26, 0.85), 1.6)
	for i in flags:
		var t: float = (float(i) + 0.5) / float(flags)
		var p: Vector2 = pa.lerp(pb, t) + Vector2(0.0, sin(t * PI) * sag)
		ci.draw_colored_polygon(PackedVector2Array([
			p + Vector2(-4.6, 0.0), p + Vector2(4.6, 0.0), p + Vector2(0.0, 11.5)]),
			cols[i % cols.size()])
