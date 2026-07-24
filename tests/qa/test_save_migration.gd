extends SceneTree
## QA M5-3: save migration (v1 -> v2 envelope) + corruption recovery (SPEC §10).
## - Craft a version:1 envelope with a VALID checksum whose state lacks
##   expedition_state/event_state -> load_game() true, defaults present after load.
## - Tamper state without fixing checksum -> load_game() false, save renamed to
##   .bak, and a fresh boot (reset_to_new_game) survives.
## Checksum salt is read from SaveSystem._SALT (no duplication of the constant).
## Run: godot --headless --path <repo> -s tests/qa/test_save_migration.gd

var failures: int = 0

const SAVE_FILE := "user://grand_exhibit_save.json"

func check(cond: bool, msg: String) -> void:
	if cond:
		print("  PASS ", msg)
	else:
		failures += 1
		printerr("  FAIL ", msg)

func cleanup() -> void:
	for p in [SAVE_FILE, SAVE_FILE + ".bak"]:
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(p)

func write_envelope(env: Dictionary) -> void:
	var f := FileAccess.open(SAVE_FILE, FileAccess.WRITE)
	f.store_string(JSON.stringify(env))
	f.close()

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var DL: Node = root.get_node("DataLoader")
	var GS: Node = root.get_node("GameState")
	var SS: Node = root.get_node("SaveSystem")
	DL.reload_all()
	cleanup()
	GS.reset_to_new_game()
	GS.ready_flag = true  # save_now() requires it

	print("-- craft v1 envelope (missing expedition/event keys, valid checksum) --")
	GS.cash = BigNumber.from_parts(1.5, 4)  # 15K marker
	GS.gems = 77
	SS.save_now()
	check(SS.has_save(), "baseline v2 save written")
	var env: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(SAVE_FILE))
	check(int(env.get("version", 0)) == 2, "baseline envelope is version 2")
	var v1_state: Dictionary = env["state"].duplicate(true)
	v1_state.erase("expedition_state")
	v1_state.erase("event_state")
	check(not v1_state.has("expedition_state") and not v1_state.has("event_state"),
		"v1 state crafted without expedition/event keys")
	var payload: String = JSON.stringify(v1_state)
	var salt: String = SS._SALT  # private const, read not duplicated
	var v1_env := {
		"version": 1,
		"saved_at": int(env.get("saved_at", 0)),
		"checksum": (payload + salt).sha256_text(),
		"state": v1_state,
	}
	write_envelope(v1_env)
	GS.reset_to_new_game()
	check(SS.load_game() == true, "load_game() true on valid v1 envelope")
	check(GS.expedition_state.has("stage") and GS.expedition_state.has("insight_stored")
		and GS.expedition_state.has("last_tick") and GS.expedition_state.has("boss_unlocked"),
		"migrated expedition_state defaults present")
	check(typeof(GS.event_state) == TYPE_DICTIONARY, "migrated event_state is a Dictionary")
	check(GS.cash.eq(BigNumber.from_parts(1.5, 4)), "v1 cash preserved through migration")
	check(GS.gems == 77, "v1 gems preserved through migration")
	# Migrated state must survive a v2 round-trip (save + load again).
	SS.save_now()
	var env2: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(SAVE_FILE))
	check(int(env2.get("version", 0)) == 2, "re-save upgrades envelope to version 2")
	GS.reset_to_new_game()
	check(SS.load_game() == true and GS.cash.eq(BigNumber.from_parts(1.5, 4)),
		"migrated save round-trips as v2")

	print("-- checksum tamper -> .bak + false + fresh boot survives --")
	cleanup()
	GS.reset_to_new_game()
	GS.ready_flag = true
	GS.cash = BigNumber.from_parts(9.9, 3)
	SS.save_now()
	var tampered: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(SAVE_FILE))
	tampered["state"]["gems"] = 999999  # tamper WITHOUT recomputing checksum
	write_envelope(tampered)
	check(SS.load_game() == false, "load_game() false on checksum mismatch")
	check(FileAccess.file_exists(SAVE_FILE + ".bak"), "tampered save renamed to .bak")
	check(not SS.has_save(), "tampered save removed from live path")
	# Boot path per main.gd: load fails -> reset_to_new_game -> game runs.
	GS.reset_to_new_game()
	GS.ready_flag = true
	check(GS.gems == 25, "fresh game starter gems after corruption (got %d)" % GS.gems)
	check(GS.venue_state(GS.current_venue).has("depts"), "fresh game venue state present")
	check(GS.cash.is_zero(), "fresh game cash zero after corruption")
	check(SS.load_game() == false or SS.has_save() == false, "no phantom save after recovery")

	cleanup()
	print("---")
	if failures == 0:
		print("ALL QA SAVE-MIGRATION TESTS PASSED")
	else:
		printerr("QA SAVE-MIGRATION TESTS FAILED: %d" % failures)
	quit(0 if failures == 0 else 1)
