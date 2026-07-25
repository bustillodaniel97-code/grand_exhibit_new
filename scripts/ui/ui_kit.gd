extends RefCounted
## UI Kit v2 — shared palette + widget factories for every screen (SPEC §2).
## Plain RefCounted with statics. NO class_name: callers preload this file.
## v2: Kenney CC0 skin — nine-patch StyleBoxTexture buttons/panels/bars, icon
## factory, currency chips, press-squish feel, click/buy SFX. All v1 signatures
## (make_panel/make_button/make_badge/make_label/make_dot + palette constants)
## are preserved so existing callers keep working unchanged.

# --- Palette (single source of truth; SPEC §2) -------------------------------
## Vivid, high-chroma scheme. The original "warm museum" palette was built from
## desaturated earth tones (cream #F5EFE0, terracotta #C4703F, muted sage and
## slate) which on a phone read as beige office software rather than a game.
## Everything here is pushed up in saturation and separated in hue so the four
## departments are instantly distinguishable, and each colour keeps enough
## contrast against PANEL to carry white or INK text at small sizes.
const BG := Color("#2A2150")        # deep indigo — makes every bright element pop
const BG_DEEP := Color("#1B1538")   # gradient floor / behind-card wash
const INK := Color("#2B2245")       # body text on light cards
const PANEL := Color("#FFF9F0")     # card surface
const PANEL_SOFT := Color("#F3ECFF")# secondary surface, faint violet cast
## Page background INSIDE a popup card. Distinct from BG on purpose: BG is the
## app shell behind the world and is deep indigo, while a popup's own page must
## stay light because every screen draws INK-coloured body text on it. Pointing
## screens at BG made all seven of them dark-on-dark after the repaint.
const SURFACE := Color("#F7F2FF")
const ACCENT := Color("#FF7A3D")    # vivid orange — primary action
const BRASS := Color("#FFC53D")     # bright gold — currency, rewards
const SAGE := Color("#2ED573")      # vivid green — confirm, income
const SLATE := Color("#3BA9F5")     # bright azure — info, archive
const PLUM := Color("#B45CF0")      # vivid violet — promotions, premium
const DANGER := Color("#FF4757")    # hot red — unaffordable / bottleneck

const DEPT_COLORS := {
	"promotions": Color("#B45CF0"),
	"ticket": Color("#FF7A3D"),
	"archive": Color("#3BA9F5"),
	"gallery": Color("#FFC53D"),
}

## Rarity tiers. Manager collection is a core hook in this genre, so the tiers
## have to be unmistakable at thumb size — these are separated by hue, not just
## by lightness, which is what the previous grey/slate/plum/brass set failed at.
const RARITY_COLORS := {
	"common": Color("#8FA3B8"),      # cool grey-blue
	"rare": Color("#3BA9F5"),        # azure
	"epic": Color("#B45CF0"),        # violet
	"legendary": Color("#FFC53D"),   # gold
}
const LOCKED := Color("#5A4E86")     # undiscovered slot on the deep shell

# --- Type scale (design px at 720x1280; ~1.5x on a 1080p phone) --------------
const TYPE_HERO := 40      # cash readout, welcome-back amount
const TYPE_DISPLAY := 32   # screen titles
const TYPE_TITLE := 24     # card titles, section heads
const TYPE_HEADING := 20   # row titles, button labels
const TYPE_BODY := 17      # prose, descriptions
const TYPE_LABEL := 15     # chips, stat rows
const TYPE_CAPTION := 13   # counters, fine print

# --- Mobile metrics ----------------------------------------------------------
## Android's minimum comfortable touch target is 48dp; at this design width one
## design px ~= one dp on a 1080p phone, so 48 is the floor for anything tappable.
const TOUCH_MIN := 48
const RADIUS_CARD := 18
const RADIUS_BUTTON := 14
const GUTTER := 16

