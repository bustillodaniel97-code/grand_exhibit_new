extends SceneTree
## QA M5-3: save migration (v1 and v2 envelopes) + corruption recovery (SPEC §10).
## - Craft a version:1 envelope with a VALID checksum whose state lacks
##   expedition_state/event_state -> load_game() true, defaults present after load.
## - Craft a version:2 envelope with no venues_closed -> load_game() true and the
##   one-way ladder rebuilt from venue order (SaveSystem._migrate_v2_to_v3).
## - Tamper state without fixing checksum -> load_game() false, save renamed to
##   .bak, and a fresh boot (reset_to_new_game) survives.
## Checksum salt is read from SaveSystem._SALT (no duplication of the constant).
## Run: godot --headless --path <repo> -s tests/qa/test_save_migration.gd

var failures: int = 0

## Resolved through SaveSystem rather than hardcoded. This suite deletes and
## corrupts the save on purpose, and on a developer box the literal path is
## the live player profile; SaveSystem.save_path() redirects into a throwaway
## subdirectory whenever the main loop is a res://tests/ script.
var _save_file_cache: String = ""
func save_file() -> String:
	if _save_file_cache.is_empty():
		# load() not preload(): under -s the main script compiles before autoload
		# names are bound, and save_system.gd names them. Resolving at runtime
		# sidesteps that. save_path() is static, so no instance is needed.
		_save_file_cache = load("res://autoload/save_system.gd").save_path()
	return _save_file_cache

func check(cond: bool, msg: String) -> void:
	if cond:
		print("  PASS ", msg)
	else:
		failures += 1
		printerr("  FAIL ", msg)

func cleanup() -> void:
	for p in [save_file(), save_file() + ".bak", save_file() + ".corrupt", save_file() + ".tmp", save_file() + ".bak.tmp"]:
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(p)

func write_envelope(env: Dictionary) -> void:
	var f := FileAccess.open(save_file(), FileAccess.WRITE)
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
	check(SS.has_save(), "baseline v3 save written")
	var env: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(save_file()))
	check(int(env.get("version", 0)) == SS.SAVE_VERSION, "baseline envelope is current SAVE_VERSION")
	var v1_state: Dictionary = env["state"].duplicate(true)
	v1_state.erase("expedition_state")
	v1_state.erase("event_state")
	v1_state.erase("venues_closed")
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
	check(typeof(GS.venues_closed) == TYPE_ARRAY, "migrated venues_closed is an Array")
	# Migrated state must survive a v3 round-trip (save + load again).
	SS.save_now()
	var env2: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(save_file()))
	check(int(env2.get("version", 0)) == SS.SAVE_VERSION, "re-save upgrades envelope to current SAVE_VERSION")
	GS.reset_to_new_game()
	check(SS.load_game() == true and GS.cash.eq(BigNumber.from_parts(1.5, 4)),
		"migrated save round-trips as v3")

	print("-- v2 -> v3: the one-way ladder is rebuilt from venue order --")
	# A real v2 player: three venues unlocked, standing in the third. v2 had no
	# venues_closed, so the migration has to infer that the first two are shut.
	cleanup()
	GS.reset_to_new_game()
	GS.ready_flag = true
	GS.venues_unlocked = ["whispering_pines", "copper_kettle", "grand_river"]
	GS.current_venue = "grand_river"
	GS.cash = BigNumber.from_parts(6.6, 7)
	SS.save_now()
	var v3_env: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(save_file()))
	var v2_state: Dictionary = v3_env["state"].duplicate(true)
	v2_state.erase("venues_closed")
	var v2_payload: String = JSON.stringify(v2_state)
	write_envelope({
		"version": 2,
		"saved_at": int(v3_env.get("saved_at", 0)),
		"checksum": (v2_payload + SS._SALT).sha256_text(),
		"state": v2_state,
	})
	GS.reset_to_new_game()
	check(SS.load_game() == true, "load_game() true on valid v2 envelope")
	check(GS.venue_is_closed("whispering_pines") and GS.venue_is_closed("copper_kettle"),
		"v2 migration closes every venue before the current one")
	check(not GS.venue_is_closed("grand_river"), "the venue the player is standing in stays open")
	check(GS.venues_closed.size() == 2, "no extra venues invented (got %d)" % GS.venues_closed.size())
	check(GS.current_venue == "grand_river" and GS.cash.eq(BigNumber.from_parts(6.6, 7)),
		"v2 venue and cash preserved through migration")
	# A v2 save still on the FIRST venue has nothing closed yet.
	cleanup()
	GS.reset_to_new_game()
	GS.ready_flag = true
	SS.save_now()
	var first_env: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(save_file()))
	var first_state: Dictionary = first_env["state"].duplicate(true)
	first_state.erase("venues_closed")
	var first_payload: String = JSON.stringify(first_state)
	write_envelope({
		"version": 2,
		"saved_at": int(first_env.get("saved_at", 0)),
		"checksum": (first_payload + SS._SALT).sha256_text(),
		"state": first_state,
	})
	GS.reset_to_new_game()
	check(SS.load_game() == true, "load_game() true on a first-venue v2 envelope")
	check(GS.venues_closed.is_empty(), "a player who never moved has closed nothing")

	print("-- checksum tamper -> .corrupt + false + fresh boot survives --")
	cleanup()
	GS.reset_to_new_game()
	GS.ready_flag = true
	GS.cash = BigNumber.from_parts(9.9, 3)
	SS.save_now()
	var tampered: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(save_file()))
	tampered["state"]["gems"] = 999999  # tamper WITHOUT recomputing checksum
	write_envelope(tampered)
	check(SS.load_game() == false, "load_game() false on checksum mismatch")
	check(FileAccess.file_exists(save_file() + ".corrupt"), "tampered save quarantined as .corrupt")
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
