extends SceneTree
## Authored bust assets, sealed privacy, and shared texture reuse.
var failures := 0
func _initialize() -> void: call_deferred("run")
func check(ok: bool, label: String) -> void:
	if not ok: failures += 1
	print("PASS " if ok else "FAIL ", label)
func run() -> void:
	if not OS.has_environment("GRAND_EXHIBIT_TEST_RUN"): quit(2); return
	root.get_node("SaveSystem").set_process(false)
	var portrait = load("res://scenes/managers/manager_portrait.gd")
	var data := root.get_node("DataLoader")
	portrait._textures.clear()
	portrait._backgrounds.clear()
	var identities := {}
	for id in data.managers:
		var def: Dictionary = data.get_manager_def(id)
		var cached_rooms: int = portrait._backgrounds.size()
		var seal: Control = portrait.new(); root.add_child(seal); seal.setup(def,120,false)
		check(not portrait._textures.has(id), id+" sealed face is not loaded")
		check(portrait._backgrounds.size() == cached_rooms,id+" sealed file does not load a room background")
		check(seal._slot.get_child_count() == 2 and seal._slot.get_child(0) is Label and seal._slot.get_child(1) is Label,id+" sealed file contains only labels")
		seal.free()
		var owned: Control = portrait.new(); root.add_child(owned); owned.setup(def,248,true)
		var room := owned.find_child("ManagerBackground_"+str(def.get("specialty", "")),true,false) as TextureRect
		check(room != null,id+" has its own department room")
		if room != null:
			check(room.texture == portrait.background_for(def),id+" shares the correct department background")
			check(room.texture.get_size() == Vector2(512,640),id+" room has full portrait resolution")
		var texture = portrait.texture_for(def)
		check(texture != null,id+" has an authored portrait")
		if texture != null:
			check(texture.get_size() == Vector2(512,640),id+" has native portrait resolution")
			check(texture == portrait.texture_for(def),id+" reuses its cached texture")
			check(not identities.has(texture.resource_path),id+" uses an individual asset")
			identities[texture.resource_path] = true
			check(owned._slot.get_child_count() == 1 and owned._slot.get_child(0) is TextureRect,id+" immediately shows the portrait")
		owned.free()
	check(portrait._textures.size() == data.managers.size(),"Cache contains the fixed manager cast")
	check(portrait._backgrounds.size() == 4,"Only four room textures serve the whole manager cast")
	await process_frame
	print("MANAGER_PORTRAITS_DONE failures=",failures)
	quit(0 if failures == 0 else 1)
