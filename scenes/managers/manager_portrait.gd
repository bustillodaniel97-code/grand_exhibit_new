extends Control
## ManagerPortrait — the framed photo window on a manager's staff pass.
##
## Procedural, and not a second art pipeline: the face is the floor's own
## Character painted by PortraitBaker, wearing the department's uniform. A
## manager therefore looks like the staff they would be standing next to
## downstairs, and adding a manager costs a four-integer `look` block in
## managers.json rather than an asset.
##
## The window is drawn before the photo exists and keeps working if it never
## does: backdrop, halo and the name's initial go down immediately, and the baked
## texture is swapped in when it lands. Under --headless there is no rendering
## context to bake with, so the initial is what the suites see.
##
## A SEALED file never asks for a bake at all. It used to: the badge inked the
## finished portrait out to a near-black silhouette, which meant an undiscovered
## manager looked like a dark figure once the bake landed and like a "?" plate
## until it did — two different treatments for one state, decided by a race. The
## sealed plate below is the only thing an unowned manager ever renders.

const UI := preload("res://scripts/ui/ui_kit.gd")
const Character := preload("res://scenes/venue/floor/character.gd")
const PortraitBaker := preload("res://scenes/managers/portrait_baker.gd")

var _slot: Control = null

## The Character look this manager wears: their own face, the department's
## uniform. Indices come from managers.json so each of the fourteen is authored
## rather than rolled; a manager with no `look` block falls back to a hash of its
## id, which is still deterministic and still distinct in practice.
static func look_for(def: Dictionary) -> Dictionary:
	var block: Dictionary = def.get("look", {})
	var fallback: int = absi(hash(str(def.get("id", def.get("name", "")))))
	var uniform: Color = UI.DEPT_COLORS.get(str(def.get("specialty", "")), UI.LOCKED)
	var skin: int = int(block.get("skin", fallback % Character.SKIN_TONES.size()))
	var hair: int = int(block.get("hair", (fallback / 7) % Character.HAIR_COLORS.size()))
	var style: int = int(block.get("hair_style", (fallback / 53) % Character.HAIR_STYLES))
	var build: int = int(block.get("build", (fallback / 311) % Character.BUILDS.size()))
	return {
		"skin": Character.SKIN_TONES[posmod(skin, Character.SKIN_TONES.size())],
		"hair": Character.HAIR_COLORS[posmod(hair, Character.HAIR_COLORS.size())],
		# Department hue on the shirt, darker leg. Mirrors Character.set_uniform so
		# a manager matches the staff they would be standing next to.
		"shirt": uniform,
		"pants": uniform.darkened(0.45),
		"hair_style": posmod(style, Character.HAIR_STYLES),
		"build": Character.BUILDS[posmod(build, Character.BUILDS.size())],
		"is_staff": true,
		"uniform": uniform,
	}

## Portrait cache key. Stable across sessions, so reopening the screen is free.
static func portrait_key(def: Dictionary) -> String:
	return "mgr_%s" % str(def.get("id", def.get("name", "?")))

## `edge` is the window HEIGHT in design px. `fill_width` widens the window to
## whatever the parent gives it — the coverflow pass wants a banner, the lootbox
## reward list wants a square, and the figure is centred either way.
func setup(def: Dictionary, edge: int, owned: bool, fill_width: bool = false) -> void:
	if fill_width:
		custom_minimum_size = Vector2(0, edge)
		size_flags_horizontal = Control.SIZE_EXPAND_FILL
	else:
		custom_minimum_size = Vector2(edge, edge)
	size_flags_vertical = Control.SIZE_SHRINK_CENTER
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var dept: Color = UI.DEPT_COLORS.get(str(def.get("specialty", "")), UI.LOCKED)
	var tint: Color = UI.RARITY_COLORS.get(str(def.get("rarity", "common")), UI.LOCKED)

	var back := Panel.new()
	back.set_anchors_preset(Control.PRESET_FULL_RECT)
	back.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := StyleBoxFlat.new()
	# Deep neutral backdrop with only a wash of the department hue. A backdrop of
	# straight dept.darkened() put the gallery's gold uniform on a gold wall and
	# the archive's azure on an azure one — the figure sank into its own colour.
	sb.bg_color = UI.BG_DEEP.lerp(dept, 0.30) if owned else UI.BG_DEEP.lerp(UI.LOCKED, 0.42)
	sb.set_corner_radius_all(maxi(edge / 8, 8))
	sb.set_border_width_all(3)
	sb.border_color = tint if owned else tint.lerp(UI.LOCKED, 0.55)
	back.add_theme_stylebox_override("panel", sb)
	add_child(back)

	# Studio halo behind the head, so the figure separates from the backdrop
	# instead of sinking into a flat rectangle. Lifted off centre because the crop
	# frames head and chest, so the face sits in the upper half of the window.
	var halo_wrap := CenterContainer.new()
	halo_wrap.set_anchors_preset(Control.PRESET_FULL_RECT)
	halo_wrap.offset_bottom = -edge * 0.16
	halo_wrap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	halo_wrap.add_child(UI.make_icon("disc", int(edge * 0.74),
		Color(dept.lightened(0.35), 0.40) if owned else Color(1, 1, 1, 0.05)))
	add_child(halo_wrap)

	_slot = Control.new()
	_slot.set_anchors_preset(Control.PRESET_FULL_RECT)
	_slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_slot)

	if not owned:
		_seal(edge)
		return

	var initial := UI.make_display_label(
		str(def.get("name", "?")).substr(0, 1), int(edge * 0.42), Color(1, 1, 1, 0.82))
	initial.set_anchors_preset(Control.PRESET_FULL_RECT)
	initial.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	initial.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	initial.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_slot.add_child(initial)

	var key: String = portrait_key(def)
	var baked: Texture2D = PortraitBaker.texture_for(key)
	if baked != null:
		_show(baked)
		return
	# Parent first: PortraitBaker refuses a request from a detached node, because
	# it has no tree to await a frame on.
	var fire := func() -> void:
		PortraitBaker.request(key, look_for(def), self, _show)
	if is_inside_tree():
		fire.call()
	else:
		tree_entered.connect(fire, CONNECT_ONE_SHOT)

## The sealed plate. One treatment, drawn immediately, identical for all twelve
## undiscovered managers: an unread file, not a person in shadow.
func _seal(edge: int) -> void:
	var mark := UI.make_display_label("?", int(edge * 0.46), Color(1, 1, 1, 0.30))
	mark.set_anchors_preset(Control.PRESET_FULL_RECT)
	mark.offset_bottom = -edge * 0.14
	mark.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	mark.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	mark.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_slot.add_child(mark)
	var stamp := UI.make_display_label("SEALED", maxi(int(edge * 0.11), 12),
		Color(1, 1, 1, 0.44))
	stamp.set_anchors_preset(Control.PRESET_FULL_RECT)
	stamp.offset_top = edge * 0.60
	stamp.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	stamp.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	stamp.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_slot.add_child(stamp)

func _show(tex: Texture2D) -> void:
	if tex == null or not is_instance_valid(_slot):
		return
	for c in _slot.get_children():
		_slot.remove_child(c)
		c.queue_free()
	var tr := TextureRect.new()
	tr.texture = tex
	tr.set_anchors_preset(Control.PRESET_FULL_RECT)
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_slot.add_child(tr)
