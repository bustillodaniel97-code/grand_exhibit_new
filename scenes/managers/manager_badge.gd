extends PanelContainer
## ManagerBadge — one staff ID badge in the managers roster.
##
## The roster used to be fourteen identical rows: a coloured disc with an initial
## in it, a name, "Lv 1" and a department chip. Undiscovered managers all shared
## the same "?" disc, so nine of the fourteen rows were pixel-identical and the
## screen read as a list of placeholders rather than a cast.
##
## A badge answers, in one glance, the five things a collection screen exists to
## show: who this is (a real face, not a letter), what they do (specialty plus the
## post they are best suited to), how rare they are, how far they are levelled,
## and what they are like (traits + bio). It is deliberately a STAFF PASS and not
## a trading card — photo window, rarity stripe down the binding edge, service
## number, small-caps field labels. Cards belong to a different genre and would
## fight the museum fiction.

const UI := preload("res://scripts/ui/ui_kit.gd")
const ManagerPortrait := preload("res://scenes/managers/manager_portrait.gd")
const PortraitBaker := preload("res://scenes/managers/portrait_baker.gd")

signal tapped(manager_id: String)

const PHOTO := PortraitBaker.SIZE       # 112 — photo window edge, design px
## Rarity stripe down the binding edge. Wide enough to survive being minified
## onto a phone, narrow enough to read as an edge stripe rather than a panel.
const SPINE := 9

var _id: String = ""

## Service number printed on the badge. Derived, not stored: it is set dressing,
## and a stored one would be one more field to keep in sync with the roster.
static func service_no(def: Dictionary) -> String:
	return "GX-%d" % (absi(hash(str(def.get("id", "")))) % 9000 + 1000)

# ---------------------------------------------------------------- contrast

## WCAG relative luminance. Written out rather than using Color.get_luminance(),
## which is a straight weighted sum of the sRGB components and scores gold and
## azure as near-equal — the two rarity tints that need OPPOSITE text colours.
static func rel_luminance(c: Color) -> float:
	var out := 0.0
	var weights := [0.2126, 0.7152, 0.0722]
	var channels := [c.r, c.g, c.b]
	for i in 3:
		var v: float = float(channels[i])
		v = v / 12.92 if v <= 0.03928 else pow((v + 0.055) / 1.055, 2.4)
		out += float(weights[i]) * v
	return out

static func contrast(a: Color, b: Color) -> float:
	var la := rel_luminance(a)
	var lb := rel_luminance(b)
	return (maxf(la, lb) + 0.05) / (minf(la, lb) + 0.05)

## Whichever body ink is legible on `bg`. Measured, not guessed: the rarity tints
## run from gold to grey-blue and neither ink wins across all four.
static func ink_on(bg: Color) -> Color:
	return UI.INK if contrast(UI.INK, bg) >= contrast(Color.WHITE, bg) else Color.WHITE

## Legibility floor for text on a solid chip. WCAG AA for body-size type.
const MIN_PILL_CONTRAST := 4.5

## The pill fill, pushed away from its text until the pair clears the floor. The
## epic violet is the case that forces this: white on it lands at 4.04:1 and INK
## is worse, so no choice of ink alone is legible. Deepening the CHIP keeps the
## tier's hue — which is what the player reads it by — and buys the contrast.
## Only the chip moves; the rarity stripe and the photo rim stay the kit colour.
static func legible_fill(tint: Color) -> Color:
	var ink := ink_on(tint)
	var fill := tint
	var toward_dark: bool = ink == Color.WHITE
	for _i in 14:
		if contrast(ink, fill) >= MIN_PILL_CONTRAST:
			break
		fill = fill.darkened(0.055) if toward_dark else fill.lightened(0.055)
	return fill

# ------------------------------------------------------------------ build

