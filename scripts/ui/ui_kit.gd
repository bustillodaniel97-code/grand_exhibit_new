extends RefCounted
## UI Kit — shared palette + widget factories for the venue-ui shell (SPEC §2).
## Plain RefCounted with statics. NO class_name: other branches must NOT import this
## (they hardcode the same hex values in their own files per SPEC §2).

const BG := Color("#F5EFE0")        # cream
const INK := Color("#33312E")
const PANEL := Color("#FFFDF6")
const ACCENT := Color("#C4703F")    # terracotta
const BRASS := Color("#B08D3E")
const SAGE := Color("#7A9B76")
const SLATE := Color("#5B7B8C")
const PLUM := Color("#8E6C8A")
const DANGER := Color("#B03A2E")    # unaffordable / bottleneck red

const DEPT_COLORS := {
	"promotions": Color("#8E6C8A"),
	"ticket": Color("#C4703F"),
	"archive": Color("#5B7B8C"),
	"gallery": Color("#B08D3E"),
}

# --- Living-floor diorama palette (bold room accents, SPEC §9 floor pass) ----
const UPGRADE_GREEN := Color("#3E9B4F")   # big buy/upgrade buttons
const FLOOR_CREAM := Color("#F7E8C9")     # hall floorboards
const ROOM_TICKET := Color("#E8833A")     # ticket hall accent
const ROOM_GALLERY := Color("#F0C75E")    # grand gallery accent
const ROOM_VAULT := Color("#6C8EBF")      # archive vault accent
const ROOM_PROMO := Color("#B570B8")      # promotions corner accent
const CARPET_RED := Color("#C0392B")      # entrance carpet
const ROPE_RED := Color("#8E2F24")        # queue rope velvet
const WALL_BROWN := Color("#6B4A2F")      # diorama outlines / wood

## Rounded panel style. border > 0 draws a border in a darkened shade of `color`;
## override border_color afterwards for dept zone walls (SPEC §2: radius 12, width 3).
static func make_panel(color: Color, radius: int = 12, border: int = 0) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = color
	sb.set_corner_radius_all(radius)
	if border > 0:
		sb.set_border_width_all(border)
		sb.border_color = color.darkened(0.35)
	return sb

static func make_button(text: String, bg: Color) -> Button:
	var b := Button.new()
	b.text = text
	b.add_theme_font_size_override("font_size", 22)
	b.add_theme_color_override("font_color", Color.WHITE)
	b.add_theme_color_override("font_hover_color", Color.WHITE)
	b.add_theme_color_override("font_pressed_color", Color.WHITE)
	b.add_theme_color_override("font_disabled_color", Color(1, 1, 1, 0.65))
	b.add_theme_stylebox_override("normal", make_panel(bg, 10, 0))
	b.add_theme_stylebox_override("hover", make_panel(bg.lightened(0.08), 10, 0))
	b.add_theme_stylebox_override("pressed", make_panel(bg.darkened(0.12), 10, 0))
	b.add_theme_stylebox_override("disabled", make_panel(bg.lerp(Color(0.55, 0.53, 0.5), 0.6), 10, 0))
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	return b

## Floating circular badge: dept icon letter on a colored disc (SPEC §9).
static func make_badge(letter: String, color: Color) -> Control:
	var p := PanelContainer.new()
	p.custom_minimum_size = Vector2(56, 56)
	p.add_theme_stylebox_override("panel", make_panel(color, 28, 0))
	var l := Label.new()
	l.text = letter
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", 26)
	l.add_theme_color_override("font_color", Color.WHITE)
	p.add_child(l)
	return p

static func make_label(text: String, size: int) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", INK)
	return l

## Small filled circle (queue/cart/staff dots in dept visual strips).
static func make_dot(color: Color, diameter: int = 14) -> Control:
	var p := Panel.new()
	p.custom_minimum_size = Vector2(diameter, diameter)
	p.set_anchors_preset(Control.PRESET_TOP_LEFT)
	p.size = Vector2(diameter, diameter)
	p.add_theme_stylebox_override("panel", make_panel(color, diameter / 2, 0))
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return p