# --- Living-floor diorama palette (bold room accents, SPEC §9 floor pass) ----
## Saturated to match the UI. Each room now owns a clearly separated hue so the
## floor reads as four distinct places at a glance instead of four beige boxes.
const UPGRADE_GREEN := Color("#22C55E")   # big buy/upgrade buttons
const FLOOR_CREAM := Color("#FFF0D2")     # hall floorboards
const ROOM_TICKET := Color("#FF9A3D")     # ticket hall accent
const ROOM_GALLERY := Color("#FFD23F")    # grand gallery accent
const ROOM_VAULT := Color("#4FB8F7")      # archive vault accent
const ROOM_PROMO := Color("#C86DF0")      # promotions corner accent
const CARPET_RED := Color("#FF4757")      # entrance carpet
const ROPE_RED := Color("#D62F44")        # queue rope velvet
const WALL_BROWN := Color("#5A3E2B")      # diorama outlines / wood

# --- Kenney CC0 asset registry (assets/ui — see CREDITS.md) ------------------
const _BTN_NORMAL := "res://assets/ui/buttons/btn_rect_normal.png"
const _BTN_PRESSED := "res://assets/ui/buttons/btn_rect_pressed.png"
const _BTN_SQ_NORMAL := "res://assets/ui/buttons/btn_sq_normal.png"
const _BTN_SQ_PRESSED := "res://assets/ui/buttons/btn_sq_pressed.png"
const _PANEL_LIGHT := "res://assets/ui/panels/panel_light.png"
const _PANEL_PARCHMENT := "res://assets/ui/panels/panel_parchment.png"
const _PANEL_INSET := "res://assets/ui/panels/panel_inset.png"
const _PANEL_DARK := "res://assets/ui/panels/panel_dark.png"
const _BAR_BG := "res://assets/ui/bars/bar_bg.png"
const _BAR_FILLS := {
	"green": "res://assets/ui/bars/bar_fill_green.png",
	"yellow": "res://assets/ui/bars/bar_fill_yellow.png",
	"blue": "res://assets/ui/bars/bar_fill_blue.png",
	"red": "res://assets/ui/bars/bar_fill_red.png",
}
const _DIVIDER := "res://assets/ui/divider.png"
## Quicksand (OFL-1.1) — rounded geometric sans. Two weights only: display for
## headings/numbers/buttons, body for prose. Replaces Kenney Future, whose "X"
## renders as "H" and "$" as "S" — the old kit dodged that with a per-string
## fallback that left the UI mixing two typefaces at random.
const _FONT_DISPLAY := "res://assets/fonts/Quicksand-Bold.ttf"
const _FONT_BODY := "res://assets/fonts/Quicksand-Medium.ttf"
const _SFX := {
	"click": "res://assets/ui/sfx/click.ogg",
	"tap": "res://assets/ui/sfx/tap.ogg",
	"buy": "res://assets/ui/sfx/buy.ogg",
}
## Named icons -> white/tintable PNGs (game-icons) or pre-colored derived PNGs.
const ICONS := {
	"cash": "res://assets/ui/icons/coin.png",
	"gems": "res://assets/ui/icons/gem.png",
	"insight": "res://assets/ui/icons/star.png",
	"star": "res://assets/ui/icons/star.png",
	"star_depth": "res://assets/ui/icons/star_depth.png",
	"star_outline": "res://assets/ui/icons/star_outline.png",
	"lock": "res://assets/ui/icons/locked.png",
	"unlock": "res://assets/ui/icons/unlocked.png",
	"check": "res://assets/ui/icons/checkmark.png",
	"cross": "res://assets/ui/icons/cross.png",
	"arrow_right": "res://assets/ui/icons/arrowRight.png",
	"arrow_up": "res://assets/ui/icons/arrowUp.png",
	"gear": "res://assets/ui/icons/gear.png",
	"trophy": "res://assets/ui/icons/trophy.png",
	"medal": "res://assets/ui/icons/medal1.png",
	"cart": "res://assets/ui/icons/cart.png",
	"home": "res://assets/ui/icons/home.png",
	"exclamation": "res://assets/ui/icons/exclamation.png",
	"question": "res://assets/ui/icons/question.png",
	"disc": "res://assets/ui/icons/disc.png",
}

