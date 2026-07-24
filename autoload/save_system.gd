extends Node
## SaveSystem — versioned JSON save with checksum + offline earnings. See SPEC §3/§10.

const SAVE_PATH := "user://grand_exhibit_save.json"
const SAVE_VERSION := 2
const _SALT := "grand-exhibit-v1"

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

func save_now() -> void:
	if not GameState.ready_flag:
		return
	GameState.last_seen_unix = ClockGuard.now()
	ClockGuard.note_seen(GameState.last_seen_unix)
	# Normalize through a JSON parse round-trip first: parsing rewrites ints as
	# floats and reorders keys, so stringify(to_save_dict()) != stringify(parsed).
	# Checksumming the normalized form keeps load_game()'s verification stable.
	var state: Dictionary = JSON.parse_string(JSON.stringify(GameState.to_save_dict()))
	var payload: String = JSON.stringify(state)
	var envelope := {
		"version": SAVE_VERSION,
		"saved_at": GameState.last_seen_unix,
		"checksum": _checksum(payload),
		"state": state,
	}
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(envelope))
		f.close()

func has_save() -> bool:
	return FileAccess.file_exists(SAVE_PATH)

func load_game() -> bool:
	if not has_save():
		return false
	var text := FileAccess.get_file_as_string(SAVE_PATH)
	var parsed: Variant = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		return _recover_corrupt("unparseable")
	var env: Dictionary = parsed
	var state: Dictionary = env.get("state", {})
	var payload: String = JSON.stringify(state)
	if str(env.get("checksum", "")) != _checksum(payload):
		return _recover_corrupt("checksum_mismatch")
	var version: int = int(env.get("version", 1))
	if version < SAVE_VERSION:
		state = migrate(state, version)
	GameState.from_save_dict(state)
	return true

func _recover_corrupt(reason: String) -> bool:
	Analytics.log_event("save_corrupt", {"reason": reason})
	var backup := SAVE_PATH + ".bak"
	if FileAccess.file_exists(SAVE_PATH):
		DirAccess.rename_absolute(SAVE_PATH, backup)
	return false

func migrate(state: Dictionary, from_version: int) -> Dictionary:
	# v1 -> v2: expedition/event state keys added; from_save_dict already tolerates
	# missing keys by overlaying onto defaults, so a pass-through is sufficient.
	Analytics.log_event("save_migrated", {"from": from_version, "to": SAVE_VERSION})
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
