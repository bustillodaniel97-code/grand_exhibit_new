extends SceneTree
## Draw-call attribution for the living floor: samples the frame with the whole
## floor visible, with only the static diorama visible, and with the floor hidden.
var _vp: SubViewport
var _t := 0.0
var _phase := 0
var _floor: Node = null
func _initialize() -> void:
	_vp = SubViewport.new()
	_vp.size = Vector2i(720, 1280)
	_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(_vp)
	_vp.add_child((load("res://scenes/main.tscn") as PackedScene).instantiate())
	call_deferred("_seed")
func _seed() -> void:
	var gs: Node = root.get_node_or_null("GameState")
	if gs == null: return
	gs.add_cash(load("res://scripts/core/big_number.gd").from_float(1e12))
	for dept in ["ticket", "archive", "promotions", "gallery"]:
		for track in ["staff", "speed", "value"]:
			gs.set_dept_level(gs.current_venue, dept, track, 12)
func _find(n: Node, want: String) -> Node:
	if n.name == want: return n
	for c in n.get_children():
		var r := _find(c, want)
		if r != null: return r
	return null
func _dc() -> int:
	return int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
func _process(delta: float) -> bool:
	_t += delta
	if _t < 8.0: return false
	if _floor == null:
		_floor = _find(_vp, "VenueFloor")
		if _floor == null:
			print("floor not found"); quit(1); return true
	match _phase:
		0:
			print("full floor           draw_calls=%d  process=%.2f ms" % [_dc(),
				Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0])
			for c in (_floor.get_node("../")).get_children(): pass
			var canvas: Node = _floor.get_child(0)
			for c in canvas.get_children():
				if c.name in ["Statics", "Stacks", "VaultPile", "Labels"]: continue
				(c as CanvasItem).visible = false
			_phase = 1; _t = 6.0
		1:
			print("statics only (cast off) draw_calls=%d  process=%.2f ms" % [_dc(), Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0])
			(_floor.get_child(0).get_node("Statics") as CanvasItem).visible = false
			_phase = 2; _t = 6.0
		2:
			print("statics off too      draw_calls=%d  process=%.2f ms" % [_dc(), Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0])
			(_floor as CanvasItem).visible = false
			_phase = 3; _t = 6.0
		3:
			print("floor fully hidden   draw_calls=%d  process=%.2f ms" % [_dc(), Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0])
			quit(0); return true
	return false