# Neutral grey button texture's mid-tone: tint compensation so modulate colors
# land on the requested palette color instead of darkening ~15%.
const _BTN_BASE := Color(0.855, 0.863, 0.906)
# panel_light.png parchment fill: compensate when a near-white panel is wanted.
const _PANEL_BASE := Color(0.925, 0.890, 0.808)

static var _cache := {}          # path -> Resource (textures, fonts, streams)
static var _icon_cache := {}     # "name@size" -> ImageTexture (prescaled)
static var _sfx_player: AudioStreamPlayer = null

static func _res(path: String) -> Resource:
	if not _cache.has(path):
		_cache[path] = load(path)
	return _cache[path]

## Heading / number / button face.
static func font() -> Font:
	return _res(_FONT_DISPLAY) as Font

## Prose face.
static func body_font() -> Font:
	return _res(_FONT_BODY) as Font

## Make Quicksand the engine-wide default so every Control that never asks for a
## font still gets one — no more Open Sans leaking through next to the game face.
## Idempotent; call once at boot (main.gd) and from any standalone screen test.
static func install_default_font() -> void:
	if ThemeDB.fallback_font != body_font():
		ThemeDB.fallback_font = body_font()
		ThemeDB.fallback_font_size = TYPE_BODY

static func _apply_display_font(c: Control, _text: String = "") -> void:
	c.add_theme_font_override("font", font())

## Public wrapper for screens that restyle their own labels. The `text` argument
## is vestigial (the old kit chose a face per string); kept so callers compile.
static func apply_display_font(c: Control, _text: String = "") -> void:
	_apply_display_font(c)

## Prescaled icon texture (game-icons ship at 100px; scale once, cache).
static func icon_texture(name: String, size: int = 24) -> Texture2D:
	var key := "%s@%d" % [name, size]
	if _icon_cache.has(key):
		return _icon_cache[key]
	var path: String = ICONS.get(name, "")
	if path == "":
		push_warning("ui_kit: unknown icon '%s'" % name)
		return null
	var tex: Texture2D = _res(path) as Texture2D
	if tex == null:
		return null
	var img: Image = tex.get_image()
	if img == null:
		return tex
	var w: int = img.get_width()
	var h: int = img.get_height()
	if maxi(w, h) <= size:
		_icon_cache[key] = tex
		return tex
	var scale := float(size) / float(maxi(w, h))
	img.resize(maxi(1, int(w * scale)), maxi(1, int(h * scale)), Image.INTERPOLATE_LANCZOS)
	var out := ImageTexture.create_from_image(img)
	_icon_cache[key] = out
	return out

# ---------------------------------------------------------------- safe area

## Largest share of the viewport any single inset may claim. A safe area is
## trim, never layout: if the platform hands back something implausible we would
## rather ignore it than let it eat the screen.
const _SAFE_AREA_MAX_FRACTION := 0.12

## Display safe-area insets converted into design/canvas units, so the top bar
## clears a notch or punch-hole and the bottom bar clears the gesture pill.
## Returns {"top","bottom","left","right"}.
##
## Mobile only, deliberately. On desktop `get_display_safe_area()` reports the
## whole screen work area (e.g. 1920x1034), which bears no relation to the game
## window — trusting it there gave the bottom nav a 254px phantom inset and tore
## the layout in half. Zero everywhere except Android/iOS.
static func safe_area_insets(c: Control) -> Dictionary:
	var zero := {"top": 0.0, "bottom": 0.0, "left": 0.0, "right": 0.0}
	if c == null or not c.is_inside_tree():
		return zero
	if not (OS.get_name() in ["Android", "iOS"]):
		return zero
	var win: Vector2i = DisplayServer.window_get_size()
	if win.x <= 0 or win.y <= 0:
		return zero
	var sa: Rect2i = DisplayServer.get_display_safe_area()
	if sa.size.x <= 0 or sa.size.y <= 0:
		return zero
	# Canvas units per physical pixel under the "canvas_items" stretch mode.
	var vis: Vector2 = c.get_viewport_rect().size
	var kx: float = vis.x / float(win.x)
	var ky: float = vis.y / float(win.y)
	var cap_x: float = vis.x * _SAFE_AREA_MAX_FRACTION
	var cap_y: float = vis.y * _SAFE_AREA_MAX_FRACTION
	return {
		"top": clampf(float(sa.position.y) * ky, 0.0, cap_y),
		"bottom": clampf(float(win.y - (sa.position.y + sa.size.y)) * ky, 0.0, cap_y),
		"left": clampf(float(sa.position.x) * kx, 0.0, cap_x),
		"right": clampf(float(win.x - (sa.position.x + sa.size.x)) * kx, 0.0, cap_x),
	}

