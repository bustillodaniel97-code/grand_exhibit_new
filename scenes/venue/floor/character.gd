extends Node2D
## Character — the procedural chibi cast. Original design, no texture assets.
##
## Two render paths, one body of drawing code:
##   · SPRITE (normal play) — CharacterBaker rasterises this figure once at 4x
##     and box-filters it down; _draw then blits a single textured quad. Every
##     edge is supersampled, and a figure costs 1 draw call instead of ~18.
##   · PAINTER / fallback — draws the primitives directly. Used inside the
##     baker's SubViewport, and as the fallback under --headless where there is
##     no rendering context to bake with (the test suites run this path).
##
## Because the sprite path pays for detail exactly once, the shading here is far
## heavier than a per-frame budget would allow: layered skin tones, a rim light
## along the key side, contact occlusion under the chin and at the waist, banded
## hair with a highlight, and stroked silhouettes on every major mass.
##
## Looks are quantised to LOOK_COUNT palettes so the bake cache stays bounded.
##
## Public API unchanged: randomize_look / set_uniform / walking / facing /
## with_cart / holding_sign / carry_stack.

const UI := preload("res://scripts/ui/ui_kit.gd")
const Baker := preload("res://scenes/venue/floor/character_baker.gd")

const WALK_FPS := 10.0
const OUTLINE := Color("#3A2A1F")
const OUTLINE_W := 1.8
## Distinct visitor palettes. Bounds the bake cache; the crowd still reads as
## varied because hair style and walk phase vary independently of palette.
const LOOK_COUNT := 14

const SKIN_TONES: Array[Color] = [
	Color("#F8D8B0"), Color("#EFC094"), Color("#D9A170"), Color("#B87B4C"),
	Color("#8E5733"), Color("#66412A"),
]
const HAIR_COLORS: Array[Color] = [
	Color("#2B2320"), Color("#4E3524"), Color("#7C5228"), Color("#C79A45"),
	Color("#B5AFA8"), Color("#8A3A2C"), Color("#42304E"),
]
const SHIRT_COLORS: Array[Color] = [
	Color("#4E7FB5"), Color("#C85A5A"), Color("#5FA86E"), Color("#D19A3E"),
	Color("#7A6BB5"), Color("#4FA3A5"), Color("#C77BA6"), Color("#5C6B8A"),
]
const PANTS_COLORS: Array[Color] = [
	Color("#3A3F4A"), Color("#5A4A3A"), Color("#44546A"), Color("#4A3F52"),
]

var is_staff: bool = false
var uniform_color: Color = Color("#C4703F")
var with_cart: bool = false        # porter: pushes a docent cart w/ artifact crate
var holding_sign: bool = false     # promoter: holds an exhibit sign
var walking: bool = false
var facing: int = 1                # 1 = right, -1 = left
var carry_stack: int = 0           # visual crate count carried (porter)

## Set by CharacterBaker: freeze on one walk pose and always draw primitives.
var bake_pose: int = -1

var _skin: Color = SKIN_TONES[0]
var _hair: Color = HAIR_COLORS[0]
var _shirt: Color = SHIRT_COLORS[0]
var _pants: Color = PANTS_COLORS[0]
var _hair_style: int = 0
var _build: float = 1.0
var _look_key: String = ""
var _is_painter: bool = false
var _bob_t: float = 0.0
var _frame: int = 0
var _frames: Array = []

func _ready() -> void:
	if not _is_painter:
		_try_bake()
	queue_redraw()

## Marks this instance as the baker's off-screen painter.
func set_painter_mode(on: bool) -> void:
	_is_painter = on

# ------------------------------------------------------------------ look

