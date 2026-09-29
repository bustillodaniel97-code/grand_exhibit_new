extends SceneTree
## test_cloud_save.gd — cloud save through Play Games saved games
## (cloud_save.gd + PlatformServices), against a fake of the
## GodotPlayGameServices singleton.
##
## Proves: the payload round-trips (gzip JSON envelope); progress orders saves
## by museums, then milestones, then reputation; signing in asks for the cloud
## copy; a cloud save further along is offered, not applied, and blocks
## uploads until the player decides; one that is behind is replaced by this
## phone's; "keep this phone's" uploads; "load" replaces the game state and
## saves it; uploads are rate-limited; backgrounding uploads.

var failures := 0
var CS: GDScript

func check(ok: bool, message: String) -> void:
	if ok:
		print("  PASS ", message)
	else:
		failures += 1
		printerr("  FAIL ", message)

func _initialize() -> void:
	call_deferred("run")

class FakePlayGames:
	extends Object
	signal userAuthenticated(is_authenticated: bool)
	signal gameSaved(is_saved: bool, save_data_name: String, save_data_description: String)
	signal gameLoaded(json_data: String)
	var saves: Array = []
	var loads: Array = []
	func initialize() -> void:
		pass
	func isAuthenticated() -> void:
		pass
	func unlockAchievement(_id: String) -> void:
		pass
	func saveGame(file_name: String, description: String, data: PackedByteArray, played_ms: int, progress: int) -> void:
		saves.append({"name": file_name, "desc": description, "data": data, "played": played_ms, "progress": progress})
	func loadGame(file_name: String, create_if_not_found: bool) -> void:
		loads.append([file_name, create_if_not_found])
	## Answer a load the way the plugin does: JSON with the bytes as numbers.
	func answer(bytes: PackedByteArray) -> void:
		var arr: Array = []
		for b in bytes:
			arr.append(int(b))
		gameLoaded.emit(JSON.stringify({"content": arr, "metadata": {"uniqueName": "grand_exhibit_main"}}))

func run() -> void:
	if not OS.has_environment("GRAND_EXHIBIT_TEST_RUN"):
		printerr("REFUSED: requires GRAND_EXHIBIT_TEST_RUN isolation"); quit(2); return
	CS = load("res://scripts/platform/cloud_save.gd")
	var gs: Node = root.get_node("GameState")
	var ps: Node = root.get_node("PlatformServices")
	var ss: Node = root.get_node("SaveSystem")
	ss.set_process(false)
	root.get_node("Economy").set_process(false)
	gs.reset_to_new_game()
	gs.ready_flag = true

	# Payload and progress.
	var local: Dictionary = gs.to_save_dict()
	var bytes: PackedByteArray = CS.encode(local, ss.SAVE_VERSION, 1000)
	var back: Dictionary = CS.decode(bytes)
	check(int(back.get("version", 0)) == ss.SAVE_VERSION and int(back.get("saved_at", 0)) == 1000
		and str((back["state"] as Dictionary).get("current_venue", "")) == str(local["current_venue"]),
		"the save round-trips through the compressed payload")
	check(CS.decode(PackedByteArray([1, 2, 3])).is_empty(), "garbage decodes to nothing")
	var ahead: Dictionary = local.duplicate(true)
	ahead["venues_unlocked"] = ["whispering_pines", "grand_river", "sunspire"]
	var more_ms: Dictionary = local.duplicate(true)
	(more_ms["venues_state"] as Dictionary)[str(local["current_venue"])] = {"milestones": ["a", "b"]}
	check(CS.progress_of(ahead) > CS.progress_of(more_ms) and CS.progress_of(more_ms) > CS.progress_of(local),
		"progress: museums, then milestones, then reputation")

	# Sign-in asks the cloud; a further-along save is offered.
	var fake := FakePlayGames.new()
	ps._use_store_for_test("play_games", fake)
	check(ps.cloud != null, "Play Games brings cloud save with it")
	fake.userAuthenticated.emit(true)
	check(fake.loads.size() == 1 and str(fake.loads[0][0]) == CS.SLOT, "signing in asks for the cloud save")
	var offered: Array = []
	ps.cloud_save_available.connect(func(s: Dictionary) -> void: offered.append(s))
	fake.answer(CS.encode(ahead, ss.SAVE_VERSION, 2000))
	check(offered.size() == 1 and int(offered[0]["museums"]) == 3, "a cloud save further along is offered")
	check((gs.venues_unlocked as Array).size() == 1, "and not applied behind the player's back")
	fake.saves.clear()
	check(not ps.sync_cloud(true) and fake.saves.is_empty(), "no upload while the player hasn't decided")
	check(not (ps.cloud_summary() as Dictionary).is_empty(), "Settings can show it")

	# Keep this phone's: it becomes the cloud copy.
	ps.keep_local_save()
	check(fake.saves.size() == 1 and int(fake.saves[0]["progress"]) == CS.progress_of(gs.to_save_dict()),
		"keeping this phone's uploads it")
	check(CS.decode(fake.saves[0]["data"]).get("state", {}) is Dictionary, "the upload is a readable save")

	# A cloud save that's behind is simply replaced.
	fake.saves.clear()
	var behind: Dictionary = local.duplicate(true)
	behind["venues_unlocked"] = []
	fake.answer(CS.encode(behind, ss.SAVE_VERSION, 500))
	check((ps.cloud_summary() as Dictionary).is_empty() and fake.saves.size() == 1, "a cloud save behind this phone is replaced")
	fake.saves.clear()
	fake.answer(PackedByteArray())
	check(fake.saves.size() == 1, "no cloud save yet: this phone's is uploaded")

	# Load the cloud save.
	fake.answer(CS.encode(ahead, ss.SAVE_VERSION, 3000))
	check(ps.load_cloud_save(false), "the player loads the cloud save")
	check((gs.venues_unlocked as Array).size() == 3, "its progress replaces this phone's")
	check(ss.load_game() and (gs.venues_unlocked as Array).size() == 3, "and it is saved to disk")
	check(not ps.load_cloud_save(false), "loading twice does nothing")

	# Rate limit and backgrounding.
	fake.saves.clear()
	check(not ps.sync_cloud(), "a second upload within minutes waits")
	check(ps.sync_cloud(true) and fake.saves.size() == 1, "a forced one goes")
	ps.cloud._last_upload_ms = -CS.MIN_UPLOAD_GAP_MS * 2
	ps._notification(Node.NOTIFICATION_APPLICATION_PAUSED)
	check(fake.saves.size() == 2, "going to the background uploads")

	ps._clear_store_for_test()
	check(ps.cloud == null, "clearing the store drops cloud save")
	fake.free()
	await create_timer(0.3).timeout
	print("RESULT: ", "OK" if failures == 0 else "FAILED (%d)" % failures)
	quit(1 if failures > 0 else 0)
