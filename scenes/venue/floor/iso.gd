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

## Screen rise of one STOREY, in px.
##
## Elevation is a RENDER property here, never a simulation one: a level lifts
## what is DRAWN and nothing else. The FSM stays flat — every waypoint, queue
## slot and browse spot is a plain grid coordinate and pathing never learns
## about storeys — so a multi-storey venue adds no sim state and cannot
## introduce a class of pathing bug.
##
## Sized against WALL_H rather than picked by eye: a storey has to clear a full
## back wall plus its cap rail, or the floor above is drawn INSIDE the room below
## and the two read as one cluttered plane instead of as two floors.
const LEVEL_H := 74.0

## z_index band reserved per storey. Y-sort orders the diorama within a level;
## across levels the upper storey must win outright regardless of its projected
## y, so each level claims a band and the cast (0), cash floats (1) and room
## plaques (2) sit inside their own level's band.
const LEVEL_Z := 8
## Smaller risers keep feet close to the continuously interpolated stair surface.
const STAIR_TREADS := 14

## Screen offset of a storey. Negative because up is -y in canvas space.
static func level_lift(level: int) -> float:
	return -LEVEL_H * float(level)

## The canvas VenueFloor fits the diorama into and CLIPS to. Letting the diamond
## overhang it is deliberate; putting content out there is not. The archive's
## vault door (x=750), its money pile (x=756), the far half of its shelving
## (x=768) and one lobby planter (x=-30) were all drawn outside this rect and had
## never once been visible on a phone. `gx_window` is the placement rule that
## replaced eyeballing it, and tests/venue/test_geometry.gd holds the line.
const VIEW := Vector2(720.0, 760.0)

## The colour unlit faces tint TOWARD.
##
## `Color.darkened()` multiplies toward BLACK, so every shadowed face in the game
## slides toward grey mud on the way there — a crimson carpet's dark side and a
## teal wall's dark side converge on nearly the same colour, and the whole diorama
## reads as flat shapes that are merely dimmer rather than lit. Real shadow is lit
## by the ambient: a night sky, a daylit street. Shading toward that instead keeps
## the hue alive in the darks, and it is the cheapest single change that makes
## these polygons look lit — no shader, no extra draw calls, no new assets.
##
## A static because exactly one venue is ever on screen; VenueFloor sets it from
## that venue's own shell colour when the theme is built, so the ambient always
## belongs to the building it is shading.
static var shade_ambient: Color = Color("#1E2138")

## Shade a face by `amount`, toward the ambient rather than toward black.
static func shade(col: Color, amount: float) -> Color:
	return col.lerp(shade_ambient, amount)

## Ground-plane rotation, applied inside the projection.
##
## Every painter in the game builds its shape from grid-space points and hands
## them to `to_screen`. Rotating there rotates the piece — the whole piece, walls
## and lids and rope posts included — without any painter knowing it happened.
## The alternative was teaching thirty-odd painters to compute rotated corners
## individually, which is the answer I wrongly gave first.
##
## Rotation is on the GROUND PLANE, about a pivot in grid space, so a turned
## bench stays flat on the floor instead of spinning against the screen the way
## a node rotation would.
##
## Guarded by a bool because this is the hottest function in the renderer —
## thousands of calls a frame — and the untransformed path has to stay free.
static var _rot_on := false
static var _rot_pivot := Vector2.ZERO
static var _rot_cos := 1.0
static var _rot_sin := 0.0
static var _rot_stack: Array = []

## Turn everything drawn until the matching pop by `radians` about `pivot`.
static func push_rotation(pivot: Vector2, radians: float) -> void:
	_rot_stack.push_back([_rot_on, _rot_pivot, _rot_cos, _rot_sin])
	_rot_on = not is_zero_approx(radians)
	_rot_pivot = pivot
	_rot_cos = cos(radians)
	_rot_sin = sin(radians)

static func pop_rotation() -> void:
	if _rot_stack.is_empty():
		_rot_on = false
		return
	var prev: Array = _rot_stack.pop_back()
	_rot_on = bool(prev[0])
	_rot_pivot = prev[1]
	_rot_cos = float(prev[2])
	_rot_sin = float(prev[3])

