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
## Looks are quantised to LOOK_COUNT slots so the bake cache stays bounded. One
## slot is a whole appearance — palette, hair style and build — because the bake
## is keyed on the slot; see look_for_slot for why the axes are strided rather
## than drawn from one RNG stream.
##
## Public API: set_look_slot / randomize_look / set_uniform / walking / facing /
## with_cart / holding_sign / carry_stack.

const UI := preload("res://scripts/ui/ui_kit.gd")
const Baker := preload("res://scenes/venue/floor/character_baker.gd")

const WALK_FPS := 10.0
const OUTLINE := Color("#3A2A1F")
const OUTLINE_W := 1.8
## Eyes are inked a shade lighter than the silhouette stroke. At the size the
## head is minified to on a phone, filling them with OUTLINE let them merge with
## the head stroke and with the staff cap into one dark mass.
const EYE_INK := Color("#4A3728")

## Figure metrics the bake budget and the suites both reason about.
const HEAD_R := 10.8
const HEAD_Y := -33.5
const BOB_AMP := 2.6
const SQUASH_AMP := 0.07

const HAIR_STYLES := 8
## Build multiplies torso/limb width and, at 45% strength, head radius. It is
## serialised through the bake, so it costs cache slots rather than draw time.
const BUILDS: Array[float] = [0.91, 1.0, 1.09]
## Distinct visitor looks. Bounds the bake cache. Every slot is a distinct
## (hair style, build) pair, and the palette axes are strided so no two slots
## share a full palette. Sized above the floor's peak population so a busy floor
## no longer shows the same person three times.
const LOOK_COUNT := HAIR_STYLES * 3   # 24
## Per-department staff variants. Staff read by uniform hue, so the variants only
## need to break up skin, hair and stature — three is enough for five tellers.
const STAFF_LOOK_COUNT := 3
## Styles that still read under a peaked cap: nothing that piles mass on the crown.
const STAFF_STYLES: Array[int] = [0, 6, 7]

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

## Hair is silhouette-first. On a phone the head is about twenty screen pixels,
## so the only thing a player resolves is the OUTLINE; four styles that all hug
## the skull at r+0.8 are one haircut in four colours no matter how the strands
## are shaded. Seven of the eight styles below push the outline at least 3px past
## the skull cap.
##
## HAIR_BACK — masses behind the skull, drawn BEFORE it so the head occludes
## them. That is what lets a lock or a tail read at full strength without its
## 1.8px stroke ever crossing skin. Entries are [dx, dy, rx, ry] in design px
## from the head centre.
const HAIR_BACK: Array = [
	[],                                                             # 0 crop
	[],                                                             # 1 side sweep
	[[-1.0, -11.8, 4.8, 4.2]],                                      # 2 bun
	[[-10.4, 2.8, 4.2, 7.2], [10.4, 2.8, 4.2, 7.2]],                # 3 bob
	[[-10.6, -6.0, 4.6, 4.6], [0.0, -11.4, 5.2, 4.6],
		[10.6, -6.0, 4.6, 4.6]],                                    # 4 curls
	[[-0.4, -8.8, 4.8, 4.2], [0.4, -13.0, 3.0, 3.0]],               # 5 tall stack
	[[-12.0, 1.8, 4.2, 8.2], [-9.0, -5.8, 2.8, 2.8]],               # 6 ponytail
	[[-11.8, -5.4, 4.4, 4.4], [11.0, -5.6, 4.0, 4.0]],              # 7 twin tails
]

## HAIR_FRONT — appliqués on the face side of the skull. Filled, never stroked.
const HAIR_FRONT: Array = [
	[], [[-5.6, -8.2, 7.0, 5.4]], [], [], [], [], [], [],
]

## Crown band per style: [outer radius above HEAD_R, band thickness, sweep start
## in half-turns, sweep end in turns]. Style 4's band is thick and wide because
## the halo IS its silhouette.
const HAIR_CAP: Array = [
	[0.8, 5.8, 0.97, 1.03],
	[1.0, 6.6, 0.84, 1.05],
	[0.8, 5.4, 0.97, 1.03],
	[1.0, 6.2, 0.82, 1.08],
	[4.2, 9.0, 0.90, 1.10],
	[0.9, 6.0, 0.92, 1.06],
	[1.0, 6.4, 0.88, 1.08],
	[0.9, 6.0, 0.94, 1.06],
]