# ---------------------------------------------------------------- styleboxes

## v1 signature preserved (returns StyleBoxFlat: dept walls mutate border_color).
## v2: adds a soft drop shadow for the crafted "paper on desk" feel.
static func make_panel(color: Color, radius: int = 12, border: int = 0) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = color
	sb.set_corner_radius_all(radius)
	if border > 0:
		sb.set_border_width_all(border)
		sb.border_color = color.darkened(0.35)
	sb.shadow_color = Color(0.12, 0.09, 0.05, 0.22)
	sb.shadow_size = 4
	sb.shadow_offset = Vector2(0, 2)
	return sb

static func _nine_patch(path: String, m: int, modulate: Color,
		ml: int = 14, mr: int = 14, mt: int = 12, mb: int = 12) -> StyleBoxTexture:
	var sb := StyleBoxTexture.new()
	sb.texture = _res(path) as Texture2D
	sb.texture_margin_left = m
	sb.texture_margin_right = m
	sb.texture_margin_top = m
	sb.texture_margin_bottom = m
	sb.modulate_color = modulate
	sb.content_margin_left = ml
	sb.content_margin_right = mr
	sb.content_margin_top = mt
	sb.content_margin_bottom = mb
	return sb

## Compensated tint: modulate that lands on `color` given a base texture tone.
static func _compensate(color: Color, base: Color) -> Color:
	return Color(
		clampf(color.r / base.r, 0.0, 1.25),
		clampf(color.g / base.g, 0.0, 1.25),
		clampf(color.b / base.b, 0.0, 1.25),
		color.a)

## Card panel. Flat, rounded and lightly shadowed rather than a tinted parchment
## nine-patch: the Kenney parchment carried its own beige value, so tinting it
## with the new saturated palette turned every card muddy. A flat fill lets the
## palette read at full chroma.
static func make_card(color: Color = PANEL) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = color
	sb.set_corner_radius_all(RADIUS_CARD)
	sb.set_content_margin_all(14)
	sb.shadow_color = Color(0.06, 0.03, 0.16, 0.30)
	sb.shadow_size = 6
	sb.shadow_offset = Vector2(0, 3)
	return sb

## Framed panel: card plus a saturated rim — offers, lootboxes, rarity frames.
static func make_frame(tint: Color = PANEL) -> StyleBoxFlat:
	var sb := make_card(PANEL)
	sb.set_border_width_all(3)
	sb.border_color = tint if tint != PANEL else BRASS
	return sb

## Inset well: recessed surface (empty slots, sunken areas).
static func make_inset(tint: Color = PANEL_SOFT) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = tint.darkened(0.06)
	sb.set_corner_radius_all(RADIUS_BUTTON)
	sb.set_content_margin_all(10)
	sb.set_border_width_all(2)
	sb.border_color = tint.darkened(0.18)
	return sb

## Dark panel (toasts, dramatic headers).
static func make_dark_panel() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = BG_DEEP
	sb.set_corner_radius_all(RADIUS_CARD)
	sb.set_content_margin_all(14)
	sb.shadow_color = Color(0, 0, 0, 0.35)
	sb.shadow_size = 6
	return sb