## Reflection on the ground plane, about a line through a pivot.
##
## A MIRROR IS NOT A ROTATION. No angle turns a left-handed arrangement into a
## right-handed one, which is why an L of benches could never be matched on the
## opposite side of a room by spinning the pieces — the shape needed reflecting,
## and nothing in the renderer could reflect.
##
## `axis` is the line the reflection happens ACROSS, in grid space: "x" mirrors
## gy about the pivot (a north-south flip), "y" mirrors gx (east-west), and "d"
## mirrors about the diagonal by swapping gx and gy, which is the one that reads
## as a left-right mirror on an isometric screen.
static var _mir_on := false
static var _mir_pivot := Vector2.ZERO
static var _mir_axis := "y"
static var _mir_stack: Array = []

static func push_mirror(pivot: Vector2, axis: String) -> void:
	_mir_stack.push_back([_mir_on, _mir_pivot, _mir_axis])
	_mir_on = axis != ""
	_mir_pivot = pivot
	_mir_axis = axis

static func pop_mirror() -> void:
	if _mir_stack.is_empty():
		_mir_on = false
		return
	var prev: Array = _mir_stack.pop_back()
	_mir_on = bool(prev[0])
	_mir_pivot = prev[1]
	_mir_axis = str(prev[2])

static func mirror_point(g: Vector2, pivot: Vector2, axis: String) -> Vector2:
	match axis:
		"x": return Vector2(g.x, 2.0 * pivot.y - g.y)
		"y": return Vector2(2.0 * pivot.x - g.x, g.y)
		"d":
			var d: Vector2 = g - pivot
			return pivot + Vector2(d.y, d.x)
	return g

static func to_screen(g: Vector2) -> Vector2:
	var p := g
	if _mir_on:
		p = mirror_point(p, _mir_pivot, _mir_axis)
	if _rot_on:
		var d: Vector2 = p - _rot_pivot
		p = _rot_pivot + Vector2(d.x * _rot_cos - d.y * _rot_sin,
			d.x * _rot_sin + d.y * _rot_cos)
	return ORIGIN + Vector2((p.x - p.y) * TILE.x * 0.5, (p.x + p.y) * TILE.y * 0.5)

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
		ci.draw_line(pts[i - 1], pts[i], col, w, true)

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

## Three/four-point convex faces use the renderer's batchable primitives.
## Larger or concave shapes retain Godot's polygon triangulation. Color, alpha,
## vertex positions, draw order and the current draw transform are unchanged.
## Diagnostic switch supports same-scene pixel/performance comparison.
static var batch_simple_faces := true
static func fill(ci: CanvasItem, points: PackedVector2Array, color: Color) -> void:
	var simple := points.size() == 3
	if points.size() == 4:
		var sign_value := 0.0
		simple = true
		for i in range(4):
			var cross := (points[(i+1)%4]-points[i]).cross(points[(i+2)%4]-points[(i+1)%4])
			if is_zero_approx(cross):
				simple = false
				break
			if sign_value != 0.0 and cross * sign_value < 0.0:
				simple = false
				break
			sign_value = cross
	if batch_simple_faces and simple:
		ci.draw_primitive(points, PackedColorArray([color]), PackedVector2Array())
	else:
		ci.draw_colored_polygon(points, color)

## Filled floor patch with an optional darker seam around it.
static func floor_patch(ci: CanvasItem, g: Vector2, size: Vector2,
		col: Color, seam: Color = Color(0, 0, 0, 0)) -> void:
	var q := quad(g, size)
	fill(ci, q, col)
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
		col: Color, outline: Color = Color(0, 0, 0, 0.14)) -> void:
	var back := to_screen(g)
	var right := to_screen(g + Vector2(size.x, 0.0))
	var front := to_screen(g + size)
	var left := to_screen(g + Vector2(0.0, size.y))
	var up := Vector2(0.0, -height)
	# Shaded primitives preserve batching and the exact authored silhouette.
	# The contact end is darker; broad highlights match the rendered prop kit.
	ci.draw_primitive(PackedVector2Array([left, front, front + up, left + up]),
		PackedColorArray([shade(col,.37),shade(col,.40),shade(col,.26),shade(col,.23)]),PackedVector2Array())
	ci.draw_primitive(PackedVector2Array([front, right, right + up, front + up]),
		PackedColorArray([shade(col,.22),shade(col,.19),shade(col,.07),shade(col,.11)]),PackedVector2Array())
	ci.draw_primitive(PackedVector2Array([back + up, right + up, front + up, left + up]),
		PackedColorArray([col.lightened(.12),col.lightened(.06),col,col.lightened(.04)]),PackedVector2Array())
	if height >= 4.0 and minf(size.x,size.y) >= .18:
		var edge:=Vector2(0,minf(.85,height*.10))
		ci.draw_primitive(PackedVector2Array([left+up,front+up,front+up+edge,left+up+edge]),
			PackedColorArray([col, col, shade(col,.26), shade(col,.23)]),PackedVector2Array())
		ci.draw_primitive(PackedVector2Array([front+up,right+up,right+up+edge,front+up+edge]),
			PackedColorArray([col.lightened(.08), col.lightened(.12), shade(col,.07), shade(col,.11)]),PackedVector2Array())
	if outline.a > 0.0:
		stroke(ci, PackedVector2Array([
			left + up, back + up, right + up, front + up, left + up, left, front, right]),
			outline, 1.0)
		ci.draw_line(front, front + up, outline, 1.0, true)

