extends RefCounted
## Original Blender-rendered museum product miniatures. Every category has a
## distinct physical silhouette; catalog tier identities select authored art.
## Texture resources are cached, never generated during a draw or purchase.
const UI := preload("res://scripts/ui/ui_kit.gd")
const ART_ROOT := "res://art/store/"
static var _textures: Dictionary = {}
const PRODUCT_ART := {
	"gems_pouch":"gems_0", "gems_sack":"gems_1", "gems_crate":"gems_2",
	"gems_vault":"gems_3", "gems_hoard":"gems_4", "gems_empire":"gems_5",
	"first_buy_bonus":"gems_1", "daily_gem_trove":"gems_2",
	"cash_hour":"cash_0", "cash_quarter":"cash_1", "cash_day":"cash_2",
	"daily_cash_boost":"cash_1",
	"insight_scholar":"insight_0", "insight_curator":"insight_1", "insight_sage":"insight_2",
	"daily_insight_drop":"insight_0", "daily_insight_cache":"insight_1",
	"starter_bundle":"bundle_0", "daily_gem_snack":"bundle_0", "daily_cash_surge":"bundle_1",
	"daily_director_combo":"bundle_1", "venue3_bundle":"bundle_1", "venue4_bundle":"bundle_2",
	"venue5_bundle":"bundle_2", "venue6_bundle":"bundle_2", "veteran_director_pack":"bundle_2",
	"inspection_prep_bundle":"bundle_1", "no_ads":"pass",
	"reward_income_x2":"boost", "reward_instant_cash":"cash_0", "reward_free_gems":"gems_0",
}

static func product_key(def: Dictionary, tier: int = 0) -> String:
	var id := str(def.get("id", ""))
	if PRODUCT_ART.has(id):return PRODUCT_ART[id]
	match str(def.get("kind", "")):
		"gems":return "gems_%d" % clampi(tier,0,5)
		"cash_pack":return "cash_%d" % clampi(tier,0,2)
		"insight_pack":return "insight_%d" % clampi(tier,0,2)
		"utility":return "pass"
	return "bundle_%d" % clampi(tier,0,2)

static func make_product_art(def: Dictionary, box: int = 144, tier: int = 0) -> Control:
	var key := product_key(def,tier)
	if not _textures.has(key):_textures[key] = load(ART_ROOT+key+".png")
	var picture := TextureRect.new()
	picture.name = "ProductArt_"+key
	picture.custom_minimum_size = Vector2(box,box)
	picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	picture.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	picture.texture = _textures[key]
	picture.mouse_filter = Control.MOUSE_FILTER_IGNORE
	picture.set_meta("store_art_asset",key)
	return picture

static func foreground_for(background: Color) -> Color:
	# Relative luminance must be measured in linear light, not encoded sRGB.
	var dark := Color("14232d")
	var light := Color("f5f1e8")
	var luminance := background.srgb_to_linear().get_luminance()
	var dark_ratio := (luminance + .05) / (dark.srgb_to_linear().get_luminance() + .05)
	var light_ratio := (light.srgb_to_linear().get_luminance() + .05) / (luminance + .05)
	return dark if dark_ratio > light_ratio else light

# ---------------------------------------------------------------------- badges

## Corner ribbon ("BEST VALUE", "+73% MORE PER $", "SAVE 56%"). Deliberately not
## rotated: rotated text at 13px on a phone is where legibility goes to die.
static func make_ribbon(text: String, color: Color) -> PanelContainer:
	var p := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = color
	sb.set_corner_radius_all(6)
	sb.corner_radius_top_left = 2
	sb.content_margin_left = 9
	sb.content_margin_right = 9
	sb.content_margin_top = 3
	sb.content_margin_bottom = 4
	sb.shadow_color = Color(0.06, 0.03, 0.16, 0.25)
	sb.shadow_size = 3
	sb.shadow_offset = Vector2(0, 2)
	p.add_theme_stylebox_override("panel", sb)
	p.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var foreground := foreground_for(color)
	var l := UI.make_display_label(text, UI.TYPE_CAPTION, foreground)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.30))
	l.add_theme_constant_override("outline_size", 0)
	p.add_child(l)
	return p

## Anchor price with a rule through it. The basis for the anchor is always printed
## next to it by the caller ("bought separately") — a struck-out number with no
## stated basis is the exact pattern store reviews call misleading.
static func make_strikethrough(text: String, size: int = UI.TYPE_LABEL) -> Label:
	var l := UI.make_label(text, size)
	l.add_theme_color_override("font_color", Color("c1cece"))
	l.draw.connect(func() -> void:
		var y: float = l.size.y * 0.56
		l.draw_line(Vector2(0, y), Vector2(l.size.x, y), UI.DANGER, 2.0, true))
	return l

## Small pill used for countdowns and cap counters.
static func make_pill(text: String, color: Color, icon_name: String = "") -> PanelContainer:
	var p := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = color
	sb.set_corner_radius_all(12)
	sb.content_margin_left = 10
	sb.content_margin_right = 10
	sb.content_margin_top = 3
	sb.content_margin_bottom = 4
	p.add_theme_stylebox_override("panel", sb)
	p.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	p.add_child(row)
	if icon_name != "":
		row.add_child(UI.make_icon(icon_name, 16, Color.WHITE))
	var l := UI.make_display_label(text, UI.TYPE_CAPTION, Color.WHITE)
	l.name = "PillLabel"
	row.add_child(l)
	p.set_meta("pill_label", l)
	return p

static func set_pill_text(pill: Control, text: String) -> void:
	var l: Label = pill.get_meta("pill_label", null) as Label
	if l != null:
		l.text = text

## The big green rewarded-video chip used on the world dock and in the store.
## Height floor is UI.TOUCH_MIN * 4 / 3 — comfortably past the 48dp minimum,
## because this is the most-tapped control in the game.
static func make_boost_button(label: String, color: Color) -> Button:
	var b := UI.make_button(label, color)
	b.custom_minimum_size = Vector2(0, 64)
	b.add_theme_font_size_override("font_size", UI.TYPE_TITLE)
	b.clip_text = true
	return b
