extends Node2D
## Character — fully procedural chibi drawn in _draw (no assets, original design).
## Proportions (ours, ~44px tall): round head r=11, stubby capsule body 18x16,
## short legs, dot eyes. Variants: visitor (random skin/hair/shirt by seed),
## staff (dept uniform shirt + matching cap), porter (+ wooden docent cart with
## artifact crate), promoter (+ hand sign).
## Animates: walk bob + leg scissor while `walking`, facing flip via scale.x.

const UI := preload("res://scripts/ui/ui_kit.gd")

const SKIN_TONES: Array[Color] = [
	Color("#F2C89B"), Color("#E0AC7E"), Color("#B97F52"), Color("#8C5A38"), Color("#6E4126"),
]
const HAIR_COLORS: Array[Color] = [
	Color("#2E2620"), Color("#5A3A22"), Color("#8A5A2E"), Color("#C28A3E"),
	Color("#B0B0B0"), Color("#7A3B2E"),
]
const SHIRT_COLORS: Array[Color] = [
	Color("#4E7FB5"), Color("#C05A5A"), Color("#5F9E6A"), Color("#B58A3E"),
	Color("#7A6BB5"), Color("#4FA3A5"), Color("#B5A24E"),
]
const PANTS_COLORS: Array[Color] = [
	Color("#3A3F4A"), Color("#5A4A3A"), Color("#44546A"),
]

var is_staff: bool = false
var uniform_color: Color = Color("#C4703F")
var with_cart: bool = false        # porter: pushes a docent cart w/ artifact crate
var holding_sign: bool = false     # promoter: holds an exhibit sign
var walking: bool = false
var facing: int = 1                # 1 = right, -1 = left
var carry_stack: int = 0           # visual crate/ticket-stack count carried (porter)

var _skin: Color = SKIN_TONES[0]
var _hair: Color = HAIR_COLORS[0]
var _shirt: Color = SHIRT_COLORS[0]
var _pants: Color = PANTS_COLORS[0]
var _hair_style: int = 0
var _bob_t: float = 0.0

func _ready() -> void:
	queue_redraw()

## Deterministic random look for visitors.
func randomize_look(rng_seed: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = rng_seed
	_skin = SKIN_TONES[rng.randi() % SKIN_TONES.size()]
	_hair = HAIR_COLORS[rng.randi() % HAIR_COLORS.size()]
	_shirt = SHIRT_COLORS[rng.randi() % SHIRT_COLORS.size()]
	_pants = PANTS_COLORS[rng.randi() % PANTS_COLORS.size()]
	_hair_style = rng.randi() % 3
	queue_redraw()

func set_uniform(dept_color: Color) -> void:
	is_staff = true
	uniform_color = dept_color
	_shirt = dept_color
	_pants = dept_color.darkened(0.45)
	_hair = HAIR_COLORS[1]
	_skin = SKIN_TONES[1]
	queue_redraw()

func _process(delta: float) -> void:
	if walking:
		_bob_t += delta * 9.0
	else:
		_bob_t = 0.0
	scale.x = absf(scale.x) * float(facing)
	if walking:
		queue_redraw()

func _draw() -> void:
	var bob: float = -absf(sin(_bob_t)) * 2.5 if walking else 0.0
	var step: float = sin(_bob_t) * 3.0 if walking else 0.0
	# Shadow.
	draw_ellipse(Rect2(-11, -3, 22, 6), Color(0, 0, 0, 0.14))
	# Legs (scissor while walking).
	draw_rect(Rect2(-6 + step * 0.4, -8 + bob, 5, 7), _pants)
	draw_rect(Rect2(1 - step * 0.4, -8 + bob, 5, 7), _pants)
	# Body capsule.
	var body := Rect2(-9, -24 + bob, 18, 17)
	draw_rect(body, _shirt)
	draw_circle(Vector2(0, -24 + bob), 9, _shirt)  # rounded shoulders
	# Arms.
	draw_circle(Vector2(-9, -16 + bob - step * 0.3), 3, _shirt.darkened(0.1))
	draw_circle(Vector2(9, -16 + bob + step * 0.3), 3, _shirt.darkened(0.1))
	# Head.
	var hc := Vector2(0, -34 + bob)
	draw_circle(hc, 11, _skin)
	# Hair variants (cap / side sweep / bun).
	match _hair_style:
		0:
			draw_arc(hc, 11.5, PI, TAU, 12, _hair, 7.0, true)
		1:
			draw_arc(hc + Vector2(-2, 0), 11.5, PI * 0.9, TAU * 1.02, 12, _hair, 8.0, true)
			draw_circle(hc + Vector2(-8, -4), 4, _hair)
		_:
			draw_arc(hc, 11.5, PI, TAU, 12, _hair, 6.0, true)
			draw_circle(hc + Vector2(0, -12), 4, _hair)
	# Face (faces +x; mirrored by scale.x when facing left).
	draw_circle(hc + Vector2(3.5, -1), 1.4, UI.INK)
	draw_circle(hc + Vector2(8.0, -1), 1.4, UI.INK)
	draw_arc(hc + Vector2(5.5, 2.5), 2.6, 0.15 * PI, 0.85 * PI, 6, UI.INK, 1.2, true)
	# Staff cap: dept-colored pillbox + brim.
	if is_staff:
		var cap_c := hc + Vector2(0, -8)
		draw_rect(Rect2(cap_c.x - 8, cap_c.y - 5, 16, 6), uniform_color.darkened(0.15))
		draw_rect(Rect2(cap_c.x - 1, cap_c.y - 2, 13, 3), uniform_color.darkened(0.3))
	# Promoter sign (museum exhibit board on a stick).
	if holding_sign:
		draw_rect(Rect2(10, -46 + bob, 3, 24), UI.WALL_BROWN)
		var board := Rect2(2, -66 + bob, 30, 20)
		draw_rect(board, UI.PANEL)
		draw_rect(board, UI.WALL_BROWN, false, 2.0)
		draw_circle(board.get_center() + Vector2(-6, 0), 4, UI.ROOM_PROMO)
		draw_line(board.get_center() + Vector2(2, -4), board.get_center() + Vector2(10, 4),
			UI.ROOM_PROMO, 2.5)
	# Porter cart: wooden trolley + artifact crate (ours — not cash bags).
	if with_cart:
		var cart_x := 14.0
		draw_rect(Rect2(cart_x, -14 + bob, 20, 4), UI.WALL_BROWN)
		draw_circle(Vector2(cart_x + 3, -8 + bob), 3.4, UI.INK)
		draw_circle(Vector2(cart_x + 17, -8 + bob), 3.4, UI.INK)
		draw_line(Vector2(cart_x, -14 + bob), Vector2(cart_x - 6, -22 + bob), UI.WALL_BROWN, 2.0)
		for i in maxi(carry_stack, 1):
			var crate := Rect2(cart_x + 2, -26 + bob - float(i - 1) * 11.0, 16, 11)
			draw_rect(crate, Color("#C89B5E"))
			draw_rect(crate, UI.WALL_BROWN, false, 1.6)
			draw_line(crate.position + Vector2(3, 5.5), crate.position + Vector2(13, 5.5),
				UI.WALL_BROWN, 1.2)

func draw_ellipse(rect: Rect2, color: Color) -> void:
	# Cheap filled ellipse via scaled circle fan.
	var pts := PackedVector2Array()
	for i in 16:
		var a := TAU * float(i) / 16.0
		pts.append(rect.get_center() + Vector2(cos(a) * rect.size.x * 0.5, sin(a) * rect.size.y * 0.5))
	draw_colored_polygon(pts, color)
