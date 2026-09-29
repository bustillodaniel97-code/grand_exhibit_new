extends Node
## SaveSystem — versioned JSON save with checksum + offline earnings. See SPEC §3/§10.

const SAVE_BASENAME := "grand_exhibit_save.json"
const TEST_SUBDIR := "test_run"
const SAVE_VERSION := 6
const _SALT := "grand-exhibit-v1"

static var _save_path_cache: String = ""

## Where the save lives.
##
## The suite deletes this file and deliberately corrupts it. On a developer box
## user:// is the REAL player profile, so the single-test command documented in
## the handoff — `godot --headless -s tests/core/test_save.gd` — used to eat
## live progress with no warning. Two independent signals redirect the write
## into a throwaway subdirectory:
##
##   · GRAND_EXHIBIT_TEST_RUN, exported by tools/run_tests.sh;
##   · the main loop being a script under res://tests/, which also catches a
##     hand-run single test where nobody remembered to set the env var.
##
## Belt and braces on purpose. The failure this guards against is silent and
## unrecoverable, and the guard costs one string compare per process.
static func save_path() -> String:
	if _save_path_cache.is_empty():
		# Do not memoise before the main loop exists, or an early call would
		# cache the non-test answer and defeat the res://tests/ signal.
		if Engine.get_main_loop() == null:
			return _resolve_save_path()
		_save_path_cache = _resolve_save_path()
	return _save_path_cache

static func _resolve_save_path() -> String:
	if _in_test_context():
		DirAccess.make_dir_recursive_absolute("user://" + TEST_SUBDIR)
		return "user://%s/%s" % [TEST_SUBDIR, SAVE_BASENAME]
	return "user://" + SAVE_BASENAME

static func _in_test_context() -> bool:
	if OS.has_environment("GRAND_EXHIBIT_TEST_RUN"):
		return true
	var loop: MainLoop = Engine.get_main_loop()
	if loop == null:
		return false
	var scr: Script = loop.get_script() as Script
	return scr != null and scr.resource_path.begins_with("res://tests/")

var autosave_interval_sec := 20
var _elapsed: float = 0.0

func _process(delta: float) -> void:
	if not GameState.ready_flag:
		return
	_elapsed += delta
	if _elapsed >= autosave_interval_sec:
		_elapsed = 0.0
		save_now()

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_APPLICATION_PAUSED:
		if GameState.ready_flag:
			save_now()

func _checksum(payload: String) -> String:
	return (payload + _SALT).sha256_text()

signal save_failed(stage: String)
var last_save_error: String = ""

## Success means a complete, re-read and verified file replaced the primary.
## The previous valid primary remains in .bak. Temporary files are never loaded.
func save_now() -> bool:
	if not GameState.ready_flag:
		return _write_failed("state_not_ready")
	GameState.last_seen_unix = ClockGuard.now()
	ClockGuard.note_seen(GameState.last_seen_unix)
	var state: Dictionary = JSON.parse_string(JSON.stringify(GameState.to_save_dict()))
	var envelope := {
		"version": SAVE_VERSION, "saved_at": GameState.last_seen_unix,
		"checksum": _checksum(JSON.stringify(state)), "state": state,
	}
	var path := save_path()
	var temp := path + ".tmp"
	var f := FileAccess.open(temp, FileAccess.WRITE)
	if f == null:
		return _write_failed("open_temp")
	f.store_string(JSON.stringify(envelope))
	f.flush()
	var write_error := f.get_error()
	f.close()
	if write_error != OK or _read_envelope(temp).is_empty():
		return _write_failed("verify_temp")
	# Do not replace a known-good backup with a corrupt primary.
	if not _read_envelope(path).is_empty():
		var backup_temp := path + ".bak.tmp"
		if DirAccess.copy_absolute(path, backup_temp) != OK:
			return _write_failed("copy_backup")
		if _read_envelope(backup_temp).is_empty():
			return _write_failed("verify_backup")
		if DirAccess.rename_absolute(backup_temp, path + ".bak") != OK:
			return _write_failed("replace_backup")
	# Same-directory rename keeps the old primary intact until replacement.
	if DirAccess.rename_absolute(temp, path) != OK:
		return _write_failed("replace_primary")
	last_save_error = ""
	return true

func _write_failed(stage: String) -> bool:
	last_save_error = stage
	Analytics.log_event("save_write_failed", {"stage": stage})
	save_failed.emit(stage)
	return false