## Progress bar track — deep, so a bright fill reads as light inside a channel.
static func make_bar_bg() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = BG_DEEP.lerp(PANEL, 0.18)
	sb.set_corner_radius_all(10)
	sb.set_border_width_all(2)
	sb.border_color = BG_DEEP.lerp(PANEL, 0.06)
	return sb

const _BAR_COLORS := {
	"green": Color("#2ED573"), "yellow": Color("#FFC53D"),
	"blue": Color("#3BA9F5"), "red": Color("#FF4757"),
}

static func make_bar_fill(kind: String = "green") -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = _BAR_COLORS.get(kind, _BAR_COLORS["green"])
	sb.set_corner_radius_all(10)
	# Lit top edge so the fill looks like a glossy capsule, not a flat block.
	sb.border_width_top = 3
	sb.border_color = (sb.bg_color as Color).lightened(0.35)
	return sb

# --- Floating chrome (HUD, nav and quest chips drawn over the world) ---------
## Base tone for chrome that floats instead of sitting on a panel. Deeper than BG
## so a pill still separates from the shell behind it.
const GLASS := Color("#171132")

## Translucent "glass" pill for floating chrome. The shell bars used to be opaque
## cream slabs: together they painted a fifth of the portrait canvas light, and
## the cream currency chips landed on a same-coloured backing (1.00:1, visible
## only by their shadow). Floating chrome instead carries its own deep surface
## plus a light hairline, which holds up over a bright room as well as over the
## deep shell.
static func make_glass(radius: int = RADIUS_BUTTON, alpha: float = 0.86,
		rim: Color = Color(1, 1, 1, 0.18)) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(GLASS.r, GLASS.g, GLASS.b, alpha)
	sb.set_corner_radius_all(radius)
	sb.set_content_margin_all(8)
	if rim.a > 0.0:
		sb.set_border_width_all(2)
		sb.border_color = rim
	sb.shadow_color = Color(0, 0, 0, 0.38)
	sb.shadow_size = 5
	sb.shadow_offset = Vector2(0, 2)
	return sb

## Bar trough for a progress bar drawn ON dark chrome. make_bar_bg's track is
## tuned to sit in a light card and reads at 1.45:1 against the deep shell; this
## one is a lightened channel cut into the pill that hosts it.
static func make_channel(tint: Color = Color(1, 1, 1, 0.16), radius: int = 10) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = tint
	sb.set_corner_radius_all(radius)
	sb.set_border_width_all(1)
	sb.border_color = Color(0, 0, 0, 0.35)
	return sb

## Label styling for text that floats over unknown pixels: white with a dark rim.
static func add_text_halo(l: Label, halo: Color = Color(0, 0, 0, 0.55), size: int = 4) -> Label:
	l.add_theme_color_override("font_outline_color", halo)
	l.add_theme_constant_override("outline_size", size)
	return l

# ---------------------------------------------------------------- widgets

## v1 signature preserved. v2: nine-patch texture states (depth edge on normal,
## flat on pressed = physically "pushed in"), Kenney Future font, squish + click.
static func make_button(text: String, bg: Color) -> Button:
	var b := Button.new()
	b.text = text
	skin_button(b, bg)
	return b

## Apply the full v2 button treatment to an existing Button.
static func skin_button(b: Button, bg: Color) -> Button:
	# Lone "X"/"✕" close buttons become a real cross icon — a glyph that small is
	# a poor touch affordance on a phone. Tag them so callers and tests can still
	# find the close control without matching on label text (which is now empty).
	if b.text.strip_edges() in ["X", "✕", "x", "×"]:
		b.text = ""
		b.icon = icon_texture("cross", 24)
		b.set_meta("role", "close")
		b.tooltip_text = "Close"
		if b.custom_minimum_size.x < TOUCH_MIN:
			b.custom_minimum_size = Vector2(TOUCH_MIN, TOUCH_MIN)
	else:
		_apply_display_font(b)
	b.add_theme_font_size_override("font_size", TYPE_HEADING)
	b.add_theme_color_override("font_color", Color.WHITE)
	b.add_theme_color_override("font_hover_color", Color.WHITE)
	b.add_theme_color_override("font_pressed_color", Color(1, 1, 1, 0.9))
	b.add_theme_color_override("font_disabled_color", Color(1, 1, 1, 0.6))
	# Dark rim keeps white text legible on the lighter accents (gold especially).
	b.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.35))
	b.add_theme_constant_override("outline_size", 3)
	retint_button(b, bg)
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	add_press_squish(b)
	return b

