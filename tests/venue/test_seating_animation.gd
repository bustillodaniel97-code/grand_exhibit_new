extends SceneTree
const Roster:=preload("res://scripts/characters/npc_roster.gd")
const Seating:=preload("res://scripts/characters/seating_sprites.gd")
const Character:=preload("res://scenes/venue/floor/character.gd")
const Motion:=preload("res://scripts/characters/motion_sprites.gd")
var failures:=0
func check(ok: bool, label: String) -> void:
	if not ok:failures+=1;printerr("FAIL: ",label)
func _initialize() -> void:call_deferred("run")
func run() -> void:
	# Regression: an elder shoe at source y=280 was cropped by the former
	# 192x256 seated image. Full-canvas fallback must match the action projection.
	var source_image:=Image.create(80,220,false,Image.FORMAT_RGBA8)
	var source_texture:=ImageTexture.create_from_image(source_image)
	for height in [256,288]:
		var texture:=AtlasTexture.new();texture.atlas=source_texture
		texture.region=Rect2(Vector2.ZERO,Vector2(80,220))
		texture.margin=Rect2(Vector2(40,40),Vector2(112,height-220))
		var rect:=Motion.seated_draw_rect(texture)
		check(rect.size/texture.get_size()==Vector2(.25,.25),"seated fallback keeps the original pixel density")
		if height==288:
			check(is_equal_approx(rect.position.y+280*.25,10),"elder shoe below legacy canvas remains at action position")
		else:
			check(rect==Rect2(-24,-56,48,64),"existing seated images retain their placement")
	for slot in 24:
		var identity:=Roster.visitor(slot)
		var record:=Seating.record_for(identity)
		check(not record.is_empty(),"seating record for "+str(identity.id))
		for view in ["front","back"]:
			check(record.get(view,[]).size()==Seating.frame_count(),"complete sit/stand action")
		var c:=Character.new();c.set_look_slot(slot);root.add_child(c);c.set_process(false)
		for front in [Vector2.RIGHT,Vector2.DOWN,Vector2.LEFT,Vector2.UP]:
			check(c.begin_seating(front,Vector2(-4,2)),"visitor begins seating")
			c._process(0)
			check(c.seated and not c.walking and c._seating_progress==0,"seating starts in standing pose without walking")
			check(c._view_back==(front.x+front.y<0),"seated back view follows bench front")
			check(c._seating_frames.size()==Seating.frame_count()*2,"actor owns both views for the action")
			check(not c.advance_seating(.4,true),"halfway action has not finished")
			check(is_equal_approx(c._seating_progress,.5),"sit-down takes the authored duration")
			check(c.advance_seating(.4,true),"sit-down completes")
			check(not c.advance_seating(.4,false),"stand-up keeps seat occupied during motion")
			check(c.advance_seating(.4,false),"stand-up completes")
			c.end_seating()
			check(not c.seated and c._seating_frames.is_empty(),"departure releases seat action images")
		c.free()
	var fake:=Roster.visitor(0);fake.gender="invalid"
	check(Seating.record_for(fake).is_empty(),"metadata cache still rejects mismatched identity")
	check(Seating.record_for(Roster.employee("ticket",0)).is_empty(),"visitor seating excludes staff")
	check(Seating.record_for(Roster.RESERVED_HOST).is_empty(),"host stays outside visitor pool")
	check(Seating.frame(Roster.visitor(0),Seating.frame_count()*2)==null,"out-of-range action frame rejected")
	print("Seating animation failures: ",failures)
	quit(1 if failures else 0)