## A wall running along one grid edge, extruded upward. `axis` is "x" for a wall
## spanning the x direction (the north/back wall) or "y" for the west wall.
static func wall(ci: CanvasItem, g: Vector2, length: float, axis: String,
		col: Color, height: float = WALL_H) -> void:
	var a := to_screen(g)
	var b := to_screen(g + (Vector2(length, 0.0) if axis == "x" else Vector2(0.0, length)))
	var up := Vector2(0.0, -height)
	# Face, with a gradient so the wall reads as lit from above.
	ci.draw_polygon(PackedVector2Array([a + up, b + up, b, a]),
		PackedColorArray([col.lightened(.06), col.lightened(.06), shade(col,.22), shade(col,.22)]))
	# Cap rail along the top edge.
	ci.draw_line(a + up, b + up, col.lightened(0.28), 2.4)
	ci.draw_line(a, b, shade(col, 0.52), 1.6)

## A GLAZED screen where a wall would go — frame, mullions, and a pane you see
## through on purpose.
##
## Glass walls are authored transparent boundaries. Opaque walls that must
## interleave with moving actors use the segmented Y-sorted path in
## wall_occlusion.gd; glazing is never a substitute for actor/wall depth.
static func glass_wall(ci: CanvasItem, g: Vector2, length: float, axis: String,
		col: Color, height: float = WALL_H) -> void:
	var step := Vector2(length, 0.0) if axis == "x" else Vector2(0.0, length)
	var a := to_screen(g)
	var b := to_screen(g + step)
	var up := Vector2(0.0, -height)
	# The pane. Low alpha and a cool tint so it reads as glazing rather than as a
	# wall someone forgot to finish.
	var pane := Color(col.lightened(0.55), 0.26)
	fill(ci, PackedVector2Array([a + up, b + up, b, a]), pane)
	# Mullions every ~1.1 tiles, plus the two ends, so the run reads as glazed
	# bays rather than one sheet of tint.
	var bays: int = maxi(1, int(round(length / 1.1)))
	var frame: Color = col.darkened(0.10)
	for i in bays + 1:
		var t: float = float(i) / float(bays)
		var foot: Vector2 = a.lerp(b, t)
		ci.draw_line(foot, foot + up, frame, 2.0)
	# Head and sill rails, and a highlight raking across the glass.
	ci.draw_line(a + up, b + up, col.lightened(0.34), 2.6)
	ci.draw_line(a, b, shade(col, 0.52), 1.8)
	ci.draw_line(a + up * 0.72, b + up * 0.34, Color(1, 1, 1, 0.16), 2.0)

## Soft contact shadow on the floor plane, shaped as a squashed iso diamond.
static func shadow(ci: CanvasItem, g: Vector2, size: Vector2, alpha: float = 0.16) -> void:
	# Feather into the same authored footprint instead of a hard ink diamond.
	var outer:=quad(g,size)
	var inset:=minf(.10,minf(size.x,size.y)*.18)
	var inner:=quad(g+Vector2.ONE*inset,size-Vector2.ONE*inset*2)
	var dark:=Color(.10,.12,.16,alpha)
	var clear:=Color(dark,0)
	fill(ci,inner,dark)
	for i in 4:
		var j: int=(i+1)%4
		ci.draw_primitive(PackedVector2Array([outer[i],outer[j],inner[j],inner[i]]),
			PackedColorArray([clear,clear,dark,dark]),PackedVector2Array())