## Face layout, in design px from the head centre. The features used to pile into
## x in [-0.2, 10.5] on a head of radius 10.8 — 97% of the ink in the right half,
## touching the silhouette — which is why the head read as a ball with a face
## sliding off it rather than as a face. FACE_CX keeps the 3/4 offset small, and
## EYE_DX is held wide enough that the gap between the eyes survives being
## minified onto a phone instead of fusing into one dark blob.
const FACE_CX := 1.5
const EYE_DX := 3.0
const EYE_R := Vector2(1.35, 1.65)
const BROW_R := Vector2(1.7, 0.65)
const MOUTH_DX := 0.6
const MOUTH_R := 2.5
const BLUSH_FAR := Vector3(-4.4, 2.2, 1.9)    # dx from face centre, dy, radius
const BLUSH_NEAR := Vector3(4.8, 2.1, 1.7)
## Staff cap peak, design px from the head centre: x span, then y span. The peak
## used to abut the eye tops exactly, and since both were near-black they fused
## into one bar that read as wraparound sunglasses on every staff member.
const CAP_PEAK_X := Vector2(-2.6, 9.6)
const CAP_PEAK_Y := Vector2(-8.2, -5.4)

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
var _look_slot: int = -1
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

## The look table: slot -> a full appearance.
##
## Every axis is driven by a stride coprime with its palette size, so each entry
## of each palette is used a near-equal number of times, and no axis is a
## function of any other. The previous table ran all six axes off one
## `seed = slot * 7919` stream, which put 43% of the crowd on one hair style,
## 36% on one hair colour, and never selected two of the palette entries at all.
static func look_for_slot(slot: int) -> Dictionary:
	var s: int = posmod(slot, LOOK_COUNT)
	var tier: int = s / HAIR_STYLES        # which build band this slot sits in
	return {
		"skin": SKIN_TONES[(s * 5) % SKIN_TONES.size()],
		"hair": HAIR_COLORS[(s * 3) % HAIR_COLORS.size()],
		"shirt": SHIRT_COLORS[(s + 3 * tier) % SHIRT_COLORS.size()],
		"pants": PANTS_COLORS[(s + tier) % PANTS_COLORS.size()],
		"hair_style": s % HAIR_STYLES,
		"build": BUILDS[tier % BUILDS.size()],
		"is_staff": false,
		"uniform": Color("#C4703F"),
	}

## Adopt a specific look slot. The floor deals slots rather than rolling them:
## with 24 slots and twenty people on screen, independent random picks put three
## visitors in the same face by the birthday paradox alone.
func set_look_slot(slot: int) -> void:
	_look_slot = posmod(slot, LOOK_COUNT)
	apply_look(look_for_slot(_look_slot))
	_look_key = "v%d" % _look_slot
	_try_bake()
	queue_redraw()

## Which look slot this figure wears, or -1 for staff and unassigned figures.
func look_slot() -> int:
	return _look_slot

