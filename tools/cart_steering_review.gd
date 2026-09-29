extends "res://tools/world_edges_campaign.gd"
const Character:=preload("res://scenes/venue/floor/character.gd")
const Steering:=preload("res://scripts/characters/cart_steering_sprites.gd")
func run() -> void:
	output=OS.get_cmdline_user_args()[0];DirAccess.make_dir_recursive_absolute(output)
	root.get_node("SaveSystem").set_process(false)
	vp=SubViewport.new();vp.size=Vector2i(960,800);vp.render_target_update_mode=SubViewport.UPDATE_ALWAYS
	root.add_child(vp)
	var background:=ColorRect.new();background.color=Color("#d9dfd4");background.size=Vector2(960,800);vp.add_child(background)
	var characters: Array=[]
	for variant in 3:
		for start in 4:
			var c:=Character.new();c.set_uniform(Color.WHITE,variant,"porter");c.with_cart=true;c.set_process(false)
			if not bool(c._cart_set.get("steering",false)):printerr("FAIL missing true cart steering ",variant);quit(1);return
			vp.add_child(c);c.position=Vector2(115+start*240,215+variant*250);c.scale=Vector2.ONE*2.5
			characters.append(c)
	for cargo in [0,3]:
		for direction in [-1,1]:
			for frame in 9:
				for i in characters.size():
					var c: Node=characters[i];c.carry_stack=cargo
					var start:=i%4;var last:=posmod(start+direction,4)
					c.walking=false;c.set_cart_turn(Steering.DIRECTIONS[start],Steering.DIRECTIONS[last],float(frame)/8);c._process(0)
				await capture(output+"/load%d-turn%d-%02d.png"%[cargo,direction,frame])
	print("STEERING_REVIEW 432 actor poses; 3 identities, 4 starts, 2 turn senses, 2 cargo states, 9 frames")
	quit(0)
