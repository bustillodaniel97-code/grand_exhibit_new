extends SceneTree
const Carts:=preload("res://scripts/characters/cart_sprites.gd")
const Roster:=preload("res://scripts/characters/npc_roster.gd")
const Character:=preload("res://scenes/venue/floor/character.gd")
var failures:=0
func check(ok: bool,label: String) -> void:
	if not ok:failures+=1;printerr("FAIL: ",label)
func _initialize() -> void:call_deferred("run")
func run() -> void:
	for variant in 3:
		var identity:=Roster.employee("porter",variant)
		var packet:=Carts.get_set(identity)
		check(not packet.is_empty(),"complete cart for "+str(identity.id))
		if packet.is_empty():continue
		check(bool(packet.get("steering",false)),"live set has true four-way steering")
		for view in 4:
			for cargo in ["0","1"]:
				var state: Dictionary=packet[cargo][str(view)]
				check(state.walk.size()==Carts.Steering.walk_frame_count(),"complete moving cart cycle")
				for tex in state.walk+[state.idle]:
					check(tex.get_size()==Vector2(336,336),"consistent untrimmed canvas/ground origin")
					check(tex.atlas.get_image().has_mipmaps(),"smooth imported minification at gameplay scale")
			check(packet["0"][str(view)].idle.get_image().get_data()!=packet["1"][str(view)].idle.get_image().get_data(),"empty cart differs from loaded cart")
		var fake:=identity.duplicate();fake.gender="female" if identity.gender=="male" else "male"
		check(Carts.get_set(fake).is_empty(),"warm cache rejects wrong identity")
		var c:=Character.new();c.set_uniform(Color.WHITE,variant,"porter");root.add_child(c);c.set_process(false)
		check(not c._cart_set.is_empty(),"live porter uses cart assets")
		c.with_cart=true;c.walking=true
		for direction in [Vector2(1,0),Vector2(0,1),Vector2(-1,0),Vector2(0,-1)]:
			var before: float=c._cycle_phase;c.record_motion(direction*.05,.1);c._process(0)
			check(not is_equal_approx(before,c._cycle_phase),"cart preserves distance-based walk")
			check(c._view_back==(direction.x+direction.y<0),"cart follows front/back movement")
		c.carry_stack=0;c.walking=false;c._process(0)
		check(c._frame==-1,"stopped cart selects planted idle")
		for cargo in [0,3]:
			c.carry_stack=cargo
			for first in 4:
				for direction in [-1,1]:
					var last:=posmod(first+direction,4)
					var arc: Array=Carts.Steering.turn_frames(identity,first,direction,cargo>0)
					var intervals := Carts.Steering.turn_intervals()
					check(arc.size()==intervals-1,"complete authored turn arc")
					var used: Dictionary={}
					for frame in intervals+1:
						c.set_cart_turn(Carts.Steering.DIRECTIONS[first],Carts.Steering.DIRECTIONS[last],float(frame)/float(intervals));c._process(0)
						var tex: Texture2D=c._steering_texture();used[tex.get_instance_id()]=true
						check(tex.get_size()==Vector2(336,336),"turn shares planted-foot canvas")
						check(tex.atlas.get_image().has_mipmaps(),"turn mipmaps present")
						if frame==0:check(tex==packet["1" if cargo>0 else "0"][str(first)].idle,"turn begins in exact idle view")
						elif frame==intervals:check(tex==packet["1" if cargo>0 else "0"][str(last)].idle,"turn ends in exact idle view")
					check(used.size()==intervals+1,"distinct authored poses throughout the complete turn")
					c.record_motion(Carts.Steering.DIRECTIONS[last]*.05,.1);c.walking=true;c._process(0)
					check(c._cart_turn.is_empty(),"walking clears completed turn")
					check(c._cart_turn_frames.is_empty(),"walking releases per-character turning textures")
					check(c._steering_texture()==packet["1" if cargo>0 else "0"][str(last)].walk[c._frame],"walking rejoins same true direction")
		check(Carts.Steering._arcs.size()<=Carts.Steering.ARC_CACHE_LIMIT,"turn cache bounded")
		check(Carts.Steering.turn_frames(fake,0,1,false).is_empty(),"turn warm cache rejects forged identity")
		c.free()
	for i in 24:check(Carts.get_set(Roster.visitor(i)).is_empty(),"visitor excluded from staff cart")
	for role in ["ticket","docent","promotions"]:
		for i in 3:check(Carts.get_set(Roster.employee(role,i)).is_empty(),"other staff excluded")
	check(Carts.get_set(Roster.RESERVED_HOST).is_empty(),"Ellis excluded")
	print("Cart animation failures: ",failures);quit(1 if failures else 0)
