extends RefCounted
## store_art.gd — procedural shopfront art and badges. All drawn in GDScript via
## the CanvasItem `draw` signal; no image files, nothing downloaded, nothing baked.
##
## Why this exists: v1's product identity was a 26px monochrome icon plus one line
## of text, so "Pouch of Gems" at $0.99 and "Vault of Gems" at $19.99 were visually
## identical and every buy button was the same orange pill. A store where the tiers
## look the same sells the cheapest tier. Each factory here scales its drawing with
## the tier index, so the ladder is legible before a single word is read.
##
## Kept out of scripts/ui/ui_kit.gd deliberately: the kit is shared with tracks
## editing it concurrently, and none of this is general-purpose UI.

const UI := preload("res://scripts/ui/ui_kit.gd")

## Tier ramp for gem piles: gem count, pile spread, facet brightness.
const _TIER_GEMS: Array[int] = [3, 5, 8, 12, 17, 24]

# ------------------------------------------------------------------ product art

## Product art tile. `tier` is 0-based within its ladder; higher tiers get more
## stuff and more shine, which is the whole point of a ladder.
static func make_product_art(def: Dictionary, box: int = 72, tier: int = 0) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(box, box)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	c.draw.connect(_paint_product.bind(c, str(def.get("kind", "")), box, tier))
	return c

static func _paint_product(c: CanvasItem, kind: String, box: int, tier: int) -> void:
	var r := Rect2(Vector2.ZERO, Vector2(box, box))
	match kind:
		"gems":
			_draw_gem_pile(c, r, tier)
		"cash_pack":
			_draw_cash_stack(c, r, tier)
		"insight_pack":
			_draw_insight_burst(c, r, tier)
		"utility":
			_draw_shield(c, r)
		_:
			_draw_crate(c, r, tier)

static func _draw_gem_pile(c: CanvasItem, r: Rect2, tier: int) -> void:
	var n: int = _TIER_GEMS[clampi(tier, 0, _TIER_GEMS.size() - 1)]
	var rng := RandomNumberGenerator.new()
	rng.seed = 1000 + tier  # stable across redraws: the pile must not shimmer
	var base: float = r.size.y * (0.20 - 0.012 * float(mini(tier, 5)))
	var cx: float = r.size.x * 0.5
	var floor_y: float = r.size.y * 0.80
	# Soft shadow puddle grounds the pile so it does not float on the card.
	c.draw_circle(Vector2(cx, floor_y + base * 0.35), base * (1.4 + 0.24 * tier),
		Color(UI.INK.r, UI.INK.g, UI.INK.b, 0.10))
	var placed: Array[Vector2] = []
	for i in range(n):
		var row: int = int(sqrt(float(i)))
		var spread: float = base * (1.1 + 0.42 * float(tier))
		var px: float = cx + rng.randf_range(-spread, spread)
		var py: float = floor_y - float(row) * base * 0.62 + rng.randf_range(-base * 0.2, base * 0.2)
		placed.append(Vector2(px, py))
	placed.sort_custom(func(a: Vector2, b: Vector2) -> bool: return a.y < b.y)
	for p in placed:
		_draw_gem(c, p, base * rng.randf_range(0.72, 1.0))

static func _draw_gem(c: CanvasItem, at: Vector2, rad: float) -> void:
	var body := PackedVector2Array([
		at + Vector2(0, -rad),
		at + Vector2(rad * 0.66, -rad * 0.18),
		at + Vector2(0, rad),
		at + Vector2(-rad * 0.66, -rad * 0.18),
	])
	c.draw_colored_polygon(body, UI.SLATE)
	# One lit facet and one dark facet: enough to read as faceted at thumb size.
	c.draw_colored_polygon(PackedVector2Array([
		at + Vector2(0, -rad),
		at + Vector2(rad * 0.66, -rad * 0.18),
		at + Vector2(0, -rad * 0.05),
	]), UI.SLATE.lightened(0.42))
	c.draw_colored_polygon(PackedVector2Array([
		at + Vector2(0, -rad * 0.05),
		at + Vector2(rad * 0.66, -rad * 0.18),
		at + Vector2(0, rad),
	]), UI.SLATE.darkened(0.22))
	c.draw_polyline(body + PackedVector2Array([at + Vector2(0, -rad)]),
		UI.INK.lerp(UI.SLATE, 0.35), 1.5, true)

static func _draw_cash_stack(c: CanvasItem, r: Rect2, tier: int) -> void:
	var layers: int = 3 + tier * 2
	var w: float = r.size.x * 0.62
	var h: float = r.size.y * 0.13
	var x: float = (r.size.x - w) * 0.5
	var y: float = r.size.y * 0.78
	var step: float = maxf(h * 0.42, (r.size.y * 0.5) / float(layers))
	for i in range(layers):
		var top: float = y - float(i) * step
		var band := Rect2(x + sin(float(i) * 1.7) * 2.0, top - h, w, h)
		c.draw_rect(band, UI.SAGE.darkened(0.06 * float(i % 3)), true)
		c.draw_rect(band, UI.INK.lerp(UI.SAGE, 0.4), false, 1.5)
	var coin_c := Vector2(r.size.x * 0.72, r.size.y * 0.30)
	c.draw_circle(coin_c, r.size.x * 0.13, UI.BRASS)
	c.draw_arc(coin_c, r.size.x * 0.13, 0.0, TAU, 24, UI.BRASS.darkened(0.35), 2.0)

