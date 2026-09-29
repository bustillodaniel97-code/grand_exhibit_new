extends RefCounted
## Juice — reward feedback shared by every screen. No class_name.
##
## coin_burst(): a spray of coins (or gems) leaps from where the player tapped
## and arcs into the HUD counter, which bounces as they land. It is the single
## most recognisable reward beat in Idle Bank Tycoon, and it tells the player
## WHERE the money went, not just that the number changed.

const UI := preload("res://scripts/ui/ui_kit.gd")

## `from` is a global canvas position. kind: "cash" or "gems".
static func coin_burst(from: Vector2, kind := "cash", count := 9) -> void:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null or tree.root == null:
		return
	var target := tree.root.find_child("HudGems" if kind == "gems" else "HudCash", true, false) as Control
	var layer := CanvasLayer.new()
	layer.layer = 40
	tree.root.add_child(layer)
	var dest := target.get_global_rect().get_center() if target != null else Vector2(360, 40)
	var tex := UI.icon_texture("gems" if kind == "gems" else "cash", 28)
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var last: Tween = null
	for i in count:
		var c := TextureRect.new()
		c.texture = tex
		c.size = Vector2(28, 28)
		c.pivot_offset = Vector2(14, 14)
		c.position = from - Vector2(14, 14)
		c.mouse_filter = Control.MOUSE_FILTER_IGNORE
		layer.add_child(c)
		var spray := from + Vector2(rng.randf_range(-70, 70), rng.randf_range(-90, -20))
		var tw := c.create_tween()
		tw.tween_property(c, "position", spray - Vector2(14, 14), 0.22).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tw.tween_interval(0.04 * i)
		tw.tween_property(c, "position", dest - Vector2(14, 14), 0.45).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
		tw.parallel().tween_property(c, "scale", Vector2.ONE * 0.6, 0.45)
		tw.tween_callback(c.queue_free)
		if target != null:
			tw.tween_callback(func() -> void: _bounce(target))
		last = tw
	if last != null:
		last.finished.connect(layer.queue_free)
	else:
		layer.queue_free()

static func _bounce(c: Control) -> void:
	if not is_instance_valid(c):
		return
	c.pivot_offset = c.size * 0.5
	var tw := c.create_tween()
	tw.tween_property(c, "scale", Vector2.ONE * 1.08, 0.06)
	tw.tween_property(c, "scale", Vector2.ONE, 0.12)
