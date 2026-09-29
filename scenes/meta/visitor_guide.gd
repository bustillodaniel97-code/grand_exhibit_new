extends Control
## Visitor Guide: every kind of visitor, the reputation that brings them, and
## how many have walked in. Each card shows the visitor as a live toy (the same
## chibi and outfit the museum uses). VIPs are marked with their tip.

const UI := preload("res://scripts/ui/ui_kit.gd")
const Chrome := preload("res://scripts/ui/museum_chrome.gd")
const VisitorSystem := preload("res://scripts/meta/visitor_system.gd")
const Npc := preload("res://scenes/venue3d/toy_npc.gd")
const Venue3D := preload("res://scenes/venue3d/venue_3d.gd")

const PORTRAIT := Vector2i(150, 170)

var _tip_label: Label
var _timer: Timer

func setup(_payload: Dictionary) -> void:
	pass

func _ready() -> void:
	name = "VisitorGuide"
	var bg := ColorRect.new()
	bg.color = Chrome.BG
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_%s" % side, 18)
	add_child(margin)
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 10)
	margin.add_child(body)
	body.add_child(UI.make_display_label("Visitor Guide", 30, Chrome.INK))
	body.add_child(_label("Reputation brings new kinds of visitor to every museum. VIPs walk on a gold ring: tap the Tip! bubble over their heads for a bonus.", 15, Chrome.DIM))
	_tip_label = _label("", 16, Chrome.TEAL)
	_tip_label.name = "TipStatus"
	body.add_child(_tip_label)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	body.add_child(scroll)
	var grid := GridContainer.new()
	grid.name = "Cards"
	grid.columns = 2
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 10)
	scroll.add_child(grid)
	var i := 0
	for t in VisitorSystem.types():
		grid.add_child(_card(t, i))
		i += 1

	_timer = Timer.new()
	_timer.wait_time = 1.0
	_timer.autostart = true
	_timer.timeout.connect(_refresh_tip)
	add_child(_timer)
	_refresh_tip()

func _refresh_tip() -> void:
	var line := tr("Tips collected: %d") % VisitorSystem.tips_collected()
	var any_vip := false
	for t in VisitorSystem.unlocked():
		any_vip = any_vip or bool(t.get("vip", false))
	if not any_vip:
		line = tr("VIPs start visiting at reputation %d.") % _first_vip_rep()
	elif VisitorSystem.tip_ready():
		line += tr(" · Next VIP brings a tip")
	else:
		var s := VisitorSystem.seconds_to_tip()
		line += tr(" · Next tip in %d:%02d") % [s / 60, s % 60]
	_tip_label.text = line

func _first_vip_rep() -> int:
	for t in VisitorSystem.types():
		if bool(t.get("vip", false)):
			return int(t.get("rep", 1))
	return 1

func _card(t: Dictionary, index: int) -> Control:
	var id := str(t.get("id", ""))
	var open := VisitorSystem.is_unlocked(id)
	var vip := bool(t.get("vip", false))
	var card := PanelContainer.new()
	card.name = "Visitor_%s" % id
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var sb := Chrome.panel(16, Chrome.RAISED if vip and open else Chrome.PANEL)
	sb.set_content_margin_all(10)
	if vip:
		sb.border_color = Color("#E8B83A")
		sb.set_border_width_all(3)
	card.add_theme_stylebox_override("panel", sb)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 4)
	card.add_child(col)

	var holder := CenterContainer.new()
	col.add_child(holder)
	var portrait := _portrait(t, index)
	if not open:
		portrait.modulate = Color(0.12, 0.09, 0.06, 0.8)  # a silhouette until met
	holder.add_child(portrait)

	var title := UI.make_display_label(str(t.get("name", id)), 19, Chrome.INK)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(title)
	if vip:
		var badge := _label(tr("VIP · tips %ds of income") % int(t.get("tip_seconds", 0)), 13, Chrome.BRASS)
		badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		col.add_child(badge)
	if open:
		col.add_child(_label(str(t.get("desc", "")), 13, Chrome.DIM))
		var seen := _label(tr("Welcomed: %d") % VisitorSystem.met_count(id), 14, Chrome.TEAL)
		seen.name = "Seen"
		col.add_child(seen)
	else:
		var lock := _label(tr("Reach reputation %d") % int(t.get("rep", 1)), 14, Chrome.DANGER)
		lock.name = "Locked"
		lock.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		col.add_child(lock)
	return card

## The visitor as a live toy: its own tiny 3D world, idling on a turntable.
func _portrait(t: Dictionary, index: int) -> Control:
	var box := SubViewportContainer.new()
	box.name = "Portrait"
	box.custom_minimum_size = Vector2(PORTRAIT)
	box.stretch = true
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var vp := SubViewport.new()
	vp.size = PORTRAIT
	vp.own_world_3d = true
	vp.transparent_bg = true
	vp.msaa_3d = Viewport.MSAA_4X
	var low := str(GameState.settings.get("gfx", "auto")) == "low" or bool(GameState.settings.get("gfx_auto_low", false))
	vp.render_target_update_mode = SubViewport.UPDATE_ONCE if low else SubViewport.UPDATE_WHEN_VISIBLE
	box.add_child(vp)

	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_CLEAR_COLOR
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color("#FFF1DC")
	e.ambient_light_energy = 0.55
	e.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	env.environment = e
	vp.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-40, 30, 0)
	sun.light_energy = 1.1
	vp.add_child(sun)
	var cam := Camera3D.new()
	cam.fov = 28.0
	var eye := Vector3(0.0, 0.75, 2.6)
	cam.transform = Transform3D(Basis.looking_at(Vector3(0.0, 0.52, 0.0) - eye), eye)
	vp.add_child(cam)

	var turntable := Node3D.new()
	turntable.rotation.y = -0.35
	vp.add_child(turntable)
	var n := Npc.new()
	turntable.add_child(n)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7919 * (index + 3)
	var look := {"skin": Venue3D.SKIN[rng.randi() % Venue3D.SKIN.size()],
		"hair": Venue3D.HAIR[rng.randi() % Venue3D.HAIR.size()],
		"shirt": Venue3D.SHIRT[rng.randi() % Venue3D.SHIRT.size()],
		"pants": Venue3D.PANTS[rng.randi() % Venue3D.PANTS.size()],
		"shoe": Venue3D.SHOE[rng.randi() % Venue3D.SHOE.size()], "acc": []}
	if str(t.get("id", "")) == "local":
		look["acc"] = ["acc_bag"]
	n.setup(VisitorSystem.dress(look, t, rng))
	return box

func _label(text: String, size_px: int, color: Color) -> Label:
	var l := UI.make_label(text, size_px)
	l.add_theme_color_override("font_color", color)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return l
