extends SceneTree
const Character:=preload("res://scenes/venue/floor/character.gd")
const Roster:=preload("res://scripts/characters/npc_roster.gd")
var failures:=0
func check(ok: bool,label: String) -> void:
	if not ok:failures+=1;printerr("FAIL: ",label)
func _initialize() -> void:call_deferred("run")
func run() -> void:
	for slot in 24:
		var c:=Character.new();c.set_look_slot(slot);root.add_child(c);c.set_process(false)
		c.scale=Vector2.ONE*c.age_scale()
		var stride: float=c.preferred_walk_speed(1)
		check(c.walk_cadence()>=1.1 and c.walk_cadence()<=1.8,"visitor pace stays within walking range")
		for fps in [15,30,60,120]:
			c._cycle_phase=0;c.walking=true;c.walk_backwards=false
			for step in fps:
				c.record_motion(Vector2.RIGHT*stride*.375/float(fps),1.0/float(fps))
				c._process(1.0/float(fps))
			check(absf(c._cycle_phase-.375)<.00001,"same ground travel has the same phase at every render rate")
			c._process(2)
			check(absf(c._cycle_phase-.375)<.00001,"rendering without movement cannot add footsteps")
		c.record_motion(Vector2.UP*stride*.125,.5)
		c._process(0)
		check(absf(c._cycle_phase-.5)<.00001 and c._view_back,"corner preserves distance phase while changing view")
		c.record_motion(Vector2.ZERO,3)
		check(absf(c._cycle_phase-.5)<.00001,"blocked movement adds no distance")
		c.walk_backwards=true;c.record_motion(Vector2.UP*stride*.25,.2,Vector2.DOWN)
		c._process(0)
		check(absf(c._cycle_phase-.25)<.00001 and not c._view_back,"backing toward a seat reverses steps while facing its front")
		c.walk_backwards=false;c.scale*=.82;c._cycle_phase=0
		c.record_motion(Vector2.RIGHT*stride*.82*.25,.2)
		check(absf(c._cycle_phase-.25)<.00001,"district scale keeps feet calibrated to the ground")
		c.free()
	# Shorter ordinary strides must not retime the independently authored cart
	# animation or shift the planted feet used to approach a bench.
	var porter:=Character.new();porter.with_cart=true
	porter.set_uniform(Color.WHITE,0,"porter");root.add_child(porter);porter.set_process(false)
	porter._motion_set=porter._motion_set.duplicate()
	var cart_stride: float=porter.preferred_walk_speed(1)
	var seat_distance: float=porter.seating_foot_distance()
	porter._motion_set.stride_grid*=.7
	check(is_equal_approx(porter.preferred_walk_speed(1),cart_stride),"walking changes preserve cart travel speed")
	check(is_equal_approx(porter.seating_foot_distance(),seat_distance),"walking changes preserve bench contact")
	porter._cycle_phase=0;porter.walking=true
	porter.record_motion(Vector2.RIGHT*cart_stride*.25,.2);porter._process(0)
	check(absf(porter._cycle_phase-.25)<.00001,"cart ground distance uses cart foot cycle")
	porter.free()
	print("Distance-driven walking failures: ",failures)
	quit(1 if failures else 0)
