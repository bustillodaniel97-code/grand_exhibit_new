extends SceneTree
## test_platform_achievements.gd — PlatformServices mirroring achievements to
## Google Play Games and Game Center, against fakes of the two plugins'
## singletons (GodotPlayGameServices, GameCenter).
##
## Proves: nothing is sent before the player is signed in; a sign-in sends
## everything earned so far; a new unlock is sent at once with the right id
## (Play Console ids from the mapping, Game Center ids with the prefix); an
## unmapped Play Games achievement stays local; a failed sign-in stops the
## mirroring; each store's achievements screen opens.
## What still needs a device: the real plugins and store listings.

var failures := 0

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
	var initialized := 0
	var asked := 0
	var unlocked: Array = []
	var shown := 0
	func initialize() -> void:
		initialized += 1
	func isAuthenticated() -> void:
		asked += 1
	func unlockAchievement(id: String) -> void:
		unlocked.append(id)
	func showAchievements() -> void:
		shown += 1

class FakeGameCenter:
	extends Object
	var events: Array = []
	var auths := 0
	var awards: Array = []
	var views: Array = []
	func authenticate() -> int:
		auths += 1
		return OK
	func award_achievement(params: Dictionary) -> int:
		awards.append(params)
		return OK
	func show_game_center(params: Dictionary) -> int:
		views.append(params)
		return OK
	func get_pending_event_count() -> int:
		return events.size()
	func pop_pending_event() -> Variant:
		return events.pop_front()

func _award_names(gc: FakeGameCenter) -> Array:
	var names: Array = []
	for a in gc.awards:
		names.append(str((a as Dictionary).get("name", "")))
	return names

func run() -> void:
	if not OS.has_environment("GRAND_EXHIBIT_TEST_RUN"):
		printerr("REFUSED: requires GRAND_EXHIBIT_TEST_RUN isolation"); quit(2); return
	var gs: Node = root.get_node("GameState")
	var ps: Node = root.get_node("PlatformServices")
	root.get_node("SaveSystem").set_process(false)
	root.get_node("Economy").set_process(false)
	gs.reset_to_new_game()
	gs.ready_flag = true
	check(ps.backend == "none" and not ps.signed_in, "this build has no storefront")
	check(not ps.show_platform_achievements(), "with no storefront there's no achievements screen to open")
	var ids: Dictionary = ps.get("_platform_ids")
	check(ids.has("play_games") and ids.has("game_center_prefix"), "achievements.json carries the storefront id mapping")
	ps.unlock("FIRST_UPGRADE")
	ps.unlock("FIRST_VIP")

	# ---- Google Play Games.
	ps.set("_platform_ids", {"play_games": {"FIRST_UPGRADE": "CgkI_first", "GRAND": "CgkI_grand"}})
	var pg := FakePlayGames.new()
	ps._use_store_for_test("play_games", pg)
	check(ps.backend == "play_games" and pg.initialized == 1 and pg.asked == 1,
		"Play Games is initialized and asked whether the player is signed in")
	check(not ps.signed_in and pg.unlocked.is_empty(), "nothing is sent before the sign-in answer")
	ps.unlock("GRAND")
	check(ps.is_unlocked("GRAND") and pg.unlocked.is_empty(), "an unlock while signed out is kept locally")
	pg.emit_signal("userAuthenticated", true)
	check(ps.signed_in, "the sign-in answer is taken")
	check("CgkI_first" in pg.unlocked and "CgkI_grand" in pg.unlocked,
		"signing in sends everything earned so far, with the Play Console ids")
	check(pg.unlocked.size() == 2, "an achievement without a Play Console id stays local (got %s)" % str(pg.unlocked))
	check(ps.show_platform_achievements() and pg.shown == 1, "the Play Games achievements screen opens")
	pg.emit_signal("userAuthenticated", false)
	pg.unlocked.clear()
	ps.unlock("SECOND_FLOOR")
	ps.set("_platform_ids", {"play_games": {"SECOND_FLOOR": "CgkI_floor"}})
	ps.unlock("HUNDRED_UPGRADES")
	check(pg.unlocked.is_empty() and not ps.can_show_platform_achievements(),
		"after a failed sign-in nothing is sent and no screen is offered")
	ps._clear_store_for_test()

	# ---- Game Center.
	ps.set("_platform_ids", {"game_center_prefix": "grandexhibit.", "game_center": {"ROYAL_VISIT": "royal_custom"}})
	var gc := FakeGameCenter.new()
	ps._use_store_for_test("game_center", gc)
	check(ps.backend == "game_center" and gc.auths == 1, "Game Center authentication is started")
	await process_frame
	check(gc.awards.is_empty(), "nothing is awarded before authentication")
	gc.events.append({"type": "authentication", "result": "ok", "player_id": "P1"})
	await process_frame
	await process_frame
	check(ps.signed_in, "the authentication event is read from the queue")
	var names: Array = _award_names(gc)
	check("grandexhibit.FIRST_UPGRADE" in names and "grandexhibit.FIRST_VIP" in names and "grandexhibit.GRAND" in names,
		"authenticating sends everything earned so far, with the prefix")
	var quiet := true
	for a in gc.awards:
		quiet = quiet and not bool((a as Dictionary).get("show_completion_banner", true)) \
			and is_equal_approx(float((a as Dictionary).get("progress", 0.0)), 100.0)
	check(quiet, "a catch-up sync is at 100% and shows no banners")
	gc.awards.clear()
	ps.unlock("ROYAL_VISIT")
	check(gc.awards.size() == 1 and str(gc.awards[0]["name"]) == "royal_custom"
		and bool(gc.awards[0]["show_completion_banner"]),
		"a fresh unlock is awarded at once, mapped, with the banner")
	check(ps.show_platform_achievements() and gc.views.size() == 1
		and str((gc.views[0] as Dictionary).get("view", "")) == "achievements",
		"the Game Center achievements screen opens")
	gc.events.append({"type": "authentication", "result": "error", "error_code": 2})
	await process_frame
	await process_frame
	gc.awards.clear()
	ps.unlock("FULL_SET")
	check(not ps.signed_in and gc.awards.is_empty(), "a failed authentication stops the mirroring")
	ps._clear_store_for_test()
	check(ps.backend == "none", "the offline backend is back")

	pg.free()
	gc.free()
	await create_timer(0.8).timeout
	print("RESULT: ", "OK" if failures == 0 else "FAILED (%d)" % failures)
	quit(1 if failures > 0 else 0)