## Chunky candy button: flat saturated fill, lighter top edge, thick darker
## bottom edge for the extruded look, and on press the bottom edge collapses so
## the cap physically sinks. Replaces the tinted grey nine-patch, which muddied
## every saturated colour it was given.
##
## Use this — not skin_button — on any repeating refresh: skin_button also wires
## press-feel signals, and re-running it on a timer stacks duplicate connections
## (and duplicate click SFX).
static func retint_button(b: Button, bg: Color) -> Button:
	b.add_theme_stylebox_override("normal", _button_box(bg, 6))
	b.add_theme_stylebox_override("hover", _button_box(bg.lightened(0.12), 6))
	b.add_theme_stylebox_override("pressed", _button_box(bg.darkened(0.10), 2, 4))
	b.add_theme_stylebox_override("disabled",
		_button_box(bg.lerp(Color(0.42, 0.40, 0.50), 0.62), 4))
	return b

static func _button_box(bg: Color, lip: int, top_pad_extra: int = 0) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.set_corner_radius_all(RADIUS_BUTTON)
	sb.border_width_bottom = lip
	sb.border_width_top = 2
	sb.border_color = bg.darkened(0.32)
	sb.content_margin_left = 16
	sb.content_margin_right = 16
	sb.content_margin_top = 10 + top_pad_extra
	sb.content_margin_bottom = 12 - top_pad_extra
	sb.shadow_color = Color(0.06, 0.03, 0.16, 0.22)
	sb.shadow_size = 3
	sb.shadow_offset = Vector2(0, 2)
	return sb

## Small square icon button — close buttons, icon chips. Same candy treatment as
## the text buttons so nothing in the kit still renders on the old grey texture.
static func make_icon_button(icon_name: String, bg: Color, size: int = 52) -> Button:
	var b := Button.new()
	b.custom_minimum_size = Vector2(maxi(size, TOUCH_MIN), maxi(size, TOUCH_MIN))
	b.add_theme_font_override("font", font())
	retint_button(b, bg)
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	b.icon = icon_texture(icon_name, int(size * 0.55))
	add_press_squish(b)
	return b

## Press "squish": subtle scale dip on button_down, spring back on release.
static func add_press_squish(b: BaseButton) -> void:
	b.pivot_offset = b.size / 2.0
	b.resized.connect(func() -> void:
		if is_instance_valid(b):
			b.pivot_offset = b.size / 2.0)
	b.button_down.connect(func() -> void: _squish_to(b, Vector2(0.93, 0.88), 0.06))
	b.button_up.connect(func() -> void: _squish_to(b, Vector2.ONE, 0.14))
	b.pressed.connect(func() -> void: play_sfx(b, "click"))

static func _squish_to(b: BaseButton, target: Vector2, secs: float) -> void:
	if not is_instance_valid(b):
		return
	if not b.is_inside_tree():
		b.scale = target
		return
	var tw: Tween = b.create_tween()
	tw.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(b, "scale", target, secs)

## Floating circular badge: dept icon letter on a colored disc (SPEC §9).
## v1 signature preserved; v2 adds soft shadow (via make_panel) + display font.
static func make_badge(letter: String, color: Color) -> Control:
	var p := PanelContainer.new()
	p.custom_minimum_size = Vector2(56, 56)
	p.add_theme_stylebox_override("panel", make_panel(color, 28, 0))
	var l := Label.new()
	l.text = letter
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_apply_display_font(l)
	l.add_theme_font_size_override("font_size", TYPE_TITLE)
	l.add_theme_color_override("font_color", Color.WHITE)
	p.add_child(l)
	return p

