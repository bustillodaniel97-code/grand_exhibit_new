extends SceneTree
const Roster := preload("res://scripts/characters/npc_roster.gd")
const Activity := preload("res://scripts/characters/activity_sprites.gd")
const Character := preload("res://scenes/venue/floor/character.gd")
const Motion := preload("res://scripts/characters/motion_sprites.gd")
const Plaza := preload("res://scenes/venue/floor/public_plaza.gd")
var failures := 0
func check(ok: bool,label: String) -> void:
	if not ok:failures+=1;printerr("FAIL: ",label)
func _initialize() -> void:call_deferred("run")
func run() -> void:
	root.get_node("SaveSystem").set_process(false)
	var textures := 0
	for slot in 24:
		var identity := Roster.visitor(slot)
		var frames := Activity.feeding_frames(identity)
		check(frames.size()==Activity.frame_count(),"all visitor demographics have the complete feeding action: "+str(identity.id))
		for tex in frames:
			check(tex.get_size()==Vector2(192,288),"transparent crop restores unchanged foot anchor")
			check(tex.atlas.get_image().has_mipmaps(),"activity art imports with mipmaps")
			textures+=1
		var actor := Character.new();actor.set_look_slot(slot);root.add_child(actor);actor.set_process(false)
		actor.prepare_bird_feeding()
		check(actor._feeding_frames.size()==1 and actor._feeding_frame==-1,"approach loads one frame without replacing the walking appearance")
		actor.set_motion_vector(Vector2(.5,.4),0)
		actor.set_bird_feeding(true,1.125)
		check(actor._feeding_frame==Activity.release_frame(),"food release remains at 1.125 seconds when art gains samples")
		var hand := actor.public_hand_position()
		check(hand.is_equal_approx(actor.public_hand_position(true)),"release begins at the visible wrist")
		actor.set_bird_feeding(true,3.125)
		check(actor._feeding_frame==int(.125/Activity.DURATION*Activity.frame_count()),"feeding loop advances independently of idle walking state")
		actor.walking=true;actor.set_bird_feeding(false)
		check(actor._feeding_frame==-1 and actor._feeding_frames.is_empty(),"departure releases activity textures and restores gait")
		for direction in [Vector2(1,0),Vector2(-1,0),Vector2(0,1),Vector2(0,-1)]:
			actor.set_motion_vector(direction,actor.preferred_walk_speed())
			actor._process(.1)
			var p: Vector2=actor._heading_set.walk_hands[actor._frame]
			check(actor.public_hand_position().is_equal_approx(actor.position+p*Vector2(absf(actor.scale.x),actor.scale.y)),"leash wrist follows the displayed true-yaw gait pose")
		actor.walking=false;actor.set_bird_feeding(true,1)
		actor.set_look_slot((slot+1)%24)
		check(actor._feeding_frames.is_empty() and actor._feeding_frame==-1,"appearance changes release the previous person's activity art")
		actor.free()
	check(Activity.record_for(Roster.RESERVED_HOST).is_empty(),"host excluded from public activities")
	check(Activity.feeding_frames(Roster.employee("ticket",0)).is_empty(),"employees cannot enter public activity roster")
	var forged := Roster.visitor(0);forged.variant=3
	check(Activity.record_for(forged).is_empty(),"invalid identity rejected after metadata cache warmed")
	for seed_value in 12:
		var plaza := Plaza.new();plaza._rng.seed=seed_value
		for kind in ["rest","feed","dog"]:
			var seen: Dictionary={}
			for visit in 24:seen[plaza._visitor_slot(kind)]=true
			check(seen.size()==24,"each activity rotates the full cast independently of activity order")
	print("PUBLIC_ACTIVITIES textures=",textures," identities=24 failures=",failures)
	quit(1 if failures else 0)