func _read_envelope(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not parsed is Dictionary:
		return {}
	var state: Variant = parsed.get("state", null)
	if not state is Dictionary:
		return {}
	if str(parsed.get("checksum", "")) != _checksum(JSON.stringify(state)):
		return {}
	return parsed

func has_save() -> bool:
	return FileAccess.file_exists(save_path()) or FileAccess.file_exists(save_path() + ".bak")

func load_game() -> bool:
	var path := save_path()
	var env := _read_envelope(path)
	if env.is_empty():
		if FileAccess.file_exists(path):
			Analytics.log_event("save_corrupt", {})
			# Quarantine is separate from the last known-good generation.
			DirAccess.rename_absolute(path, path + ".corrupt")
		env = _read_envelope(path + ".bak")
		if env.is_empty():
			return false
		Analytics.log_event("save_backup_recovered", {})
	var version: int = int(env.get("version", 1))
	if version > SAVE_VERSION:
		return false
	var state: Dictionary = env["state"]
	if version < SAVE_VERSION:
		state = migrate(state, version)
	GameState.from_save_dict(state)
	return true

func migrate(state: Dictionary, from_version: int) -> Dictionary:
	# v1 -> v2: expedition/event state keys added; from_save_dict already tolerates
	# missing keys by overlaying onto defaults, so a pass-through is sufficient.
	if from_version < 3:
		state = _migrate_v2_to_v3(state)
	if from_version < 4:
		state = _migrate_v3_to_v4(state)
	if from_version < 5:
		state = _migrate_v4_to_v5(state)
	if from_version < 6:
		state = _migrate_v5_to_v6(state)
	Analytics.log_event("save_migrated", {"from": from_version, "to": SAVE_VERSION})
	return state

## v5 -> v6: decor purchase became per museum.
##
## v5 briefly made a design a global entitlement. That turned every museum after
## the first into a reskin with the same decor already paid for, so buying is now
## local to a building — the genre convention, and what makes a new venue read as
## a new setting. Nothing is confiscated: whatever is STANDING in a venue was
## obviously bought there, so it is recorded as such and stays free to restore
## from that venue's storage. decor_owned survives as the cross-museum record
## that set bonuses are computed over.
func _migrate_v5_to_v6(state: Dictionary) -> Dictionary:
	var venues: Dictionary = state.get("venues_state", {})
	for vid in venues.keys():
		if typeof(venues[vid]) != TYPE_DICTIONARY:
			continue
		var vs: Dictionary = venues[vid]
		if vs.has("decor_bought"):
			continue
		var bought: Array = []
		var placed: Variant = vs.get("decor", {})
		if typeof(placed) == TYPE_DICTIONARY:
			for did in (placed as Dictionary).values():
				if str(did) != "" and str(did) not in bought:
					bought.append(str(did))
		vs["decor_bought"] = bought
	return state

## v4 -> v5: decor ownership became global.
##
## Before v5 a design was owned only where it stood, so opening the next museum
## showed a bare floor and the shop asking full price again for pieces already
## paid for. Players read that as "my decor did not spawn".
##
## The blueprint list is DERIVED from what the save already contains: every
## design standing on any floor was, by definition, bought. Nothing is granted
## that was not earned and nothing is taken away — placements are left exactly
## where they are, and the collection is simply written down for the first time.
func _migrate_v4_to_v5(state: Dictionary) -> Dictionary:
	if state.has("decor_owned"):
		return state
	var owned: Array = []
	var venues: Dictionary = state.get("venues_state", {})
	for vid in venues.keys():
		if typeof(venues[vid]) != TYPE_DICTIONARY:
			continue
		var placed: Variant = (venues[vid] as Dictionary).get("decor", {})
		if typeof(placed) != TYPE_DICTIONARY:
			continue
		for did in (placed as Dictionary).values():
			if str(did) != "" and str(did) not in owned:
				owned.append(str(did))
	state["decor_owned"] = owned
	return state

## v3 -> v4: the upgrade atom became the ITEM. Each department's integer staff
## count becomes a container of that many level-1 items, each with an empty
## pending pile. Progress is preserved exactly — N staff were N interchangeable
## units, and N level-1 items produce identical throughput by construction.
func _migrate_v3_to_v4(state: Dictionary) -> Dictionary:
	var venues: Dictionary = state.get("venues_state", {})
	for vid in venues.keys():
		var depts: Dictionary = venues[vid].get("depts", {})
		for dept_id in depts.keys():
			var d: Dictionary = depts[dept_id]
			if d.has("items"):
				continue
			var items: Array = []
			for _i in int(d.get("staff", 1)):
				items.append({"lv": 1, "pending": {"m": 0.0, "e": 0}})
			d["items"] = items
			d["staff"] = items.size()
	return state

## v2 -> v3: the museum ladder became explicitly one-way, recorded in
## GameState.venues_closed. A v2 save has no such list, but it does have the
## facts to rebuild it exactly: every unlocked venue sitting BEFORE the current
## one in venue order is a building the player already graduated out of. Derived
## once here rather than left derived forever, so a later reorder of venues.json
## cannot re-open a closed museum.
func _migrate_v2_to_v3(state: Dictionary) -> Dictionary:
	if state.has("venues_closed"):
		return state
	var order: Array = DataLoader.venue_order()
	var current_idx: int = order.find(str(state.get("current_venue", "")))
	var closed: Array = []
	if current_idx > 0:
		for vid in state.get("venues_unlocked", []):
			var idx: int = order.find(str(vid))
			if idx >= 0 and idx < current_idx:
				closed.append(str(vid))
	state["venues_closed"] = closed
	return state

## Called once after load (or new game). Returns {amount: BigNumber, seconds: int, capped: bool}.
func compute_offline_and_apply() -> Dictionary:
	var now_unix: int = ClockGuard.now()
	var last: int = GameState.last_seen_unix
	var cfg: Dictionary = DataLoader.core.get("economy", {})
	var cap: int = int(float(cfg.get("offline_cap_hours", 4)) * 3600.0)
	var seconds: int = ClockGuard.validate_elapsed(last, now_unix, cap)
	var capped: bool = seconds >= cap and (now_unix - last) > cap
	var amount: BigNumber = BigNumber.zero()
	if seconds > 30:  # ignore micro-absences
		var rate: BigNumber = Economy.current_cash_per_second()
		var eff: float = float(cfg.get("offline_efficiency", 1.0))
		amount = rate.scale(float(seconds) * eff)
		GameState.add_cash(amount)
		EventBus.offline_earnings_ready.emit(amount, seconds, capped)
	GameState.last_seen_unix = now_unix
	ClockGuard.note_seen(now_unix)
	return {"amount": amount, "seconds": seconds, "capped": capped}
