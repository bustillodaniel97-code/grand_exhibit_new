extends Control
## Authored Blender busts share the approved floor cast faces.
## A sealed file never requests or reveals a portrait texture.

const UI := preload("res://scripts/ui/ui_kit.gd")
const Character := preload("res://scenes/venue/floor/character.gd")
const Chrome := preload("res://scripts/ui/museum_chrome.gd")
const PORTRAIT_ROOT := "res://art/manager_portraits/"
static var _textures: Dictionary = {}
const BACKGROUND_ROOT := "res://art/manager_backgrounds/"
const DEPARTMENTS := ["ticket", "archive", "promotions", "gallery"]
static var _backgrounds: Dictionary = {}

static func background_for(def: Dictionary) -> Texture2D:
	var dept := str(def.get("specialty", ""))
	if dept not in DEPARTMENTS: return null
	if _backgrounds.has(dept): return _backgrounds[dept]
	var path := BACKGROUND_ROOT + dept + ".png"
	if not ResourceLoader.exists(path): return null
	var texture := load(path) as Texture2D
	if texture != null: _backgrounds[dept] = texture
	return texture

static func texture_for(def: Dictionary) -> Texture2D:
	var id := str(def.get("id", ""))
	if _textures.has(id): return _textures[id]
	if id.is_empty() or id.get_file() != id: return null
	var path := PORTRAIT_ROOT + id + ".png"
	if not ResourceLoader.exists(path): return null
	var texture := load(path) as Texture2D
	if texture != null: _textures[id] = texture
	return texture

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
	var dept := Color(str(def.get("color", "#5B7B8C")))
	var tint: Color = UI.RARITY_COLORS.get(str(def.get("rarity", "common")), UI.LOCKED)

	var back := Panel.new()
	back.set_anchors_preset(Control.PRESET_FULL_RECT)
	back.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := StyleBoxFlat.new()
	# Deep neutral backdrop with only a wash of the department hue. A backdrop of
	# straight dept.darkened() put the gallery's gold uniform on a gold wall and
	# the archive's azure on an azure one — the figure sank into its own colour.
	sb.bg_color = Color("d8ddd4").lerp(dept, 0.12) if owned else Chrome.BG
	sb.set_corner_radius_all(14)
	sb.set_border_width_all(1)
	sb.border_color = Chrome.BRASS if owned else Chrome.BORDER
	back.add_theme_stylebox_override("panel", sb)
	add_child(back)

	# The photographed room sits behind the unchanged character, with a quiet
	# face area and architectural detail at the edges. Four shared backgrounds
	# keep the collection lightweight; sealed files never load one.
	back.clip_children = CanvasItem.CLIP_CHILDREN_AND_DRAW
	if owned:
		var background := background_for(def)
		if background != null:
			var room := TextureRect.new()
			room.name = "ManagerBackground_" + str(def.get("specialty", ""))
			room.texture = background
			room.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
			room.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			room.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
			room.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
			room.offset_left = 1; room.offset_top = 1
			room.offset_right = -1; room.offset_bottom = -1
			room.mouse_filter = Control.MOUSE_FILTER_IGNORE
			back.add_child(room)

	_slot = Control.new()
	_slot.set_anchors_preset(Control.PRESET_FULL_RECT)
	_slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_slot.clip_contents = true
	back.add_child(_slot)

	if not owned:
		_seal(edge)
		return

	var texture := texture_for(def)
	if texture != null:
		_show(texture)
		return
	# Unknown future managers retain a readable fallback, never a blank card.
	var initial := UI.make_display_label(str(def.get("name", "?")).substr(0, 1),
		int(edge * 0.42), Chrome.BG)
	initial.set_anchors_preset(Control.PRESET_FULL_RECT)
	initial.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	initial.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	initial.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_slot.add_child(initial)

## The sealed plate. One treatment, drawn immediately, identical for all
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
	tr.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	tr.set_anchors_preset(Control.PRESET_FULL_RECT)
	# Keep hair above the frame edge and enough chest visible for tailored lapels.
	tr.offset_top = custom_minimum_size.y * 0.02
	tr.offset_bottom = custom_minimum_size.y * 0.10
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_slot.add_child(tr)