## Upright flat panel standing on a wall — paintings, poster boards, signage.
## Drawn in the plane of the given axis so it sits flush against the wall face.
static func panel(ci: CanvasItem, g: Vector2, length: float, axis: String,
		bottom: float, top: float, col: Color, outline: Color = Color(0, 0, 0, 0.35)) -> void:
	var a := to_screen(g)
	var b := to_screen(g + (Vector2(length, 0.0) if axis == "x" else Vector2(0.0, length)))
	var lo := Vector2(0.0, -bottom)
	var hi := Vector2(0.0, -top)
	var poly := PackedVector2Array([a + hi, b + hi, b + lo, a + lo])
	fill(ci, poly, col)
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
	fill(ci, quad(g, size), col)
	if border.a > 0.0:
		var ring := quad(g + Vector2(0.16, 0.16), size - Vector2(0.32, 0.32))
		ring.append(ring[0])
		stroke(ci, ring, border, 2.0)

## A thin round slab held at `height` — a tabletop, a drum lid, a column cap.
##
## `cyl` extrudes from the floor, so asking it for a tabletop gives a barrel the
## full height of the table: a café table drawn that way reads as a pale drum,
## which is what the lounge furniture looked like. This draws only the top face
## plus a shallow edge band, so the top floats on whatever pedestal is drawn
## under it and the silhouette is a table.
static func disc(ci: CanvasItem, g: Vector2, r: float, height: float,
		col: Color, edge: float = 3.0) -> void:
	var c := to_screen(g)
	var rx: float = r * TILE.x
	var ry: float = r * TILE.y
	var up := Vector2(0.0, -height)
	# Front edge band: the near half of the rim, dropped by `edge`.
	var band := PackedVector2Array()
	for i in 13:
		var an: float = PI * float(i) / 12.0
		band.append(c + Vector2(cos(an) * rx, sin(an) * ry) + up)
	for i in range(12, -1, -1):
		var an: float = PI * float(i) / 12.0
		band.append(c + Vector2(cos(an) * rx, sin(an) * ry) + up + Vector2(0.0, edge))
	fill(ci, band, shade(col, 0.34))
	var top := PackedVector2Array()
	for i in 24:
		var an: float = TAU * float(i) / 24.0
		top.append(c + Vector2(cos(an) * rx, sin(an) * ry) + up)
	fill(ci, top, col)

## Upright cylinder — bins, urns, columns, drums. `r` is a radius in tiles, so
## the footprint stays a proper iso ellipse instead of a screen-space circle.
static func cyl(ci: CanvasItem, g: Vector2, r: float, height: float, col: Color) -> void:
	var c := to_screen(g)
	var rx: float = r * TILE.x
	var ry: float = r * TILE.y
	var up := Vector2(0.0, -height)
	# Smooth normals across the side make bins and columns read as round solids.
	# These strips are ordinary batchable quads, with no new nodes or textures.
	for i in 16:
		var a:=PI*float(i)/16.0
		var b:=PI*float(i+1)/16.0
		var pa:=c+Vector2(cos(a)*rx,sin(a)*ry)
		var pb:=c+Vector2(cos(b)*rx,sin(b)*ry)
		var ca:=shade(col,.12+.24*pow(sin(a*.75),2.0))
		var cb:=shade(col,.12+.24*pow(sin(b*.75),2.0))
		ci.draw_primitive(PackedVector2Array([pa,pb,pb+up,pa+up]),
			PackedColorArray([ca.darkened(.05),cb.darkened(.05),cb.lightened(.07),ca.lightened(.07)]),PackedVector2Array())
	var top := PackedVector2Array()
	for i in 32:
		var an: float = TAU * float(i) / 32.0
		top.append(c + Vector2(cos(an) * rx, sin(an) * ry) + up)
	fill(ci, top, col.lightened(.06))

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
		fill(ci, PackedVector2Array([
			p + Vector2(-4.6, 0.0), p + Vector2(4.6, 0.0), p + Vector2(0.0, 11.5)]),
			cols[i % cols.size()])
