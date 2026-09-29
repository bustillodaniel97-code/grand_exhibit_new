extends SceneTree
## Native runtime art review. Choreographed actions, not navigation evidence.
## Requires GRAND_EXHIBIT_TEST_RUN=1 and an isolated APPDATA/XDG_DATA_HOME.
const Character := preload("res://scenes/venue/floor/character.gd")
const Motion := preload("res://scripts/characters/motion_sprites.gd")
const Seating := preload("res://scripts/characters/seating_sprites.gd")
const Activity := preload("res://scripts/characters/activity_sprites.gd")
const Cart := preload("res://scripts/characters/cart_steering_sprites.gd")
const FPS := 24
var viewport: SubViewport
var output := ""
var page := "walk"
var actors: Array = []

func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("out="):output=arg.trim_prefix("out=")
		if arg.begins_with("page="):page=arg.trim_prefix("page=")
	call_deferred("run")

func caption(text: String, point: Vector2, size: int = 16) -> void:
	var label := Label.new()
	label.text=text;label.position=point
	label.add_theme_font_size_override("font_size",size)
	label.add_theme_color_override("font_color",Color("263e47"))
	viewport.add_child(label)

func run() -> void:
	if OS.get_environment("GRAND_EXHIBIT_TEST_RUN")!="1" or output.is_empty():
		printerr("Animation review requires an isolated test profile and out= directory")
		quit(2);return
	DirAccess.make_dir_recursive_absolute(output)
	for child in root.get_children():child.process_mode=Node.PROCESS_MODE_DISABLED
	viewport=SubViewport.new();viewport.size=Vector2i(960,640)
	viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS
	viewport.canvas_item_default_texture_filter=Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	root.add_child(viewport)
	var background := Polygon2D.new()
	background.polygon=PackedVector2Array([Vector2.ZERO,Vector2(960,0),Vector2(960,640),Vector2(0,640)])
	background.color=Color("e6eeeb");viewport.add_child(background)
	caption("Grand Exhibit / "+page.capitalize()+" / actual game renderer",Vector2(24,14),22)
	caption("2x character scale. Choreographed actions for visual inspection.",Vector2(24,46))
	for index in (3 if page=="cart" else 8):
		var actor := Character.new()
		if page=="cart":actor.set_uniform(Color.WHITE,index,"porter")
		else:actor.set_look_slot(index)
		viewport.add_child(actor);actor.set_process(false)
		actor.scale=Vector2.ONE*actor.age_scale()*2
		var origin := Vector2(165+index*315,365) if page=="cart" else Vector2(140+(index%4)*235,270+(index/4)*255)
		actor.position=origin
		actor.walking=false;actor._process(.1)
		if page=="cart":actor.with_cart=true;actor.carry_stack=1
		if page=="seat":assert(actor.begin_seating(Vector2.DOWN,Vector2.ZERO))
		actors.append({"node":actor,"origin":origin})
		caption(str(actor.identity.age_group).replace("_"," ")+" / "+str(actor.identity.gender),origin+Vector2(-102,45),14)
		var guide := Line2D.new()
		guide.width=1;guide.default_color=Color("b5c8c4")
		guide.add_point(origin+Vector2(-110,0));guide.add_point(origin+Vector2(95,0))
		viewport.add_child(guide);viewport.move_child(guide,1)
	var count := 144
	for frame in count:
		var time := float(frame)/FPS
		for item in actors:
			var actor: Node2D=item.node
			if page=="walk":
				var segment := fmod(time,3.0)
				var direction := Vector2.DOWN if time<3 else Vector2.UP
				actor.walking=segment<1.8
				if actor.walking:
					var delta: Vector2=direction*actor.preferred_walk_speed(1.0)/FPS
					actor.record_motion(delta,1.0/FPS)
					actor.position+=Vector2((delta.x-delta.y)*30,(delta.x+delta.y)*20)*2
			elif page=="feed":
				actor.set_motion_vector(Vector2.DOWN,0)
				actor.set_bird_feeding(true,time)
			elif page=="seat":
				var segment := fmod(time,3.0)
				if segment<.8:actor.advance_seating(1.0/FPS,true)
				elif segment>=1.5:actor.advance_seating(1.0/FPS,false)
			elif page=="cart":
				var segment := fmod(time,3.0)
				var first := Vector2.DOWN if time<3 else Vector2.RIGHT
				var last := Vector2.RIGHT if time<3 else Vector2.UP
				if segment<1.5:
					actor.walking=true
					var delta: Vector2=first*actor.preferred_walk_speed(1.0)/FPS
					actor.record_motion(delta,1.0/FPS)
					actor.position+=Vector2((delta.x-delta.y)*30,(delta.x+delta.y)*20)*2
				else:actor.set_cart_turn(first,last,clampf((segment-1.5)/1.2,0,1))
			actor._process(1.0/FPS);actor.queue_redraw()
		await RenderingServer.frame_post_draw
		assert(viewport.get_texture().get_image().save_png(output.path_join("frame-%03d.png"%frame))==OK)
	var manifest := {"scope":"Actual Character renderer; choreography, not pathfinding or device performance.","page":page,"fps":FPS,"frames":count,
		"walk_frames":actors[0].node._walk_frame_count(),"feeding_frames":Activity.frame_count(),"seating_frames":Seating.frame_count(),"cart_walk_frames":Cart.walk_frame_count(),"cart_turn_intervals":Cart.turn_intervals()}
	var file := FileAccess.open(output.path_join("review.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify(manifest,"\t"));file.close()
	print("ANIMATION_REVIEW ",JSON.stringify(manifest));quit(0)