## Deterministic look from a seed, quantised to one of LOOK_COUNT palettes.
func randomize_look(rng_seed: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = rng_seed
	var slot: int = rng.randi() % LOOK_COUNT
	var pick := RandomNumberGenerator.new()
	pick.seed = slot * 7919
	_skin = SKIN_TONES[pick.randi() % SKIN_TONES.size()]
	_hair = HAIR_COLORS[pick.randi() % HAIR_COLORS.size()]
	_shirt = SHIRT_COLORS[pick.randi() % SHIRT_COLORS.size()]
	_pants = PANTS_COLORS[pick.randi() % PANTS_COLORS.size()]
	_hair_style = pick.randi() % 4
	_build = 1.0
	_look_key = "v%d" % slot
	_try_bake()
	queue_redraw()

func set_uniform(dept_color: Color) -> void:
	is_staff = true
	uniform_color = dept_color
	_shirt = dept_color
	_pants = dept_color.darkened(0.45)
	_hair = HAIR_COLORS[0]
	_skin = SKIN_TONES[1]
	_hair_style = 0
	_look_key = "s%s" % dept_color.to_html(false)
	_try_bake()
	queue_redraw()

## Serialise the current look so the baker can rebuild it on its painter.
func current_look() -> Dictionary:
	return {
		"skin": _skin, "hair": _hair, "shirt": _shirt, "pants": _pants,
		"hair_style": _hair_style, "build": _build,
		"is_staff": is_staff, "uniform": uniform_color,
	}

func apply_look(look: Dictionary) -> void:
	_skin = look.get("skin", _skin)
	_hair = look.get("hair", _hair)
	_shirt = look.get("shirt", _shirt)
	_pants = look.get("pants", _pants)
	_hair_style = int(look.get("hair_style", 0))
	_build = float(look.get("build", 1.0))
	is_staff = bool(look.get("is_staff", false))
	uniform_color = look.get("uniform", uniform_color)
	queue_redraw()

func _try_bake() -> void:
	if _is_painter or _look_key == "":
		return
	_frames = Baker.frames_for(_look_key)
	if _frames.is_empty():
		Baker.request(_look_key, current_look(), self)

# ------------------------------------------------------------------ tick

func _process(delta: float) -> void:
	scale.x = absf(scale.x) * float(facing)
	if _frames.is_empty() and not _is_painter and _look_key != "":
		# The bake may have completed since the last tick.
		_frames = Baker.frames_for(_look_key)
		if not _frames.is_empty():
			queue_redraw()
	if not walking:
		if _frame != 0:
			_frame = 0
			_bob_t = 0.0
			queue_redraw()
		return
	_bob_t += delta
	var f: int = int(_bob_t * WALK_FPS) % Baker.FRAMES
	if f != _frame:
		_frame = f
		queue_redraw()

# ------------------------------------------------------------------ draw

func _draw() -> void:
	# Sprite path: one quad, supersampled offline.
	if not _is_painter and not _frames.is_empty():
		var tex: Texture2D = _frames[clampi(_frame, 0, _frames.size() - 1)]
		# Stored at 2x the design footprint, so it is blitted at half size.
		draw_texture_rect(tex,
			Rect2(-Baker.ANCHOR * 0.5, Vector2(Baker.SPRITE) * 0.5), false)
		# Props stay live: only a handful of characters carry one, so they are
		# not worth multiplying the bake cache by.
		if holding_sign:
			_draw_sign(0.0)
		if with_cart:
			_draw_cart(0.0)
		return
	_draw_figure()

## Full primitive draw. Runs inside the baker, and as the headless fallback.
func _draw_figure() -> void:
	var phase: float = 0.0
	if bake_pose >= 0:
		phase = TAU * float(bake_pose) / float(Baker.FRAMES)
	elif walking:
		phase = float(int(_bob_t * WALK_FPS)) / WALK_FPS * TAU * 2.2
	var moving: bool = bake_pose > 0 or (bake_pose < 0 and walking)
	var bob: float = -absf(sin(phase)) * 2.6 if moving else 0.0
	var swing: float = sin(phase) * 3.6 if moving else 0.0
	var squash: float = 1.0 + (absf(sin(phase)) - 0.5) * 0.07 if moving else 1.0
	var w: float = _build / squash
	var h: float = squash

	_draw_contact_shadow(squash)
	_draw_legs(bob, swing, w)
	_draw_arm(-1.0, bob, swing, w, h)      # far arm, behind the torso
	_draw_body(bob, w, h)
	_draw_head(bob, swing, w, h)
	_draw_arm(1.0, bob, swing, w, h)       # near arm, in front
	if holding_sign:
		_draw_sign(bob)
	if with_cart:
		_draw_cart(bob)

## Grounding shadow — three stacked ellipses fake a penumbra without a shader.
func _draw_contact_shadow(squash: float) -> void:
	var spread: float = 1.0 + (1.0 - squash) * 2.0
	paint_ellipse(Rect2(-11.0 * spread, -4.0, 22.0 * spread, 8.0), Color(0.20, 0.13, 0.06, 0.13))
	paint_ellipse(Rect2(-8.0 * spread, -3.0, 16.0 * spread, 6.0), Color(0.20, 0.13, 0.06, 0.16))
	paint_ellipse(Rect2(-5.0 * spread, -2.2, 10.0 * spread, 4.4), Color(0.20, 0.13, 0.06, 0.18))

func _draw_legs(bob: float, swing: float, w: float) -> void:
	var shoe := Color("#3B2E26")
	for side in [-1.0, 1.0]:
		var off: float = swing * 0.44 * side
		var x: float = (2.9 * side - 2.6) * w + off
		_shape(_capsule(Rect2(x, -10.0 + bob, 5.4 * w, 9.5)), _pants)
		# Inner shadow down the leg's far side.
		draw_colored_polygon(_capsule(Rect2(x + 3.4 * w, -10.0 + bob, 2.0 * w, 9.5)),
			_pants.darkened(0.22))
		_shape(_capsule(Rect2(x - 0.8, -3.6 + bob, 6.6 * w, 4.0)), shoe)
		draw_line(Vector2(x - 0.4, -2.6 + bob), Vector2(x + 5.4 * w, -2.6 + bob),
			shoe.lightened(0.28), 1.0)

func _draw_body(bob: float, w: float, h: float) -> void:
	var top: float = -25.0 * h + bob
	var bh: float = 17.0 * h
	var torso := PackedVector2Array([
		Vector2(-8.6 * w, top + bh), Vector2(-9.7 * w, top + bh * 0.34),
		Vector2(-8.0 * w, top), Vector2(8.0 * w, top),
		Vector2(9.7 * w, top + bh * 0.34), Vector2(8.6 * w, top + bh),
	])
	_shape(_round_poly(torso, 3.2), _shirt)
	# Waist occlusion.
	draw_colored_polygon(PackedVector2Array([
		Vector2(-8.6 * w, top + bh), Vector2(8.6 * w, top + bh),
		Vector2(8.3 * w, top + bh * 0.60), Vector2(-8.3 * w, top + bh * 0.60),
	]), _shirt.darkened(0.17))
	# Shading down the right (away from the key light), rim light on the left.
	draw_colored_polygon(PackedVector2Array([
		Vector2(5.6 * w, top + 1.0), Vector2(8.4 * w, top + 2.0),
		Vector2(8.6 * w, top + bh), Vector2(5.6 * w, top + bh),
	]), _shirt.darkened(0.12))
	draw_line(Vector2(-7.2 * w, top + 3.0), Vector2(-7.9 * w, top + bh * 0.75),
		_shirt.lightened(0.30), 1.8)
	draw_line(Vector2(-6.0 * w, top + 1.5), Vector2(5.0 * w, top + 1.5),
		_shirt.lightened(0.24), 1.8)
	# Collar.
	draw_colored_polygon(PackedVector2Array([
		Vector2(-3.4 * w, top - 0.4), Vector2(3.4 * w, top - 0.4),
		Vector2(2.2 * w, top + 3.2), Vector2(-2.2 * w, top + 3.2),
	]), _shirt.darkened(0.30))
	if is_staff:
		# Uniform sash + a brass button, so staff read instantly in a crowd.
		draw_line(Vector2(-6.6 * w, top + bh * 0.26), Vector2(6.6 * w, top + bh * 0.44),
			uniform_color.lightened(0.46), 2.4)
		draw_circle(Vector2(0.0, top + bh * 0.62), 1.5, UI.BRASS)

func _draw_arm(side: float, bob: float, swing: float, w: float, h: float) -> void:
	var top: float = -25.0 * h + bob
	var x: float = 8.3 * w * side
	var lift: float = swing * 0.52 * side
	var sleeve := _shirt if side > 0.0 else _shirt.darkened(0.14)
	_shape(_capsule(Rect2(x - 2.5, top + 3.0 + lift, 5.0, 11.0)), sleeve)
	var hand := Vector2(x, top + 15.0 + lift)
	draw_circle(hand, 2.8, OUTLINE)
	draw_circle(hand, 2.2, _skin)
	draw_circle(hand + Vector2(-0.6, -0.7), 1.0, _skin.lightened(0.22))

func _draw_head(bob: float, swing: float, w: float, h: float) -> void:
	var hc := Vector2(swing * 0.16, -33.5 * h + bob * 0.8)
	var r: float = 10.8
	draw_colored_polygon(_capsule(Rect2(hc.x - 2.8, hc.y + r - 3.6, 5.6, 6.4)),
		_skin.darkened(0.26))
	_shape(_ellipse_poly(hc, Vector2(r, r * 0.97), 26), _skin)
	# Occlusion under the chin, key light upper-left, narrow rim along the lit
	# edge — three tones is what gives a flat disc form at this size.
	draw_colored_polygon(_ellipse_poly(hc + Vector2(1.4, 3.8), Vector2(r * 0.82, r * 0.48), 18),
		_skin.darkened(0.14))
	draw_colored_polygon(_ellipse_poly(hc + Vector2(-3.2, -3.4), Vector2(r * 0.46, r * 0.42), 16),
		_skin.lightened(0.16))
	draw_arc(hc, r - 0.9, PI * 1.08, PI * 1.52, 10, _skin.lightened(0.32), 1.6)
	draw_circle(hc + Vector2(-r + 1.2, 1.0), 2.2, _skin.darkened(0.10))
	_draw_hair(hc, r)
	_draw_face(hc)
	if is_staff:
		_draw_cap(hc, r)

func _draw_hair(hc: Vector2, r: float) -> void:
	var dark := _hair.darkened(0.26)
	match _hair_style:
		0:  # short crop
			_shape(_arc_poly(hc, r + 0.8, PI * 0.97, TAU * 1.03, 5.8), _hair)
			draw_colored_polygon(_arc_poly(hc, r + 0.8, PI * 1.30, TAU * 1.03, 5.8), dark)
		1:  # side sweep with a fringe
			_shape(_arc_poly(hc, r + 0.8, PI * 0.84, TAU * 1.05, 6.6), _hair)
			_shape(_ellipse_poly(hc + Vector2(-6.4, -3.2), Vector2(4.8, 4.2), 16), _hair)
			draw_colored_polygon(_ellipse_poly(hc + Vector2(-7.2, -2.0), Vector2(2.6, 2.6), 12), dark)
		2:  # bun
			_shape(_arc_poly(hc, r + 0.8, PI * 0.97, TAU * 1.03, 5.4), _hair)
			_shape(_ellipse_poly(hc + Vector2(-1.0, -12.4), Vector2(4.8, 4.4), 16), _hair)
			draw_colored_polygon(_ellipse_poly(hc + Vector2(0.4, -11.4), Vector2(2.2, 2.0), 12), dark)
		_:  # bob cut past the ears
			_shape(_arc_poly(hc, r + 1.0, PI * 0.78, TAU * 1.12, 6.2), _hair)
			_shape(_ellipse_poly(hc + Vector2(-8.4, 1.6), Vector2(3.4, 5.6), 16), _hair)
			_shape(_ellipse_poly(hc + Vector2(8.4, 1.6), Vector2(3.4, 5.6), 16), _hair)
	draw_line(hc + Vector2(-5.4, -8.6), hc + Vector2(1.6, -10.0), _hair.lightened(0.38), 2.0)
	draw_line(hc + Vector2(-3.0, -10.4), hc + Vector2(2.6, -10.8), _hair.lightened(0.24), 1.2)

## Faces +x; mirrored by scale.x when facing left.
func _draw_face(hc: Vector2) -> void:
	for ex in [3.0, 7.4]:
		var e := hc + Vector2(ex, -0.8)
		# Brow shadow, iris, catchlight — a face at 30px still needs three parts.
		draw_colored_polygon(_ellipse_poly(e + Vector2(0, -2.4), Vector2(1.8, 0.7), 10),
			_skin.darkened(0.24))
		draw_colored_polygon(_ellipse_poly(e, Vector2(1.6, 2.0), 12), OUTLINE)
		draw_circle(e + Vector2(-0.55, -0.75), 0.7, Color(1, 1, 1, 0.9))
	draw_arc(hc + Vector2(5.3, 2.5), 2.7, 0.16 * PI, 0.84 * PI, 10, OUTLINE, 1.4)
	draw_circle(hc + Vector2(1.9, 2.2), 2.1, Color(0.92, 0.47, 0.42, 0.26))
	draw_circle(hc + Vector2(8.8, 2.0), 1.7, Color(0.92, 0.47, 0.42, 0.20))

func _draw_cap(hc: Vector2, r: float) -> void:
	var crown := uniform_color.darkened(0.08)
	_shape(_arc_poly(hc + Vector2(0, -1.6), r + 1.0, PI * 1.01, TAU * 0.99, 6.6), crown)
	draw_colored_polygon(_arc_poly(hc + Vector2(0, -1.6), r + 1.0, PI * 1.34, TAU * 0.99, 6.6),
		uniform_color.darkened(0.30))
	_shape(PackedVector2Array([
		Vector2(hc.x + 0.8, hc.y - 6.4), Vector2(hc.x + 12.6, hc.y - 5.6),
		Vector2(hc.x + 12.6, hc.y - 3.0), Vector2(hc.x + 0.8, hc.y - 2.8),
	]), uniform_color.darkened(0.34))
	draw_circle(hc + Vector2(-1.0, -9.4), 1.6, UI.BRASS)

## Museum exhibit board on a stick (promotions marketer).
func _draw_sign(bob: float) -> void:
	draw_line(Vector2(11, -44 + bob), Vector2(11, -20 + bob), UI.WALL_BROWN, 3.0)
	var board := Rect2(1, -64 + bob, 30, 20)
	_shape(_round_rect(board, 3.0), UI.PANEL)
	draw_circle(board.get_center() + Vector2(-7, -1), 3.6, UI.ROOM_PROMO)
	draw_line(board.get_center() + Vector2(-1, 3), board.get_center() + Vector2(11, 3),
		UI.ROOM_PROMO.darkened(0.1), 2.0)
	draw_line(board.get_center() + Vector2(-1, -3), board.get_center() + Vector2(8, -3),
		UI.ROOM_PROMO.darkened(0.1), 2.0)

## Wooden trolley + artifact crates (archive porter). Ours, not cash bags.
func _draw_cart(bob: float) -> void:
	var cx := 14.0
	_shape(_round_rect(Rect2(cx, -15 + bob, 21, 4.4), 1.6), UI.WALL_BROWN)
	draw_line(Vector2(cx + 1, -15 + bob), Vector2(cx - 6, -23 + bob), UI.WALL_BROWN, 2.4)
	for wheel_x in [cx + 4.0, cx + 17.0]:
		draw_circle(Vector2(wheel_x, -8.4 + bob), 3.8, OUTLINE)
		draw_circle(Vector2(wheel_x, -8.4 + bob), 1.5, UI.WALL_BROWN.lightened(0.3))
	for i in maxi(carry_stack, 1):
		var crate := Rect2(cx + 2.5, -26.4 + bob - float(i - 1) * 10.6, 16, 10.4)
		_shape(_round_rect(crate, 1.6), Color("#D6A868"))
		draw_line(crate.position + Vector2(1.4, 5.2), crate.position + Vector2(14.6, 5.2),
			Color("#A9793F"), 1.4)
		draw_line(crate.position + Vector2(0.8, 1.4), crate.position + Vector2(15.2, 1.4),
			Color("#EDC68F"), 1.2)

# ------------------------------------------------------------------ helpers

## Fill a polygon, then stroke its boundary. Strokes are not flagged antialiased:
## under the sprite path the supersampled downsample smooths them far better than
## the flag would, and AA geometry would only bloat the bake.
func _shape(poly: PackedVector2Array, fill: Color, outline: Color = OUTLINE) -> void:
	draw_colored_polygon(poly, fill)
	var ring := poly.duplicate()
	ring.append(poly[0])
	draw_polyline(ring, outline, OUTLINE_W)

func _ellipse_poly(center: Vector2, radii: Vector2, segments: int = 20) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in segments:
		var a := TAU * float(i) / float(segments)
		pts.append(center + Vector2(cos(a) * radii.x, sin(a) * radii.y))
	return pts

func _capsule(rect: Rect2) -> PackedVector2Array:
	return _round_rect(rect, minf(rect.size.x, rect.size.y) * 0.5)

func _round_rect(rect: Rect2, radius: float, per_corner: int = 5) -> PackedVector2Array:
	var r: float = minf(radius, minf(rect.size.x, rect.size.y) * 0.5)
	var pts := PackedVector2Array()
	var corners := [
		[Vector2(rect.position.x + rect.size.x - r, rect.position.y + rect.size.y - r), 0.0],
		[Vector2(rect.position.x + r, rect.position.y + rect.size.y - r), PI * 0.5],
		[Vector2(rect.position.x + r, rect.position.y + r), PI],
		[Vector2(rect.position.x + rect.size.x - r, rect.position.y + r), PI * 1.5],
	]
	for c in corners:
		var centre: Vector2 = c[0]
		var base: float = c[1]
		for i in per_corner + 1:
			var a: float = base + PI * 0.5 * float(i) / float(per_corner)
			pts.append(centre + Vector2(cos(a) * r, sin(a) * r))
	return pts

## Rounds a polygon by nudging each vertex toward its neighbours. The nudge is
## capped at 45% of the shorter adjacent edge: past half an edge the corner
## inverts, the polygon self-intersects, and Godot's triangulator rejects it.
func _round_poly(poly: PackedVector2Array, amount: float) -> PackedVector2Array:
	var n := poly.size()
	if n < 3:
		return poly
	var out := PackedVector2Array()
	for i in n:
		var prev: Vector2 = poly[(i - 1 + n) % n]
		var cur: Vector2 = poly[i]
		var next: Vector2 = poly[(i + 1) % n]
		var d_prev: float = prev.distance_to(cur)
		var d_next: float = next.distance_to(cur)
		if d_prev < 0.001 or d_next < 0.001:
			out.append(cur)
			continue
		out.append(cur + (prev - cur) / d_prev * minf(amount, d_prev * 0.45))
		out.append(cur + (next - cur) / d_next * minf(amount, d_next * 0.45))
	return out

## Filled band between two radii over an angular sweep — hair caps, cap crowns.
func _arc_poly(center: Vector2, radius: float, from_a: float, to_a: float,
		thickness: float, segments: int = 18) -> PackedVector2Array:
	var outer := PackedVector2Array()
	var inner := PackedVector2Array()
	for i in segments + 1:
		var a: float = lerpf(from_a, to_a, float(i) / float(segments))
		outer.append(center + Vector2(cos(a), sin(a)) * radius)
		inner.append(center + Vector2(cos(a), sin(a)) * (radius - thickness))
	inner.reverse()
	var pts := outer
	pts.append_array(inner)
	return pts

## Cheap filled ellipse. Named paint_ellipse, not draw_ellipse: Godot 4.5 added
## CanvasItem.draw_ellipse and the old name silently shadowed it.
func paint_ellipse(rect: Rect2, color: Color) -> void:
	draw_colored_polygon(_ellipse_poly(rect.get_center(),
		Vector2(rect.size.x * 0.5, rect.size.y * 0.5), 18), color)
