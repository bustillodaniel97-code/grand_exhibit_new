extends RefCounted
## CharacterBaker — renders the procedural cast once into supersampled textures
## and hands back ready-to-blit frames.
##
## Why this exists. Drawing the cast live cost ~18 canvas commands per figure and
## still looked aliased: `draw_colored_polygon` has no edge smoothing, and the
## antialiased stroke flag both broke canvas batching and only smoothed outlines,
## not fills. Baking solves both ends at once:
##
##   · quality — each frame is rasterised at SUPERSAMPLE x size and box-filtered
##     back down, which is true supersampled AA on every edge, fill and stroke,
##     and strictly better than anything the 2D renderer offers on GLES3
##   · cost — a baked character is ONE textured quad per frame instead of ~18
##     commands, so the art budget per figure stopped mattering and the shading
##     could get much richer for free
##
## Looks are quantised to a bounded palette (see Character.LOOK_COUNT) so the
## atlas can't grow without limit: memory is LOOK_COUNT x FRAMES x sprite size.
##
## Baking needs a live rendering context. Under `--headless` (the test suites)
## `bake_async` returns an empty array and Character falls back to drawing
## primitives directly, so nothing here is load-bearing for correctness.

const SUPERSAMPLE := 4          # bake at 4x, then filter down
## Stored at STORE x the design footprint so the sprite still has texel density
## to spare when the engine upscales the 720-wide canvas to a 1080p+ phone.
const STORE := 2
const DESIGN := Vector2(48, 64)     # design-space footprint of one figure
const SPRITE := Vector2i(96, 128)   # DESIGN * STORE — stored texture size
const ANCHOR := Vector2(48, 112)    # feet position, in stored-sprite space
const FRAMES := 6                   # walk-cycle poses; frame 0 doubles as idle

static var _cache := {}         # look_key -> Array[Texture2D]
static var _pending := {}       # look_key -> true while a bake is in flight

## Cached frames for a look, or [] if it has not been baked yet.
static func frames_for(look_key: String) -> Array:
	return _cache.get(look_key, [])

static func is_baked(look_key: String) -> bool:
	return _cache.has(look_key)

## Kick off a bake if this look has never been rendered. Safe to call every time
## a character spawns; concurrent callers for the same look collapse into one.
static func request(look_key: String, look: Dictionary, host: Node) -> void:
	if _cache.has(look_key) or _pending.has(look_key):
		return
	if host == null or not host.is_inside_tree():
		return
	if DisplayServer.get_name() == "headless":
		return
	_pending[look_key] = true
	_bake_async(look_key, look, host)

## True once a look has been attempted and produced nothing usable, so callers
## can tell "not baked yet" from "bake is impossible here" if they ever need to.
static func _is_blank(img: Image) -> bool:
	return img == null or not img.get_used_rect().has_area()


static func _bake_async(look_key: String, look: Dictionary, host: Node) -> void:
	var CharacterScript: GDScript = load("res://scenes/venue/floor/character.gd")
	# Let the frame settle first. The staff looks are all requested from
	# VenueFloor._ready(), before the renderer has drawn anything, and a
	# SubViewport created that early read back fully transparent.
	await host.get_tree().process_frame
	var vp := SubViewport.new()
	vp.size = Vector2i(SPRITE.x * SUPERSAMPLE, SPRITE.y * SUPERSAMPLE)
	vp.transparent_bg = true
	vp.disable_3d = true
	vp.render_target_clear_mode = SubViewport.CLEAR_MODE_ALWAYS
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	host.get_tree().root.add_child(vp)

	var painter: Node2D = CharacterScript.new()
	painter.set_painter_mode(true)
	painter.apply_look(look)
	painter.position = ANCHOR * float(SUPERSAMPLE)
	# STORE * SUPERSAMPLE: the painter draws at design scale, so it must be
	# blown up by both the storage multiplier and the supersample factor.
	painter.scale = Vector2.ONE * float(SUPERSAMPLE * STORE)
	vp.add_child(painter)

	var out: Array = []
	for f in FRAMES:
		painter.bake_pose = f
		painter.queue_redraw()
		# Two frames: one for the redraw to be submitted, one for it to land in
		# the render target before the texture is read back.
		await RenderingServer.frame_post_draw
		await RenderingServer.frame_post_draw
		var img: Image = vp.get_texture().get_image()
		# Never cache a blank frame. A transparent read-back means the render
		# target was not ready, not that the character is invisible — caching it
		# would leave that look permanently missing from the floor with no retry,
		# which is exactly how three of the four staff uniforms went invisible.
		if _is_blank(img):
			break
		img.resize(SPRITE.x, SPRITE.y, Image.INTERPOLATE_LANCZOS)
		# Mipmaps matter here specifically because the sprite is MINIFIED on the
		# way out: a 96x128 texture is blitted into a 48x64 design rect, and
		# without a mip chain that 2x reduction point-samples every other texel.
		# On a walking figure that is exactly the crawling, pixelated edge the
		# owner reported — it is a sampling artefact, not the art.
		img.generate_mipmaps()
		out.append(ImageTexture.create_from_image(img))

	vp.queue_free()
	_pending.erase(look_key)
	if out.size() == FRAMES:
		_cache[look_key] = out

## Test/debug hook: drop every baked texture.
static func clear_cache() -> void:
	_cache.clear()
	_pending.clear()
