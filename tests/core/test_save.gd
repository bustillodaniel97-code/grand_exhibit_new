extends SceneTree
## test_save.gd — round-trip, corruption recovery, offline earnings, clock rollback.
## Run: godot --headless --path <repo> -s tests/core/test_save.gd

var failures := 0

func check(cond: bool, msg: String) -> void:
	if cond:
		print("  PASS ", msg)
	else:
		failures += 1
		print("  FAIL ", msg)

func _init() -> void:
	call_deferred("run")

const V := "whispering_pines"
const SAVE_FILE := "user://grand_exhibit_save.json"

func cleanup() -> void:
	for p in [SAVE_FILE, SAVE_FILE + ".bak"]:
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(p)

func run() -> void:
	for pair in [["event_bus","EventBus"],["data_loader","DataLoader"],["clock_guard","ClockGuard"],["analytics","Analytics"],["ad_service","AdService"],["iap_service","IAPService"],["game_state","GameState"],["save_system","SaveSystem"],["economy","Economy"]]:
		var n: Node = load("res://autoload/%s.gd" % pair[0]).new()
		n.name = pair[1]
		root.add_child(n)

	# Under -s the main script compiles before autoload names are bound;
	# access the bootstrapped singletons via local aliases instead.
	var EventBus: Node = root.get_node("EventBus")
	var DataLoader: Node = root.get_node("DataLoader")
	var ClockGuard: Node = root.get_node("ClockGuard")
	var Analytics: Node = root.get_node("Analytics")
	var GameState: Node = root.get_node("GameState")
	var SaveSystem: Node = root.get_node("SaveSystem")
	var Economy: Node = root.get_node("Economy")

	cleanup()
	GameState.reset_to_new_game()

	print("-- to_save_dict / from_save_dict round-trip --")
	GameState.cash = BigNumber.from_parts(1.23, 5)
	GameState.gems = 42
	GameState.insight = BigNumber.from_parts(4.5, 3)
	GameState.reputation_xp = BigNumber.from_float(77.0)
	GameState.set_dept_level(V, "ticket", "speed", 7)
	GameState.venue_state(V)["depts"]["archive"]["staff"] = 3
	GameState.pending_cash[V] = BigNumber.from_parts(9.9, 2)
	GameState.venues_unlocked = ["whispering_pines", "copper_kettle"]
	GameState.close_venue("whispering_pines")  # the ladder is one-way; it must persist
	GameState.boosts["income_x2_until"] = 123456
	var snap: Dictionary = GameState.to_save_dict()
	GameState.reset_to_new_game()
	GameState.from_save_dict(snap)
	check(GameState.cash.eq(BigNumber.from_parts(1.23, 5)), "cash round-trip")
	check(GameState.gems == 42, "gems round-trip")
	check(GameState.insight.eq(BigNumber.from_parts(4.5, 3)), "insight round-trip")
	check(GameState.reputation_xp.eq(BigNumber.from_float(77.0)), "reputation round-trip")
	check(GameState.rep_level() == 3, "rep_level derived after load (77xp -> 3)")
	check(GameState.dept_level(V, "ticket", "speed") == 7, "dept level round-trip")
	check(int(GameState.venue_state(V)["depts"]["archive"]["staff"]) == 3, "staff round-trip")
	check(GameState.pending_cash[V].eq(BigNumber.from_parts(9.9, 2)), "pending_cash round-trip")
	check(GameState.venues_unlocked == ["whispering_pines", "copper_kettle"], "venues_unlocked round-trip")
	check(GameState.venue_is_closed("whispering_pines"), "venues_closed round-trip")
	check(not GameState.venue_is_closed("copper_kettle"), "open venue stays open across a round-trip")
	check(int(GameState.boosts["income_x2_until"]) == 123456, "boosts round-trip")

	print("-- from_save_dict tolerates partial/migrated dicts --")
	GameState.from_save_dict({"cash": {"m": 5.0, "e": 1}, "gems": 7})
	check(GameState.cash.eq(BigNumber.from_float(50.0)), "partial dict: cash applied")
	check(GameState.gems == 7, "partial dict: gems applied")
	check(GameState.venue_state(V).has("depts"), "partial dict: venue defaults present")
	check(GameState.dept_level(V, "ticket", "speed") == 1, "partial dict: dept defaults present")

	print("-- file save / load --")
	cleanup()
	GameState.reset_to_new_game()
	GameState.cash = BigNumber.from_parts(1.23, 5)
	GameState.gems = 42
	GameState.set_dept_level(V, "ticket", "speed", 7)
	GameState.ready_flag = true
	SaveSystem.save_now()
	check(SaveSystem.has_save(), "save file written")
	GameState.cash = BigNumber.zero()
	GameState.gems = 0
	check(SaveSystem.load_game(), "load_game() true on valid save")
	check(GameState.cash.eq(BigNumber.from_parts(1.23, 5)), "cash restored from file")
	check(GameState.gems == 42, "gems restored from file")
	check(GameState.dept_level(V, "ticket", "speed") == 7, "dept level restored from file")

	print("-- corrupted checksum -> .bak + fresh start --")
	var text := FileAccess.get_file_as_string(SaveSystem.SAVE_PATH)
	var env: Dictionary = JSON.parse_string(text)
	env["state"]["gems"] = 99999  # tamper without fixing checksum
	var f := FileAccess.open(SaveSystem.SAVE_PATH, FileAccess.WRITE)
	f.store_string(JSON.stringify(env))
	f.close()
	check(SaveSystem.load_game() == false, "load_game() false on checksum mismatch")
	check(FileAccess.file_exists(SaveSystem.SAVE_PATH + ".bak"), "corrupt save renamed to .bak")
	check(not SaveSystem.has_save(), "corrupt save removed from live path")
	# garbage file also recovers
	cleanup()
	var f2 := FileAccess.open(SaveSystem.SAVE_PATH, FileAccess.WRITE)
	f2.store_string("{not json at all!!!")
	f2.close()
	check(SaveSystem.load_game() == false, "load_game() false on unparseable file")
	check(FileAccess.file_exists(SaveSystem.SAVE_PATH + ".bak"), "unparseable save backed up too")

	print("-- offline earnings --")
	GameState.ready_flag = false
	GameState.reset_to_new_game()
	GameState.cash = BigNumber.zero()
	var rate: float = Economy.current_cash_per_second().to_float_approx()
	var now_unix: int = ClockGuard.now()
	GameState.last_seen_unix = now_unix - 3600
	var off: Dictionary = SaveSystem.compute_offline_and_apply()
	# wall clock may drift a second or two during the call; allow slack
	check(abs(off["seconds"] - 3600) <= 5, "offline seconds ~3600 (got %d)" % off["seconds"])
	check(absf(off["amount"].to_float_approx() - rate * float(off["seconds"])) < 1.0, "offline amount == rate * seconds")
	check(not off["capped"], "not capped under cap")
	check(absf(GameState.cash.to_float_approx() - rate * float(off["seconds"])) < 1.0, "offline cash applied")
	var cap_s: int = int(float(DataLoader.core["economy"]["offline_cap_hours"]) * 3600.0)
	GameState.cash = BigNumber.zero()
	GameState.last_seen_unix = now_unix - 10 * 3600
	var off2: Dictionary = SaveSystem.compute_offline_and_apply()
	check(off2["seconds"] == cap_s, "offline clamped to cap (%d == %d)" % [off2["seconds"], cap_s])
	check(off2["capped"], "capped flag set")
	check(is_equal_approx(off2["amount"].to_float_approx(), rate * float(cap_s)), "capped amount == rate * cap")
	GameState.cash = BigNumber.zero()
	GameState.last_seen_unix = now_unix + 10000  # device clock rolled back
	var off3: Dictionary = SaveSystem.compute_offline_and_apply()
	check(off3["seconds"] == 0, "clock rollback -> 0 seconds")
	check(off3["amount"].is_zero(), "clock rollback -> 0 amount")
	check(GameState.cash.is_zero(), "rollback grants nothing")

	print("-- migrate passthrough --")
	var migrated: Dictionary = SaveSystem.migrate({"cash": {"m": 1.0, "e": 2}}, 1)
	check(migrated.has("cash"), "migrate(v1) keeps state keys")

	cleanup()
	print("RESULT: ", "ALL PASS" if failures == 0 else "%d FAILURES" % failures)
	quit(0 if failures == 0 else 1)
