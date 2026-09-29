extends SceneTree
## Settings screen: toggles write GameState.settings, the graphics choice reaches
## the live 3D museum (shadows, glow, tilt-shift), and Replay walkthrough rewinds
## the tutorial to its first step.

var failures := 0

func check(ok: bool, message: String) -> void:
	if ok:
		print("PASS: ", message)
	else:
		failures += 1
		printerr("FAIL: ", message)

func _initialize() -> void:
	call_deferred("run")

func _press(screen: Node, button_name: String) -> void:
	var b: Button = screen.find_child(button_name, true, false)
	check(b != null, "settings has a '%s' button" % button_name)
	if b != null:
		b.pressed.emit()
	await process_frame

func run() -> void:
	if not OS.has_environment("GRAND_EXHIBIT_TEST_RUN"):
		printerr("REFUSED: requires GRAND_EXHIBIT_TEST_RUN isolation"); quit(2); return
	var gs: Node = root.get_node("GameState")
	var ss: Node = root.get_node("SaveSystem")
	ss.set_process(false)
	var path: String = ss.save_path()
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)
	var vp := SubViewport.new()
	vp.size = Vector2i(720, 1280)
	root.add_child(vp)
	vp.add_child((load("res://scenes/main.tscn") as PackedScene).instantiate())
	await create_timer(2.5).timeout
	var floor: Node = root.find_child("VenueFloor", true, false)
	check(floor != null and floor.get("world") != null, "the 3D museum floor is mounted")
	var world: Node = floor.get("world")
	var screen: Control = (load("res://scenes/meta/settings_screen.tscn") as PackedScene).instantiate()
	vp.add_child(screen)
	await process_frame

	var music_before := bool(gs.settings.get("music", true))
	await _press(screen, "Toggle_music")
	check(bool(gs.settings.get("music", true)) != music_before, "the Music toggle flips the saved setting")

	await _press(screen, "gfx_low")
	check(str(gs.settings.get("gfx", "")) == "low", "choosing Low saves gfx=low")
	check(str(world.get("quality")) == "low", "Low reaches the live museum")
	var sun: DirectionalLight3D = world.get("_sun")
	var env: Environment = world.get("_env")
	check(sun != null and not sun.shadow_enabled, "Low turns sun shadows off")
	check(env != null and not env.glow_enabled, "Low turns glow off")

	gs.settings["gfx_auto_low"] = true
	await _press(screen, "gfx_high")
	check(str(world.get("quality")) == "high", "High restores the full-quality museum")
	check(sun.shadow_enabled and env.glow_enabled, "High turns shadows and glow back on")
	check(not gs.settings.has("gfx_auto_low"), "a manual choice clears the auto-low latch")

	gs.settings["tutorial_step"] = 99
	await _press(screen, "ReplayTutorial")
	check(int(gs.settings.get("tutorial_step", -1)) == 0, "Replay walkthrough rewinds the tutorial")
	var tut: Control = root.find_child("Tutorial", true, false)
	check(tut != null and tut.active() and tut.current_id() == "collect", "the walkthrough restarts at 'collect'")

	if is_instance_valid(screen):
		screen.queue_free()
	vp.queue_free()
	await create_timer(0.5).timeout
	gs.reset_to_new_game()
	print("RESULT: ", "OK" if failures == 0 else "FAILED (%d)" % failures)
	quit(1 if failures > 0 else 0)
