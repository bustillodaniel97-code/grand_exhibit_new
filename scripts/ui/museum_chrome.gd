extends RefCounted
## Main museum chrome: matches the shop's navy cases, brass and warm paper.
const BG:=Color("14232d")
const PANEL:=Color("213641")
const RAISED:=Color("2b4650")
const INK:=Color("f5f1e8")
const DIM:=Color("b9cece")
const BRASS:=Color("d6b579")
const TEAL:=Color("7ec4b0")
const ACTION:=Color("27766a")
const BORDER:=Color("48616a")
const DANGER:=Color("f1aa96")

static func panel(radius: int=12, fill: Color=PANEL) -> StyleBoxFlat:
	var sb:=StyleBoxFlat.new()
	sb.bg_color=fill
	sb.border_color=BORDER
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(radius)
	sb.set_content_margin_all(8)
	return sb

static func button(b: Button, active: bool=false, radius: int=12) -> void:
	b.add_theme_stylebox_override("normal",panel(radius,ACTION if active else PANEL))
	b.add_theme_stylebox_override("hover",panel(radius,ACTION.lightened(.1) if active else RAISED))
	b.add_theme_stylebox_override("pressed",panel(radius,BG))
	var focus:=panel(radius,Color.TRANSPARENT)
	focus.border_color=BRASS;focus.set_border_width_all(2)
	b.add_theme_stylebox_override("focus",focus)
	for state in ["font_color","font_hover_color","font_pressed_color","icon_normal_color","icon_hover_color","icon_pressed_color"]:
		b.add_theme_color_override(state,INK)

static func channel(fill: Color) -> StyleBoxFlat:
	var sb:=StyleBoxFlat.new();sb.bg_color=fill;sb.set_corner_radius_all(3)
	return sb