## Body-face label (prose, descriptions, stat rows).
static func make_label(text: String, size: int = TYPE_BODY) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", body_font())
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", INK)
	return l

## Display-font label (headers / numbers that should feel "designed").
static func make_display_label(text: String, size: int = TYPE_TITLE, color: Color = INK) -> Label:
	var l := make_label(text, size)
	_apply_display_font(l)
	l.add_theme_color_override("font_color", color)
	return l

## Small filled circle (queue/cart/staff dots in dept visual strips).
static func make_dot(color: Color, diameter: int = 14) -> Control:
	var p := Panel.new()
	p.custom_minimum_size = Vector2(diameter, diameter)
	p.set_anchors_preset(Control.PRESET_TOP_LEFT)
	p.size = Vector2(diameter, diameter)
	var sb := StyleBoxFlat.new()
	sb.bg_color = color
	sb.set_corner_radius_all(diameter / 2)
	p.add_theme_stylebox_override("panel", sb)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return p

## Named icon as a fixed-size TextureRect. Tint white icons via `tint`.
static func make_icon(name: String, size: int = 24, tint: Color = Color(1, 1, 1)) -> TextureRect:
	var tr := TextureRect.new()
	tr.texture = icon_texture(name, size)
	tr.custom_minimum_size = Vector2(size, size)
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	tr.modulate = tint
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return tr

## Currency chip: parchment card + icon + value label (HUD, screen headers).
## Update the value later via chip_value_label(chip).text = "...".
static func make_currency_chip(icon_name: String, value: String,
		tint: Color = Color(1, 1, 1), font_size: int = 24) -> PanelContainer:
	var chip := PanelContainer.new()
	chip.add_theme_stylebox_override("panel", make_card(PANEL))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	chip.add_child(row)
	row.add_child(make_icon(icon_name, int(font_size * 1.15), tint))
	var l := make_display_label(value, font_size, INK)
	l.name = "ValueLabel"
	row.add_child(l)
	chip.set_meta("value_label", l)
	return chip

static func chip_value_label(chip: Control) -> Label:
	return chip.get_meta("value_label", null) as Label

static func set_chip_value(chip: Control, text: String) -> void:
	var l := chip_value_label(chip)
	if l != null:
		l.text = text

## Thin horizontal divider line (subtle separators, HUD rows).
static func make_divider(tint: Color = Color(0.45, 0.38, 0.28, 0.5)) -> TextureRect:
	var tr := TextureRect.new()
	tr.texture = _res(_DIVIDER) as Texture2D
	tr.custom_minimum_size = Vector2(0, 4)
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_TILE
	tr.modulate = tint
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tr.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return tr

# ---------------------------------------------------------------- SFX (CC0)

## Play a UI sound ("click"/"tap"/"buy"). No autoload: one shared
## AudioStreamPlayer is parked on the tree root on first use.
## Respects GameState.settings["sfx"] when GameState is present.
static func play_sfx(anchor: Node, kind: String = "click") -> void:
	if anchor == null or not anchor.is_inside_tree():
		return
	if not _sfx_enabled(anchor):
		return
	if _sfx_player == null or not is_instance_valid(_sfx_player):
		_sfx_player = AudioStreamPlayer.new()
		_sfx_player.name = "UiKitSfx"
		_sfx_player.bus = "Master"
		anchor.get_tree().root.add_child(_sfx_player)
	var stream := _res(_SFX.get(kind, _SFX["click"])) as AudioStream
	if stream == null:
		return
	_sfx_player.stream = stream
	_sfx_player.play()

static func _sfx_enabled(anchor: Node) -> bool:
	var tree := anchor.get_tree()
	if tree == null:
		return false
	var gs: Node = tree.root.get_node_or_null("GameState")
	if gs == null:
		return true
	var settings: Variant = gs.get("settings")
	if settings is Dictionary:
		return bool(settings.get("sfx", true))
	return true
