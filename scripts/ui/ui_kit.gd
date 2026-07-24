extends RefCounted
## UI Kit v2 — shared palette + widget factories for every screen (SPEC §2).
## Plain RefCounted with statics. NO class_name: callers preload this file.
## v2: Kenney CC0 skin — nine-patch StyleBoxTexture buttons/panels/bars, icon
## factory, currency chips, press-squish feel, click/buy SFX. All v1 signatures
## (make_panel/make_button/make_badge/make_label/make_dot + palette constants)
## are preserved so existing callers keep working unchanged.

# --- Palette (single source of truth; SPEC §2 warm museum scheme) -----------
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
const _FONT_MAIN := "res://assets/fonts/KenneyFuture.ttf"
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

static func font() -> Font:
	return _res(_FONT_MAIN) as Font

## Kenney Future is all-caps display type whose "X" glyph reads as "H" — fatal
## for "Grand eXhibit" — and whose "$" reads as a plain "S". Apply it only to
## text without those glyphs; other text keeps the default font. Single
## "X"/"✕" button labels become a real cross icon instead.
static func _needs_font_fallback(text: String) -> bool:
	return text.to_lower().contains("x") or text.contains("$")

static func _apply_display_font(c: Control, text: String) -> void:
	if not _needs_font_fallback(text):
		c.add_theme_font_override("font", font())

## Public wrapper for screens that restyle their own labels.
static func apply_display_font(c: Control, text: String) -> void:
	_apply_display_font(c, text)

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

## Card panel: light parchment nine-patch (rpg-expansion), tinted toward `color`.
static func make_card(color: Color = PANEL) -> StyleBoxTexture:
	return _nine_patch(_PANEL_LIGHT, 22, _compensate(color, _PANEL_BASE), 16, 16, 14, 14)

## Framed panel: deeper parchment with ornate darker rim — offers, lootboxes,
## rarity frames. `tint` multiplies the parchment (keep it light).
static func make_frame(tint: Color = Color(1, 1, 1)) -> StyleBoxTexture:
	return _nine_patch(_PANEL_PARCHMENT, 22, tint, 16, 16, 14, 14)

## Inset well: recessed parchment (empty slots, sunken areas).
static func make_inset(tint: Color = Color(1, 1, 1)) -> StyleBoxTexture:
	return _nine_patch(_PANEL_INSET, 20, tint, 12, 12, 10, 10)

## Dark wood panel (toasts, dramatic headers).
static func make_dark_panel() -> StyleBoxTexture:
	return _nine_patch(_PANEL_DARK, 22, Color(1, 1, 1), 16, 16, 14, 14)

## Progress bar background/fill (rpg-expansion bar pieces, pre-composed).
static func make_bar_bg() -> StyleBoxTexture:
	return _nine_patch(_BAR_BG, 12, Color(1, 1, 1), 4, 4, 2, 2)

static func make_bar_fill(kind: String = "green") -> StyleBoxTexture:
	return _nine_patch(_BAR_FILLS.get(kind, _BAR_FILLS["green"]), 12, Color(1, 1, 1), 4, 4, 2, 2)

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
	# Lone "X"/"✕" close buttons get a real cross icon (Kenney Future's X reads as H).
	if b.text.strip_edges() in ["X", "✕", "x"]:
		b.text = ""
		b.icon = icon_texture("cross", 22)
	else:
		_apply_display_font(b, b.text)
	b.add_theme_font_size_override("font_size", 22)
	b.add_theme_color_override("font_color", Color.WHITE)
	b.add_theme_color_override("font_hover_color", Color.WHITE)
	b.add_theme_color_override("font_pressed_color", Color(1, 1, 1, 0.9))
	b.add_theme_color_override("font_disabled_color", Color(1, 1, 1, 0.6))
	var normal := _nine_patch(_BTN_NORMAL, 24, _compensate(bg, _BTN_BASE), 18, 18, 10, 16)
	var hover := _nine_patch(_BTN_NORMAL, 24, _compensate(bg.lightened(0.1), _BTN_BASE), 18, 18, 10, 16)
	# Pressed: flat (no depth edge) + text nudged down = physically depressed.
	var pressed := _nine_patch(_BTN_PRESSED, 24, _compensate(bg.darkened(0.08), _BTN_BASE), 18, 18, 14, 12)
	var disabled := _nine_patch(_BTN_PRESSED, 24,
		_compensate(bg.lerp(Color(0.62, 0.60, 0.57), 0.72), _BTN_BASE), 18, 18, 12, 12)
	b.add_theme_stylebox_override("normal", normal)
	b.add_theme_stylebox_override("hover", hover)
	b.add_theme_stylebox_override("pressed", pressed)
	b.add_theme_stylebox_override("disabled", disabled)
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	add_press_squish(b)
	return b

## Small icon button (square nine-patch) — close buttons, icon chips.
static func make_icon_button(icon_name: String, bg: Color, size: int = 52) -> Button:
	var b := Button.new()
	b.custom_minimum_size = Vector2(size, size)
	b.add_theme_font_override("font", font())
	b.add_theme_stylebox_override("normal",
		_nine_patch(_BTN_SQ_NORMAL, 20, _compensate(bg, _BTN_BASE), 8, 8, 8, 10))
	b.add_theme_stylebox_override("hover",
		_nine_patch(_BTN_SQ_NORMAL, 20, _compensate(bg.lightened(0.1), _BTN_BASE), 8, 8, 8, 10))
	b.add_theme_stylebox_override("pressed",
		_nine_patch(_BTN_SQ_PRESSED, 20, _compensate(bg.darkened(0.08), _BTN_BASE), 8, 8, 10, 8))
	b.add_theme_stylebox_override("disabled",
		_nine_patch(_BTN_SQ_PRESSED, 20, _compensate(bg.lerp(Color(0.62, 0.6, 0.57), 0.72), _BTN_BASE), 8, 8, 10, 8))
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
	_apply_display_font(l, letter)
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

## Display-font label (headers / numbers that should feel "designed").
static func make_display_label(text: String, size: int, color: Color = INK) -> Label:
	var l := make_label(text, size)
	_apply_display_font(l, text)
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
