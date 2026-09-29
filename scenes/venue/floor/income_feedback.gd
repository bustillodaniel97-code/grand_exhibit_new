extends Node2D
## A counter receipt glint for routine service; an amount for deliberate collection.
## Visual-only: the caller owns the payment and the world/storey anchor.
const UI := preload("res://scripts/ui/ui_kit.gd")
var amount := ""
var automatic := false
var progress := 0.0
var drift := 0.0
var animation: Tween

func _ready() -> void:
	animation=create_tween()
	animation.tween_method(set_progress,0.0,1.0,.7 if automatic else 1.35)
	animation.tween_callback(queue_free)

func set_progress(value: float) -> void:
	progress=clampf(value,0,1)
	queue_redraw()

func _draw() -> void:
	var opacity:=minf(progress/.12,1.0)*(1.0-smoothstep(.65,1.0,progress))
	if automatic:
		var center:=Vector2(0,-2*progress)
		draw_circle(center,4.5,Color(.12,.25,.23,opacity*.9))
		draw_arc(center,4.5,0,TAU,24,Color(.9,.78,.48,opacity),.8,true)
		draw_polyline(PackedVector2Array([center+Vector2(-2,0),center+Vector2(-.5,1.5),center+Vector2(2,-1.5)]),Color(.93,.86,.67,opacity),1,true)
		return
	var font:=UI.font()
	# World zoom enlarges CanvasItem text after font rasterization. Rasterize at
	# 3x and draw down so the amount stays sharp in the closest museum view.
	var width:=font.get_string_size(amount,HORIZONTAL_ALIGNMENT_LEFT,-1,33).x/3.0+25
	var origin:=Vector2(-width*.5+drift*.2*progress,-12*progress)
	var box:=StyleBoxFlat.new()
	box.bg_color=Color(.08,.18,.19,opacity*.96)
	box.border_color=Color(.72,.68,.48,opacity*.8)
	box.set_border_width_all(1)
	box.set_corner_radius_all(5)
	box.draw(get_canvas_item(),Rect2(origin,Vector2(width,19)))
	var coin:=origin+Vector2(9,9.5)
	draw_circle(coin,3.2,Color(.9,.73,.35,opacity))
	draw_line(coin+Vector2(0,-1.5),coin+Vector2(0,1.5),Color(.42,.3,.1,opacity),1,true)
	draw_set_transform(origin+Vector2(17,13.5),0,Vector2.ONE/3.0)
	draw_string(font,Vector2.ZERO,amount,HORIZONTAL_ALIGNMENT_LEFT,-1,33,Color(.92,.94,.86,opacity))
	draw_set_transform(Vector2.ZERO)
