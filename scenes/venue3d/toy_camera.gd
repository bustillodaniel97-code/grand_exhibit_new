extends Camera3D
## Diorama camera for the 3D venue: a fixed three-quarter pitch that looks down
## the grid's +Z axis (the building's front toward the player), one-finger or
## mouse drag to pan, pinch or wheel to zoom. Framing is by WIDTH so every phone
## shows the whole building across at the default zoom.

@export var pitch_deg := 44.0
@export var min_dist := 14.0
@export var max_dist := 52.0

var focus := Vector3.ZERO
var dist := 40.0
var bounds := Rect2(-2, -2, 18, 26)  # clamp for `focus` on the XZ plane
## Optional: ground height under a focus z (upper floors). The focus eases to it,
## so panning up the building rises with the floors instead of sinking into them.
var height_at: Callable
var _fly: Tween

var _touches := {}
var _pinch_start := 0.0
var _dist_start := 0.0

func _ready() -> void:
	keep_aspect = Camera3D.KEEP_WIDTH
	fov = 24.0
	near = 1.0
	far = 200.0
	_apply()

## Frame a ground-plane rectangle across the screen width.
func frame(rect: Rect2, margin := 1.5) -> void:
	focus = Vector3(rect.get_center().x, 0.0, rect.get_center().y)
	dist = clampf((rect.size.x * 0.5 + margin) / tan(deg_to_rad(fov * 0.5)), min_dist, max_dist)
	_apply()

func _process(delta: float) -> void:
	if height_at.is_valid():
		var target := float(height_at.call(focus.z))
		if absf(focus.y - target) > 0.001:
			focus.y = lerpf(focus.y, target, minf(1.0, delta * 5.0))
			_apply()

## Glide the focus to a ground point (the floor selector).
func fly_to(point: Vector3, secs := 0.6) -> void:
	if _fly and _fly.is_valid():
		_fly.kill()
	_fly = create_tween()
	_fly.tween_method(func(p: Vector3) -> void:
		focus = p
		_apply(), focus, point, secs).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

func _apply() -> void:
	focus.x = clampf(focus.x, bounds.position.x, bounds.end.x)
	focus.z = clampf(focus.z, bounds.position.y, bounds.end.y)
	var p := deg_to_rad(pitch_deg)
	position = focus + Vector3(0.0, sin(p), cos(p)) * dist
	rotation = Vector3(-p, 0.0, 0.0)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_zoom(0.9)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_zoom(1.1)
	elif event is InputEventMouseMotion and (event.button_mask & MOUSE_BUTTON_MASK_LEFT) and _touches.size() < 2:
		_pan(event.relative)
	elif event is InputEventScreenTouch:
		if event.pressed:
			_touches[event.index] = event.position
		else:
			_touches.erase(event.index)
		if _touches.size() == 2:
			_pinch_start = _pinch_span()
			_dist_start = dist
	elif event is InputEventScreenDrag:
		_touches[event.index] = event.position
		if _touches.size() == 2 and _pinch_start > 0.0:
			dist = clampf(_dist_start * _pinch_start / maxf(_pinch_span(), 1.0), min_dist, max_dist)
			_apply()

func _pinch_span() -> float:
	var pts: Array = _touches.values()
	return (pts[0] as Vector2).distance_to(pts[1] as Vector2)

func _zoom(k: float) -> void:
	dist = clampf(dist * k, min_dist, max_dist)
	_apply()

func _pan(rel: Vector2) -> void:
	# World units per pixel at the focus distance, so the ground tracks the finger.
	var vp_w := float(get_viewport().get_visible_rect().size.x)
	var per_px := 2.0 * dist * tan(deg_to_rad(fov * 0.5)) / maxf(vp_w, 1.0)
	focus.x -= rel.x * per_px
	focus.z -= rel.y * per_px / sin(deg_to_rad(pitch_deg))
	_apply()
