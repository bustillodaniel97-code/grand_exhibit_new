extends RefCounted
## PortraitBaker — head-and-shoulders stills of the procedural cast, for the
## manager ID badges. Static API, no class_name; callers preload this file.
##
## Why this is not CharacterBaker. That baker exists for a different job: six
## walk poses of a WHOLE figure, stored at the size the floor blits them. A badge
## photo is the opposite trade — one pose, cropped to the head and shoulders, at
## several times that magnification. Reusing a walk frame would stretch roughly
## sixty stored texels of face across a 224px window, which is exactly the soft,
## resampled look the bake pipeline was built to avoid. Cropping at bake time
## instead spends the supersample where the player is actually looking.
##
## Two rules are inherited verbatim from CharacterBaker, for the same reasons:
##   · looks are keyed, so the cache stays bounded and reopening the screen is free
##   · a transparent read-back is NEVER cached — it means the render target was
##     not ready, not that the subject is invisible
##
## Bakes are queued and drained through a single shared render target. Fourteen
## badges are built in the same frame, and fourteen simultaneous 672x672 targets
## is ~48MB of transient VRAM on a phone for no gain.
##
## Under --headless there is no rendering context, so request() is a no-op and the
## badge keeps the placeholder it already drew.

## Character-local crop, in design px. Chosen against character.gd's own metrics:
## the tallest hair (style 5's stack, style 4's halo) tops out near y = -50 on the
## largest build, and the shoulders reach x = +/-12.8 including the near arm, so
## this window frames the figure without ever clipping a silhouette.
const CROP := Rect2(-20.0, -54.0, 40.0, 40.0)

## On-screen size of a badge photo, in design px.
const SIZE := 112
## Stored at STORE x the design footprint, so the sprite still has texel density
## to spare when the engine upscales the 720-wide canvas to a 1080p+ phone.
const STORE := 2
const SUPERSAMPLE := 3
const TEX := SIZE * STORE               # 224 — stored texture edge
const RENDER := TEX * SUPERSAMPLE       # 672 — render target edge

static var _cache := {}         # look_key -> ImageTexture
static var _pending := {}       # look_key -> callbacks waiting for the shared bake
static var _queue: Array = []
static var _busy := false

## Baked portrait for a look, or null if it has not been rendered yet.
static func texture_for(look_key: String) -> Texture2D:
	return _cache.get(look_key, null)

static func is_baked(look_key: String) -> bool:
	return _cache.has(look_key)

## Queue a bake if this look has never been rendered. `on_ready` is called with
## the finished Texture2D; it is skipped if the requester died in the meantime.
static func request(look_key: String, look: Dictionary, host: Node,
		on_ready: Callable = Callable()) -> void:
	if look_key == "" or host == null or not host.is_inside_tree():
		return
	if _cache.has(look_key):
		if on_ready.is_valid(): on_ready.call(_cache[look_key])
		return
	if DisplayServer.get_name() == "headless":
		return
	# Rebuilt roster cards still need the result of an already-running bake.
	# Deduplicate rendering, never subscribers; dead controls are skipped below.
	if _pending.has(look_key):
		if on_ready.is_valid(): (_pending[look_key] as Array).append(on_ready)
		return
	_pending[look_key] = [on_ready] if on_ready.is_valid() else []
	_queue.append({"key": look_key, "look": look, "host": host})
	if not _busy:
		_pump()

## Drains the queue through ONE render target and ONE painter. The first version
## built a fresh SubViewport per portrait, which cost three frames each: the
## roster is fourteen badges, so half a second of the screen's life was spent
## showing placeholder initials that had already been asked for.
static func _pump() -> void:
	_busy = true
	var anchor: Node = _live_host()
	if anchor == null:
		_drain_queue()
		_busy = false
		return
	# Let the frame settle first: a SubViewport created before the renderer has
	# drawn anything reads back fully transparent.
	var tree := anchor.get_tree()
	await tree.process_frame

	var vp := SubViewport.new()
	vp.size = Vector2i(RENDER, RENDER)
	vp.transparent_bg = true
	vp.disable_3d = true
	vp.render_target_clear_mode = SubViewport.CLEAR_MODE_ALWAYS
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	tree.root.add_child(vp)

	var painter: Node2D = load("res://scenes/venue/floor/character.gd").new()
	painter.set_painter_mode(true)
	# Pose 0 is the stance the walk cycle starts from: no bob, no swing, no
	# squash. A badge photo of someone mid-stride would look like a mistake.
	painter.bake_pose = 0
	# Front-on framing: the cap peak must not be drawn in walking profile.
	painter.portrait_mode = true
	var k: float = float(RENDER) / CROP.size.x
	painter.scale = Vector2.ONE * k
	painter.position = -CROP.position * k
	vp.add_child(painter)

	while not _queue.is_empty():
		await _bake(_queue.pop_front(), vp, painter)
	vp.queue_free()
	_busy = false

static func _bake(job: Dictionary, vp: SubViewport, painter: Node2D) -> void:
	var key: String = str(job["key"])
	painter.apply_look(job["look"])
	painter.queue_redraw()
	# Two frames: one for the redraw to be submitted, one for it to land in the
	# render target before the texture is read back.
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var callbacks: Array = _pending.get(key, [])
	_pending.erase(key)
	if not is_instance_valid(vp):
		return
	var img: Image = vp.get_texture().get_image()
	if img == null or not img.get_used_rect().has_area():
		return
	img.resize(TEX, TEX, Image.INTERPOLATE_LANCZOS)
	var tex := ImageTexture.create_from_image(img)
	_cache[key] = tex
	for cb: Callable in callbacks:
		if cb.is_valid() and is_instance_valid(cb.get_object()):
			cb.call(tex)

## Any queued requester that is still in the tree can host the render target.
static func _live_host() -> Node:
	for job in _queue:
		var host: Node = job["host"]
		if is_instance_valid(host) and host.is_inside_tree():
			return host
	return null

static func _drain_queue() -> void:
	for job in _queue:
		_pending.erase(str(job["key"]))
	_queue.clear()

## Test/debug hook: drop every baked portrait.
static func clear_cache() -> void:
	_cache.clear()
	_pending.clear()
	_queue.clear()