## `state` is {"level","rank","cards"}; `owned` false renders the sealed variant.
func setup(id: String, def: Dictionary, state: Dictionary, owned: bool, is_new: bool) -> void:
	_id = id
	var rarity: String = str(def.get("rarity", "common"))
	var tint: Color = UI.RARITY_COLORS.get(rarity, UI.LOCKED)
	var specialty: String = str(def.get("specialty", ""))
	var dept: Color = UI.DEPT_COLORS.get(specialty, UI.LOCKED)
	add_theme_stylebox_override("panel", _badge_box(tint, owned))

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(row)
	var photo := ManagerPortrait.new()
	row.add_child(photo)
	photo.setup(def, PHOTO, owned)

	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	info.add_theme_constant_override("separation", 5)
	info.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(info)

	# Name + rarity. The rarity word rides a pill in its own hue, because at thumb
	# size a coloured word on its own is not a tier, it is a typo.
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 8)
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	info.add_child(head)
	var name_l := UI.make_display_label(
		str(def.get("name", id)) if owned else "Personnel File Sealed",
		UI.TYPE_TITLE, UI.INK if owned else UI.INK.lerp(UI.PANEL, 0.40))
	name_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	head.add_child(name_l)
	head.add_child(pill(rarity.to_upper(), tint))

	# The two job facts on one line: which department, and the post inside it.
	var post := HBoxContainer.new()
	post.add_theme_constant_override("separation", 8)
	post.mouse_filter = Control.MOUSE_FILTER_IGNORE
	info.add_child(post)
	post.add_child(pill(specialty.to_upper(), dept))
	var post_l := UI.make_label(str(def.get("post", "")), UI.TYPE_LABEL)
	post_l.add_theme_color_override("font_color", UI.INK.lerp(UI.PANEL, 0.26))
	post_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	post_l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	post_l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	post.add_child(post_l)

	# Level + rank. The service number leads the row either way, so a sealed badge
	# is still a badge and the card keeps one height across the roster.
	var rank_row := HBoxContainer.new()
	rank_row.add_theme_constant_override("separation", 8)
	rank_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	info.add_child(rank_row)
	rank_row.add_child(_field("NO. %s" % service_no(def)))
	if owned:
		rank_row.add_child(UI.make_display_label(
			"LV %d" % maxi(int(state.get("level", 1)), 1), UI.TYPE_LABEL, UI.INK))
		rank_row.add_child(_pips(int(state.get("rank", 1))))
	var gap := Control.new()
	gap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rank_row.add_child(gap)
	if is_new and owned:
		rank_row.add_child(pill("NEW", UI.ACCENT))

	info.add_child(_traits_row(def, dept, owned))

	var bio := UI.make_label(
		str(def.get("flavor", "")) if owned
		else "Recruit this manager from a lootbox to open their file.",
		UI.TYPE_CAPTION)
	bio.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	bio.add_theme_color_override("font_color", UI.INK.lerp(UI.PANEL, 0.32))
	bio.mouse_filter = Control.MOUSE_FILTER_IGNORE
	info.add_child(bio)

	_add_tap_target()

# ------------------------------------------------------------------ tap

## The whole badge is the target. A PanelContainer with a gui_input handler is
## not: it never changes a pixel when pressed, which is the same silent tap the
## quest chips were just fixed for. This is a real Button laid over the badge
## with empty styleboxes, so the card itself squishes and clicks.
func _add_tap_target() -> void:
	var hit := Button.new()
	hit.flat = true
	hit.focus_mode = Control.FOCUS_NONE
	for state in ["normal", "hover", "pressed", "focus", "disabled"]:
		hit.add_theme_stylebox_override(state, StyleBoxEmpty.new())
	hit.button_down.connect(func() -> void: _squish(Vector2(0.975, 0.955)))
	hit.button_up.connect(func() -> void: _squish(Vector2.ONE))
	hit.pressed.connect(func() -> void:
		UI.play_sfx(self, "tap")
		tapped.emit(_id))
	add_child(hit)
	pivot_offset = size / 2.0
	resized.connect(func() -> void: pivot_offset = size / 2.0)

