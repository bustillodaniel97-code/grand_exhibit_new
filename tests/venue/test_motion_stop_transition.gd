extends SceneTree
const Character := preload("res://scenes/venue/floor/character.gd")
var failures := 0
func check(ok: bool, label: String) -> void:
	if not ok: failures += 1; printerr("FAIL: ", label)
func _initialize() -> void: call_deferred("run")
func run() -> void:
	for fps in [15,30,60,120]:
		var c := Character.new(); c.set_look_slot(2); root.add_child(c); c.set_process(false)
		c._cycle_phase=.31;c._frame=2;c.walking=false
		var phase: float=c._cycle_phase
		for i in ceili(Character.STOP_DEBOUNCE*fps*.75):c._process(1.0/fps)
		check(c._frame==2 and is_equal_approx(c._cycle_phase,phase),"%dfps brief block holds pose and phase"%fps)
		for i in ceili((Character.STOP_DEBOUNCE+.05)*fps):c._process(1.0/fps)
		check(c._frame==-1 and is_equal_approx(c._cycle_phase,phase),"%dfps long stop reaches idle without phase travel"%fps)
		c.walking=true;c.record_motion(Vector2.RIGHT*.02,.02);c._process(1.0/fps)
		check(c._frame>=0 and c._cycle_phase!=phase,"%dfps restart uses distance-selected walk"%fps)
		var moving_phase: float=c._cycle_phase
		for i in fps:c._process(1.0/fps)
		check(is_equal_approx(c._cycle_phase,moving_phase),"%dfps sustained distance-driven display does not invent travel"%fps)
		c.set_motion_vector(Vector2.UP,c.preferred_walk_speed());var corner_phase: float=c._cycle_phase
		c._process(0)
		check(c._view_back and is_equal_approx(c._cycle_phase,corner_phase),"%dfps facing transition preserves phase"%fps)
		c.free()
	# Incompatible action/cart states retain immediate dedicated poses.
	var cart:=Character.new();cart.set_uniform(Color.WHITE,0,"porter");root.add_child(cart);cart.set_process(false)
	cart.with_cart=true;cart._frame=3;cart.walking=false;cart._process(.01)
	check(cart._frame==-1,"cart stop bypasses ordinary-character debounce")
	cart.free()
	print("Motion stop transition failures: ",failures)
	quit(1 if failures else 0)
