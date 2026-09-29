extends RefCounted
## Main museum chrome, toy edition: warm cream cards with chunky brown borders
## and a soft drop shadow, dark cocoa ink, and saturated green actions with
## white lettering. It sits on the bright 3D diorama the way Idle Bank Tycoon's
## light panels sit on its bank, instead of the old navy cases that took a
## quarter of the screen and read as a separate, darker game.
const BG:=Color("fff3dc")        # page behind popup content
const PANEL:=Color("fffaf0")     # card / idle button
const RAISED:=Color("ffe9b8")    # emphasised card, hover
const INK:=Color("3a2a1a")       # body text
const DIM:=Color("7a6450")       # secondary text
const BRASS:=Color("c98a12")     # gold as INK (labels, eyebrows)
const TEAL:=Color("15846f")      # positive / info text
const ACTION:=Color("3fae5a")    # primary buttons
const BORDER:=Color("c9a577")    # card rims
const DANGER:=Color("d9413a")
const SHADOW:=Color(0.23, 0.16, 0.08, 0.22)
const ON_ACTION:=Color("ffffff") # text on ACTION

static func panel(radius: int=12, fill: Color=PANEL) -> StyleBoxFlat:
	var sb:=StyleBoxFlat.new()
	sb.bg_color=fill
	sb.border_color=BORDER
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(radius)
	sb.set_content_margin_all(8)
	if fill.a > 0.0:
		sb.shadow_color=SHADOW
		sb.shadow_size=3
		sb.shadow_offset=Vector2(0, 2)
	return sb

static func button(b: Button, active: bool=false, radius: int=12) -> void:
	var normal:=panel(radius,ACTION if active else PANEL)
	if active:
		normal.border_color=ACTION.darkened(0.3)
		normal.set_border_width_all(2)
		normal.border_width_bottom=4
	b.add_theme_stylebox_override("normal",normal)
	var hover:=panel(radius,ACTION.lightened(.12) if active else RAISED)
	if active:
		hover.border_color=ACTION.darkened(0.3)
		hover.border_width_bottom=4
	b.add_theme_stylebox_override("hover",hover)
	var pressed:=panel(radius,ACTION.darkened(.12) if active else RAISED.darkened(.06))
	pressed.shadow_size=0
	b.add_theme_stylebox_override("pressed",pressed)
	var disabled:=panel(radius,Color("efe6d6"))
	disabled.border_color=Color("dccbb0")
	b.add_theme_stylebox_override("disabled",disabled)
	var focus:=panel(radius,Color.TRANSPARENT)
	focus.border_color=BRASS;focus.set_border_width_all(2)
	b.add_theme_stylebox_override("focus",focus)
	var ink:=ON_ACTION if active else INK
	for state in ["font_color","font_hover_color","font_pressed_color","font_focus_color","font_hover_pressed_color",
			"icon_normal_color","icon_hover_color","icon_pressed_color","icon_focus_color","icon_hover_pressed_color"]:
		b.add_theme_color_override(state,ink)
	b.add_theme_color_override("font_disabled_color",DIM)
	if active:
		b.add_theme_color_override("font_outline_color",ACTION.darkened(0.45))
		b.add_theme_constant_override("outline_size",4)
	else:
		b.remove_theme_constant_override("outline_size")

static func channel(fill: Color) -> StyleBoxFlat:
	var sb:=StyleBoxFlat.new();sb.bg_color=fill;sb.set_corner_radius_all(3)
	return sb