## Deterministic look from a seed, quantised to one of LOOK_COUNT slots.
func randomize_look(rng_seed: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = rng_seed
	set_look_slot(rng.randi() % LOOK_COUNT)

## Staff read by uniform hue first, so the variant only moves skin, hair colour,
## hair style and stature. Variants are capped at STAFF_LOOK_COUNT so a room full
## of staff costs a bounded number of bake slots; without it the five tellers
## behind the counters were one person copy-pasted five times.
func set_uniform(dept_color: Color, variant: int = 0) -> void:
	var v: int = posmod(variant, STAFF_LOOK_COUNT)
	is_staff = true
	uniform_color = dept_color
	_shirt = dept_color
	_pants = dept_color.darkened(0.45)
	_skin = SKIN_TONES[(v * 2 + 1) % SKIN_TONES.size()]
	_hair = HAIR_COLORS[(v * 3) % HAIR_COLORS.size()]
	_hair_style = STAFF_STYLES[v % STAFF_STYLES.size()]
	_build = BUILDS[(v + 1) % BUILDS.size()]
	_look_slot = -1
	_look_key = "s%s_%d" % [dept_color.to_html(false), v]
	_try_bake()
	queue_redraw()

## Bake-cache key for this figure's appearance. Two characters sharing a key are
## the same person on screen.
func look_key() -> String:
	return _look_key

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
	var bob: float = -absf(sin(phase)) * BOB_AMP if moving else 0.0
	var swing: float = sin(phase) * 3.6 if moving else 0.0
	var squash: float = 1.0 + (absf(sin(phase)) - 0.5) * SQUASH_AMP if moving else 1.0
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
	# The torso reaches 9.7*w at the shoulder, so an arm at 8.3*w was swallowed
	# whole on the far side and every figure read one-armed with a floating hand.
	var x: float = (8.3 * w + 1.2) * side
	var lift: float = swing * 0.52 * side
	var sleeve := _shirt if side > 0.0 else _shirt.darkened(0.14)
	_shape(_capsule(Rect2(x - 2.5, top + 3.0 + lift, 5.0, 11.0)), sleeve)
	var hand := Vector2(x, top + 15.0 + lift)
	draw_circle(hand, 2.8, OUTLINE)
	draw_circle(hand, 2.2, _skin)
	draw_circle(hand + Vector2(-0.6, -0.7), 1.0, _skin.lightened(0.22))

func _draw_head(bob: float, swing: float, w: float, h: float) -> void:
	var hc := Vector2(swing * 0.16, HEAD_Y * h + bob * 0.8)
	# Build carries into the head at 45% strength. Full strength made the small
	# builds read as children, and none at all left every figure wearing the same
	# head — which is most of why the crowd looked stamped from one die.
	var r: float = HEAD_R * (1.0 + (_build - 1.0) * 0.45)
	_draw_hair_back(hc, r)
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
	_draw_hair_front(hc, r)
	_draw_face(hc)
	if is_staff:
		_draw_cap(hc, r)

## Masses behind the skull. Drawn before the head so the head occludes their
## inner half: the outline changes, but no stroke lands on the face.
func _draw_hair_back(hc: Vector2, r: float) -> void:
	var k: float = r / HEAD_R
	var back := _hair.darkened(0.14)
	for e in HAIR_BACK[_hair_style]:
		_shape(_ellipse_poly(hc + Vector2(e[0], e[1]) * k, Vector2(e[2], e[3]) * k, 18), back)

func _draw_hair_front(hc: Vector2, r: float) -> void:
	var cap: Array = HAIR_CAP[_hair_style]
	var outer: float = r + float(cap[0])
	var thick: float = float(cap[1])
	var from_a: float = PI * float(cap[2])
	var to_a: float = TAU * float(cap[3])
	_shape(_crescent(hc, outer, from_a, to_a, thick), _hair)
	# Key light is upper-left, so the back of the sweep carries the shadow.
	draw_colored_polygon(_crescent(hc, outer, lerpf(from_a, to_a, 0.55), to_a, thick),
		_hair.darkened(0.26))
	var k: float = r / HEAD_R
	for e in HAIR_FRONT[_hair_style]:
		# Filled, never stroked. A 1.8px outline laid across a 21px head is a bar,
		# and the stroked lock this replaces ran vertically between the two eyes.
		draw_colored_polygon(_ellipse_poly(hc + Vector2(e[0], e[1]) * k,
			Vector2(e[2], e[3]) * k, 18), _hair)
		draw_colored_polygon(_ellipse_poly(hc + Vector2(e[0] - 1.2, e[1] + 1.2) * k,
			Vector2(e[2] * 0.34, e[3] * 0.42) * k, 12), _hair.darkened(0.26))
	# The highlight rides the middle of the crown band. It used to be two straight
	# lines across the top of the head, which at this size read as a bandage.
	draw_arc(hc, outer - thick * 0.34, lerpf(from_a, to_a, 0.17), lerpf(from_a, to_a, 0.41),
		12, _hair.lightened(0.26), 1.6)

## Faces +x; mirrored by scale.x when facing left.
func _draw_face(hc: Vector2) -> void:
	for side in [-1.0, 1.0]:
		var e := hc + Vector2(FACE_CX + EYE_DX * side, -0.8)
		# Brow shadow, iris, catchlight — a face this small still needs three parts.
		draw_colored_polygon(_ellipse_poly(e + Vector2(0, -2.3), BROW_R, 10),
			_skin.darkened(0.24))
		draw_colored_polygon(_ellipse_poly(e, EYE_R, 12), EYE_INK)
		draw_circle(e + Vector2(-0.45, -0.6), 0.62, Color(1, 1, 1, 0.92))
	draw_arc(hc + Vector2(FACE_CX + MOUTH_DX, 2.6), MOUTH_R, 0.18 * PI, 0.82 * PI, 10,
		EYE_INK, 1.3)
	draw_circle(hc + Vector2(FACE_CX + BLUSH_FAR.x, BLUSH_FAR.y), BLUSH_FAR.z,
		Color(0.92, 0.47, 0.42, 0.22))
	draw_circle(hc + Vector2(FACE_CX + BLUSH_NEAR.x, BLUSH_NEAR.y), BLUSH_NEAR.z,
		Color(0.92, 0.47, 0.42, 0.24))

func _draw_cap(hc: Vector2, r: float) -> void:
	var crown := uniform_color.darkened(0.08)
	var cc := hc + Vector2(0, -1.6)
	_shape(_crescent(cc, r + 1.0, PI * 1.01, TAU * 0.99, 6.6), crown)
	draw_colored_polygon(_crescent(cc, r + 1.0, PI * 1.42, TAU * 0.99, 6.6),
		uniform_color.darkened(0.30))
	# The peak clears the eyes by more than 2 design px and its lower edge carries
	# no stroke, so it can no longer fuse with them into a sunglasses bar.
	var peak := PackedVector2Array([
		Vector2(hc.x + CAP_PEAK_X.x, hc.y + CAP_PEAK_Y.x + 0.6),
		Vector2(hc.x + CAP_PEAK_X.y, hc.y + CAP_PEAK_Y.x),
		Vector2(hc.x + CAP_PEAK_X.y, hc.y + CAP_PEAK_Y.y),
		Vector2(hc.x + CAP_PEAK_X.x, hc.y + CAP_PEAK_Y.y - 0.4),
	])
	draw_colored_polygon(peak, uniform_color.darkened(0.34))
	draw_polyline(PackedVector2Array([peak[0], peak[1], peak[2]]), OUTLINE, OUTLINE_W)
	draw_circle(hc + Vector2(-1.4, -9.6), 1.6, UI.BRASS)

## Furthest any of a style's hair reaches from the head centre, in design px at
## the nominal head radius. The suite measures silhouette variety with this, and
## checks the tallest styles still fit inside the baked sprite.
static func hair_reach(style: int) -> float:
	var s: int = clampi(style, 0, HAIR_STYLES - 1)
	var best: float = HEAD_R + float(HAIR_CAP[s][0])
	for group in [HAIR_BACK[s], HAIR_FRONT[s]]:
		for e in group:
			var c := Vector2(e[0], e[1])
			for i in 32:
				var a: float = TAU * float(i) / 32.0
				best = maxf(best, (c + Vector2(cos(a) * float(e[2]), sin(a) * float(e[3]))).length())
	return best

## Axis-aligned bounds of a style's hair, in design px from the head centre. The
## crown is treated as a full circle, which is conservative. The suite uses this
## to prove the tall styles still fit above the baked sprite's anchor — hair that
## overruns the sprite is silently guillotined, not an error anyone would see.
static func hair_bounds(style: int) -> Rect2:
	var s: int = clampi(style, 0, HAIR_STYLES - 1)
	var outer: float = HEAD_R + float(HAIR_CAP[s][0])
	var box := Rect2(-outer, -outer, outer * 2.0, outer * 2.0)
	for group in [HAIR_BACK[s], HAIR_FRONT[s]]:
		for e in group:
			box = box.merge(Rect2(float(e[0]) - float(e[2]), float(e[1]) - float(e[3]),
				float(e[2]) * 2.0, float(e[3]) * 2.0))
	return box

## Horizontal span of every facial feature, in design px from the head centre.
static func face_extent() -> Vector2:
	var half: float = maxf(EYE_R.x, BROW_R.x)
	var lo: float = minf(minf(FACE_CX - EYE_DX - half, FACE_CX + MOUTH_DX - MOUTH_R),
		FACE_CX + BLUSH_FAR.x - BLUSH_FAR.z)
	var hi: float = maxf(maxf(FACE_CX + EYE_DX + half, FACE_CX + MOUTH_DX + MOUTH_R),
		FACE_CX + BLUSH_NEAR.x + BLUSH_NEAR.z)
	return Vector2(lo, hi)

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

## Hair crescent: an arc band whose inner edge tapers back out to meet the outer
## edge at both ends. A constant-thickness annulus closes with a radial end cap,
## and stroking that cap laid a dark bar diagonally across the cheek on every
## style whose sweep came past the horizontal.
func _crescent(center: Vector2, radius: float, from_a: float, to_a: float,
		depth: float, segments: int = 22) -> PackedVector2Array:
	var outer := PackedVector2Array()
	var inner := PackedVector2Array()
	for i in segments + 1:
		var t: float = float(i) / float(segments)
		var d := Vector2.RIGHT.rotated(lerpf(from_a, to_a, t))
		outer.append(center + d * radius)
		inner.append(center + d * (radius - depth * pow(sin(PI * t), 0.55)))
	inner.reverse()
	var pts := outer
	pts.append_array(inner)
	return pts

## Cheap filled ellipse. Named paint_ellipse, not draw_ellipse: Godot 4.5 added
## CanvasItem.draw_ellipse and the old name silently shadowed it.
func paint_ellipse(rect: Rect2, color: Color) -> void:
	draw_colored_polygon(_ellipse_poly(rect.get_center(),
		Vector2(rect.size.x * 0.5, rect.size.y * 0.5), 18), color)
