extends "res://tools/world_edges_campaign.gd"
const Character:=preload("res://scenes/venue/floor/character.gd")
func run() -> void:
	output=OS.get_cmdline_user_args()[0];DirAccess.make_dir_recursive_absolute(output)
	root.get_node("SaveSystem").set_process(false)
	vp=SubViewport.new();vp.size=Vector2i(960,800);vp.render_target_update_mode=SubViewport.UPDATE_ALWAYS
	root.add_child(vp)
	var background:=ColorRect.new();background.color=Color("#d9dfd4");background.size=Vector2(960,800);vp.add_child(background)
	var characters: Array=[]
	for variant in 3:
		for dir in 4:
			var c:=Character.new();c.set_uniform(Color.WHITE,variant,"porter");c.with_cart=true;c.set_process(false)
			if c._cart_set.is_empty():printerr("FAIL missing cart asset ",variant);quit(1);return
			vp.add_child(c);c.position=Vector2(115+dir*240,215+variant*250);c.scale=Vector2.ONE*2.5
			c.walking=true;characters.append(c)
	var directions:=[Vector2(1,0),Vector2(0,1),Vector2(-1,0),Vector2(0,-1)]
	for cargo in [0,3]:
		for frame in 24:
			for i in characters.size():
				var c: Node=characters[i];c.carry_stack=cargo
				c.set_motion_vector(directions[i%4],c.preferred_walk_speed(1.75));c._cycle_phase=float(frame)/24;c._process(0)
			await capture(output+"/load%d-%02d.png"%[cargo,frame])
	quit(0)
