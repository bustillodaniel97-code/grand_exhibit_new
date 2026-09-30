extends RefCounted
## Main museum chrome, 2026 edition: white cards on a soft neutral page, one
## hairline rim and a wide, faint shadow instead of chunky brown borders; pill
## buttons with a single calm green-teal action colour; near-black ink set in
## Inter. It replaces the cream-and-brass "toy" chrome, whose thick rims,
## outlined lettering and parchment tones read as antique next to the matte
## diorama. Every popup, the HUD, the rail and the nav draw from here.
const BG:=Color("f2f3f1")        # page behind popup content, shell bars
const PANEL:=Color("ffffff")     # card / idle button
const RAISED:=Color("eef2f0")    # emphasised card, hover
const INK:=Color("1b2327")       # body text
const DIM:=Color("69737a")       # secondary text
const BRASS:=Color("a2741c")     # gold as ink (labels, eyebrows, rewards)
const TEAL:=Color("22786a")      # positive / info text
const ACTION:=Color("2b8468")    # primary buttons
const BORDER:=Color("e1e5e3")    # hairline card rims, dividers
const DANGER:=Color("d2463e")
const SHADOW:=Color(0.07, 0.11, 0.13, 0.09)
const ON_ACTION:=Color("ffffff") # text on ACTION

## Rounder than the old chrome at every size: callers still pass the radius
## they were written with, and get the modern equivalent.
static func radius(r: int) -> int:
	return 0 if r <= 0 else r + 8

## White or ink, whichever reads better on `fill`.
static func on_color(fill: Color) -> Color:
	# WCAG contrast, measured in linear light.
	var l := fill.srgb_to_linear().get_luminance()
	var white := 1.05 / (l + 0.05)
	var ink := (l + 0.05) / (INK.srgb_to_linear().get_luminance() + 0.05)
	return ON_ACTION if white >= ink else INK

static func panel(r: int=12, fill: Color=PANEL) -> StyleBoxFlat:
	var sb:=StyleBoxFlat.new()
	sb.bg_color=fill
	sb.border_color=BORDER
	sb.set_border_width_all(1 if fill.a > 0.0 else 0)
	sb.set_corner_radius_all(radius(r))
	sb.corner_detail=10
	sb.set_content_margin_all(8)
	if fill.a > 0.0:
		sb.shadow_color=SHADOW
		sb.shadow_size=10
		sb.shadow_offset=Vector2(0, 3)
	return sb

## Filled or quiet pill. Active: the action colour with white lettering and a
## soft tinted glow. Idle: a white chip with a hairline. No outlines on text,
## no extruded lip — pressing darkens the fill and drops the shadow.
static func button(b: Button, active: bool=false, r: int=12) -> void:
	var fill:=ACTION if active else PANEL
	var normal:=_pill(r, fill, active)
	b.add_theme_stylebox_override("normal",normal)
	b.add_theme_stylebox_override("hover",_pill(r, ACTION.lightened(.08) if active else RAISED, active))
	var pressed:=_pill(r, ACTION.darkened(.12) if active else Color("e4e9e7"), active)
	pressed.shadow_size=0
	b.add_theme_stylebox_override("pressed",pressed)
	var disabled:=_pill(r, Color("eceeed"), false)
	disabled.set_border_width_all(0)
	disabled.shadow_size=0
	b.add_theme_stylebox_override("disabled",disabled)
	var focus:=StyleBoxFlat.new()
	focus.draw_center=false
	focus.set_corner_radius_all(radius(r) + 2)
	focus.border_color=Color(ACTION, 0.4)
	focus.set_border_width_all(2)
	focus.set_expand_margin_all(2)
	b.add_theme_stylebox_override("focus",focus)
	var ink:=ON_ACTION if active else INK
	for state in ["font_color","font_hover_color","font_pressed_color","font_focus_color","font_hover_pressed_color",
			"icon_normal_color","icon_hover_color","icon_pressed_color","icon_focus_color","icon_hover_pressed_color"]:
		b.add_theme_color_override(state,ink)
	b.add_theme_color_override("font_disabled_color",Color("a3abae"))
	b.add_theme_color_override("icon_disabled_color",Color("a3abae"))
	b.add_theme_constant_override("outline_size",0)

static func _pill(r: int, fill: Color, active: bool) -> StyleBoxFlat:
	var sb:=panel(r, fill)
	sb.content_margin_left=14
	sb.content_margin_right=14
	sb.content_margin_top=6
	sb.content_margin_bottom=6
	if active:
		sb.set_border_width_all(0)
		sb.shadow_color=Color(fill.darkened(0.2), 0.28)
		sb.shadow_size=8
		sb.shadow_offset=Vector2(0, 3)
	else:
		sb.shadow_color=Color(SHADOW, 0.05)
		sb.shadow_size=4
		sb.shadow_offset=Vector2(0, 1)
	return sb

## Progress track / fill: a slim fully rounded bar.
static func channel(fill: Color) -> StyleBoxFlat:
	var sb:=StyleBoxFlat.new();sb.bg_color=fill;sb.set_corner_radius_all(6)
	return sb