func _squish(target: Vector2) -> void:
	if not is_inside_tree():
		scale = target
		return
	var tw := create_tween()
	tw.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(self, "scale", target, 0.10)

# ------------------------------------------------------------------ pieces

## Badge card: light stock, rarity stripe punched down the binding edge. The
## stripe is a one-sided border rather than a child panel, so it follows the
## card's corner radius for free and costs no extra draw.
func _badge_box(tint: Color, owned: bool) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = UI.PANEL if owned else UI.PANEL_SOFT.darkened(0.04)
	sb.set_corner_radius_all(UI.RADIUS_CARD)
	sb.content_margin_left = 12 + SPINE
	sb.content_margin_right = 14
	sb.content_margin_top = 12
	sb.content_margin_bottom = 12
	sb.border_width_left = SPINE
	sb.border_color = tint if owned else tint.lerp(UI.LOCKED, 0.55)
	sb.shadow_color = Color(0.06, 0.03, 0.16, 0.22)
	sb.shadow_size = 5
	sb.shadow_offset = Vector2(0, 3)
	return sb

## Small tinted pill (rarity, department, NEW). Public: the detail sheet shows
## the same tags, and a second copy of them would drift.
static func pill(text: String, tint: Color) -> Control:
	var fill := legible_fill(tint)
	var sb := StyleBoxFlat.new()
	sb.bg_color = fill
	sb.set_corner_radius_all(7)
	sb.content_margin_left = 8
	sb.content_margin_right = 8
	sb.content_margin_top = 2
	sb.content_margin_bottom = 3
	var p := PanelContainer.new()
	# Shrink on BOTH axes: a pill dropped into a VBox stretches to the column
	# width by default, which turns a tier tag into a progress bar.
	p.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	p.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_theme_stylebox_override("panel", sb)
	var l := UI.make_display_label(text, UI.TYPE_CAPTION, ink_on(fill))
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_child(l)
	return p

## Small-caps field label — the printed-form voice of the badge.
func _field(text: String) -> Label:
	var l := UI.make_display_label(text, UI.TYPE_CAPTION, UI.INK.lerp(UI.PANEL, 0.44))
	l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l

## Rank stars. Earned pips are brass and filled, spent ones an outline: a dimmed
## fill on cream stock is a 2:1 smudge that reads as a rendering fault.
func _pips(rank: int) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 3)
	row.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for i in 4:
		if i < rank:
			row.add_child(UI.make_icon("star", 17, UI.BRASS))
		else:
			row.add_child(UI.make_icon("star_outline", 17, UI.INK.lerp(UI.PANEL, 0.48)))
	return row

## Trait keywords. Outlined rather than filled: two more saturated pills next to
## the rarity and department pills turned the badge into a bag of sweets.
func _traits_row(def: Dictionary, dept: Color, owned: bool) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var traits: Array = def.get("traits", [])
	if not owned:
		row.add_child(_field("%d TRAITS ON FILE" % traits.size()))
		return row
	for t in traits:
		row.add_child(trait_chip(str(t), dept))
	return row

## Outlined keyword chip. Public: the detail sheet shows the same traits.
static func trait_chip(text: String, dept: Color) -> Control:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(dept, 0.13)
	sb.set_corner_radius_all(7)
	sb.set_border_width_all(2)
	sb.border_color = Color(dept, 0.60)
	sb.content_margin_left = 7
	sb.content_margin_right = 7
	sb.content_margin_top = 1
	sb.content_margin_bottom = 2
	var p := PanelContainer.new()
	p.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	p.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_theme_stylebox_override("panel", sb)
	var l := UI.make_label(text, UI.TYPE_CAPTION)
	l.add_theme_color_override("font_color", dept.darkened(0.48))
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_child(l)
	return p