static func _draw_insight_burst(c: CanvasItem, r: Rect2, tier: int) -> void:
	var mid := r.size * 0.5
	var outer: float = r.size.x * (0.26 + 0.03 * float(mini(tier, 4)))
	var rays: int = 8 + tier * 2
	for i in range(rays):
		var a: float = TAU * float(i) / float(rays)
		var len_mul: float = 1.0 if i % 2 == 0 else 0.62
		c.draw_line(mid + Vector2(cos(a), sin(a)) * outer * 0.9,
			mid + Vector2(cos(a), sin(a)) * outer * (1.55 * len_mul),
			UI.PLUM.lightened(0.2), 2.0, true)
	_draw_star(c, mid, outer, UI.PLUM)
	c.draw_circle(mid, outer * 0.30, UI.PANEL)

static func _draw_star(c: CanvasItem, mid: Vector2, rad: float, col: Color) -> void:
	var pts := PackedVector2Array()
	for i in range(10):
		var a: float = -PI * 0.5 + TAU * float(i) / 10.0
		var rr: float = rad if i % 2 == 0 else rad * 0.45
		pts.append(mid + Vector2(cos(a), sin(a)) * rr)
	c.draw_colored_polygon(pts, col)
	c.draw_polyline(pts + PackedVector2Array([pts[0]]), col.darkened(0.35), 1.5, true)

static func _draw_crate(c: CanvasItem, r: Rect2, tier: int) -> void:
	var w: float = r.size.x * 0.68
	var h: float = r.size.y * 0.50
	var box := Rect2((r.size.x - w) * 0.5, r.size.y * 0.40, w, h)
	c.draw_circle(Vector2(r.size.x * 0.5, box.end.y + 3.0), w * 0.5,
		Color(UI.INK.r, UI.INK.g, UI.INK.b, 0.10))
	c.draw_rect(box, UI.BRASS.darkened(0.10), true)
	c.draw_rect(Rect2(box.position, Vector2(box.size.x, box.size.y * 0.28)), UI.BRASS, true)
	c.draw_rect(box, UI.INK.lerp(UI.BRASS, 0.35), false, 2.0)
	# Ribbon: the universal "this is a bundle" cue.
	var band_w: float = w * 0.16
	c.draw_rect(Rect2(box.position.x + (w - band_w) * 0.5, box.position.y, band_w, box.size.y),
		UI.ACCENT, true)
	var bow := Vector2(box.position.x + w * 0.5, box.position.y)
	c.draw_colored_polygon(PackedVector2Array([
		bow, bow + Vector2(-w * 0.26, -h * 0.24), bow + Vector2(-w * 0.06, -h * 0.04)]), UI.ACCENT)
	c.draw_colored_polygon(PackedVector2Array([
		bow, bow + Vector2(w * 0.26, -h * 0.24), bow + Vector2(w * 0.06, -h * 0.04)]), UI.ACCENT)
	for i in range(mini(tier, 3)):
		_draw_gem(c, Vector2(box.position.x + w * (0.18 + 0.30 * float(i)), box.position.y - h * 0.16),
			r.size.y * 0.09)

static func _draw_shield(c: CanvasItem, r: Rect2) -> void:
	var mid := Vector2(r.size.x * 0.5, r.size.y * 0.46)
	var w: float = r.size.x * 0.34
	var h: float = r.size.y * 0.38
	var pts := PackedVector2Array([
		mid + Vector2(-w, -h), mid + Vector2(w, -h), mid + Vector2(w, h * 0.28),
		mid + Vector2(0, h * 1.25), mid + Vector2(-w, h * 0.28)])
	c.draw_colored_polygon(pts, UI.SAGE)
	c.draw_polyline(pts + PackedVector2Array([pts[0]]), UI.SAGE.darkened(0.35), 2.0, true)
	# Struck-through play triangle: "no ad plays here".
	var tri := PackedVector2Array([
		mid + Vector2(-w * 0.30, -h * 0.38), mid + Vector2(-w * 0.30, h * 0.38),
		mid + Vector2(w * 0.42, 0)])
	c.draw_colored_polygon(tri, UI.PANEL)
	c.draw_line(mid + Vector2(-w * 0.72, h * 0.62), mid + Vector2(w * 0.72, -h * 0.62),
		UI.DANGER, 4.0, true)

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
	var l := UI.make_display_label(text, UI.TYPE_CAPTION, Color.WHITE)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.30))
	l.add_theme_constant_override("outline_size", 2)
	p.add_child(l)
	return p

## Anchor price with a rule through it. The basis for the anchor is always printed
## next to it by the caller ("bought separately") — a struck-out number with no
## stated basis is the exact pattern store reviews call misleading.
static func make_strikethrough(text: String, size: int = UI.TYPE_LABEL) -> Label:
	var l := UI.make_label(text, size)
	l.add_theme_color_override("font_color", UI.SLATE.darkened(0.15))
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
