extends SceneTree
## Longer ordinary gait banks must not retime travel, carts or public actions.
const Character := preload("res://scenes/venue/floor/character.gd")
const Motion := preload("res://scripts/characters/motion_sprites.gd")
var failures := 0

func check(ok: bool, label: String) -> void:
	if not ok:
		failures += 1
		printerr("FAIL: ", label)

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	for count in [8,16,24,32]:
		var records: Array = []
		records.resize(count)
		var raw := {"front":{"walk":records},"back":{"walk":records.duplicate()},"walk_frames":count}
		check(Motion.walk_frame_count(raw)==count,"complete %d-phase bank accepted"%count)
		raw.back.walk.pop_back()
		check(Motion.walk_frame_count(raw)==0,"partial %d-phase bank rejected"%count)
		var headings: Dictionary={}
		for h in 8:headings[str(h)]={"walk":records.duplicate()}
		var directional:={"directions":headings,"direction_walk_frames":count}
		check(Motion.direction_frame_count(directional)==count,"directional phase count is independent of legacy views")
		directional.directions["7"].walk.pop_back()
		check(Motion.direction_frame_count(directional)==0,"partial directional upgrade rejected")
		for fps in [15,30,60,120]:
			var c := Character.new()
			c.set_look_slot(2)
			root.add_child(c)
			c.set_process(false)
			c.scale=Vector2.ONE*c.age_scale()
			# Reuse validated source textures to test index selection independently
			# of whether this installation has already promoted a longer art bank.
			c._heading_set=c._heading_set.duplicate()
			var originals: Array=c._heading_set.walk.duplicate()
			var expanded: Array=[]
			for i in count:expanded.append(originals[i%originals.size()])
			c._heading_set.walk=expanded
			var hands: Array[Vector2]=[]
			for i in count:hands.append(Vector2(float(i),-20.0))
			c._heading_set.walk_hands=hands
			c._cycle_phase=0.0
			c.walking=true
			var speed: float=c.preferred_walk_speed()
			var stride: float=c.preferred_walk_speed(1.0)
			for tick in fps:
				c.record_motion(Vector2.RIGHT*stride*.375/float(fps),1.0/float(fps))
				c._process(1.0/float(fps))
			check(absf(c._cycle_phase-.375)<.00001,"%d frames / %d Hz keeps travelled phase"%[count,fps])
			# Floating sums may land just below .375; sample the actual phase.
			check(c._frame==Motion.phase_frame(c._cycle_phase,count),"every available gait sample can be selected")
			check(is_equal_approx(c.preferred_walk_speed(),speed),"frame count never changes walking speed")
			c.record_motion(Vector2.RIGHT*stride*.20,.10)
			var final_frame: int=Motion.phase_frame(c._cycle_phase,count)
			c.walking=false
			c._process(.01)
			check(c._frame==final_frame,"final travelled pose survives a same-tick stop")
			check(c.public_hand_position().is_equal_approx(c.position+hands[final_frame]*Vector2(absf(c.scale.x),c.scale.y)),"brief stop keeps a carried prop attached to the displayed wrist")
			var phase: float=c._cycle_phase
			c._process(Character.STOP_DEBOUNCE+.01)
			check(c._frame==-1 and is_equal_approx(c._cycle_phase,phase),"sustained stop reaches idle without invented distance")
			c.walking=true
			c._process(1.0)
			check(c._frame==final_frame and is_equal_approx(c._cycle_phase,phase),"resume preserves gait phase until actual travel")
			c.free()
	var actor := Character.new()
	actor.set_look_slot(2)
	root.add_child(actor)
	actor.set_process(false)
	var phase_before: float=actor._cycle_phase
	for degrees in [22.0,23.0,21.8,24.0,22.4]:
		actor.set_motion_vector(Vector2.RIGHT.rotated(deg_to_rad(degrees)),actor.preferred_walk_speed())
		check(actor._motion_heading==0,"small heading corrections do not flicker across a sprite boundary")
	actor.set_motion_vector(Vector2.RIGHT.rotated(deg_to_rad(30.0)),actor.preferred_walk_speed())
	check(actor._motion_heading==1,"deliberate direction change crosses hysteresis immediately")
	actor.set_motion_vector(Vector2.RIGHT.rotated(deg_to_rad(21.0)),actor.preferred_walk_speed())
	check(actor._motion_heading==1,"reverse boundary jitter retains the new heading")
	actor.set_motion_vector(Vector2.RIGHT.rotated(deg_to_rad(21.0)),0.0)
	check(actor._motion_heading==0,"station-facing commands are exact even without travel")
	check(is_equal_approx(actor._cycle_phase,phase_before),"turning display never advances footsteps")
	actor.free()
	var porter := Character.new()
	porter.set_uniform(Color.WHITE,0,"porter")
	root.add_child(porter)
	porter.set_process(false)
	porter._cycle_phase=.75
	porter._frame=24
	porter.with_cart=true
	var cart_count: int=porter._cart_set.get("walk_frames",8)
	check(porter._walk_frame_count()==cart_count and porter._frame==Motion.phase_frame(.75,cart_count),"cart selection uses its independently authored phase count")
	porter.free()
	print("Motion sampling failures: ",failures)
	quit(1 if failures else 0)
