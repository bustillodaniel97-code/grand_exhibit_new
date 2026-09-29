extends RefCounted
## cloud_save.gd — the save in the player's cloud, so progress follows the
## account to a new phone. Backed by Google Play Games saved games (snapshots)
## through the godot-play-game-services singleton that PlatformServices already
## signs in with; driven through call()/connect(), so nothing needs the plugin
## to compile. (Steam Cloud needs no code: Steamworks Auto-Cloud syncs the save
## file. See docs/PLATFORMS.md.)
##
## Rules:
##  · Never overwrite silently. A cloud save that is further along than this
##    phone's is offered to the player (PlatformServices -> Settings); one that
##    is behind is replaced by this phone's.
##  · "Further along" is progress_of(): museums opened, then goal milestones,
##    then reputation. Wall-clock time can't be trusted across devices.
##  · Uploads happen when the app is backgrounded, at most once every
##    MIN_UPLOAD_GAP_MS (Play Games rate-limits snapshot writes).
##  · The payload is the same envelope the local save writes (version, state),
##    gzip-compressed JSON.
##
## tests/meta/test_cloud_save.gd drives it against a fake singleton.

signal loaded(envelope: Dictionary)
signal saved(ok: bool)

const SLOT := "grand_exhibit_main"
const MIN_UPLOAD_GAP_MS := 5 * 60 * 1000
const MAX_PAYLOAD := 32 * 1024 * 1024

var _store: Object = null
var _last_upload_ms := -MIN_UPLOAD_GAP_MS
var _loading := false

func bind(store: Object) -> bool:
	if store == null or not store.has_method("saveGame") or not store.has_method("loadGame"):
		return false
	_store = store
	if store.has_signal("gameSaved") and not store.is_connected("gameSaved", _on_game_saved):
		store.connect("gameSaved", _on_game_saved)
	if store.has_signal("gameLoaded") and not store.is_connected("gameLoaded", _on_game_loaded):
		store.connect("gameLoaded", _on_game_loaded)
	return true

func unbind() -> void:
	if _store != null:
		if _store.has_signal("gameSaved") and _store.is_connected("gameSaved", _on_game_saved):
			_store.disconnect("gameSaved", _on_game_saved)
		if _store.has_signal("gameLoaded") and _store.is_connected("gameLoaded", _on_game_loaded):
			_store.disconnect("gameLoaded", _on_game_loaded)
	_store = null

func is_bound() -> bool:
	return _store != null

# ------------------------------------------------------------------ progress

## A number that only grows as the player gets further: museums opened, then
## goal milestones across them, then reputation (orders of magnitude of XP).
static func progress_of(state: Dictionary) -> int:
	var museums := (state.get("venues_unlocked", []) as Array).size()
	var milestones := 0
	var vs: Dictionary = state.get("venues_state", {})
	for v in vs.values():
		if v is Dictionary:
			milestones += ((v as Dictionary).get("milestones", []) as Array).size()
	var xp: Dictionary = state.get("reputation_xp", {})
	var rep := clampi(int(xp.get("e", 0)) * 10 + int(float(xp.get("m", 0.0))), 0, 999)
	return museums * 1000000 + mini(milestones, 999) * 1000 + rep

## What the player sees when deciding: the museum, how many are open, when.
static func summary(envelope: Dictionary) -> Dictionary:
	var state: Dictionary = envelope.get("state", {})
	return {
		"venue": str(state.get("current_venue", "")),
		"museums": (state.get("venues_unlocked", []) as Array).size(),
		"gems": int(state.get("gems", 0)),
		"saved_at": int(envelope.get("saved_at", 0)),
		"progress": progress_of(state),
	}

# ------------------------------------------------------------------ payload

static func encode(state: Dictionary, version: int, saved_at: int) -> PackedByteArray:
	var env := {"version": version, "saved_at": saved_at, "state": state}
	return JSON.stringify(env).to_utf8_buffer().compress(FileAccess.COMPRESSION_GZIP)

static func decode(bytes: PackedByteArray) -> Dictionary:
	# Not a gzip stream (magic 1f 8b): refuse before the decompressor complains.
	if bytes.size() < 18 or bytes[0] != 0x1f or bytes[1] != 0x8b:
		return {}
	var raw := bytes.decompress_dynamic(MAX_PAYLOAD, FileAccess.COMPRESSION_GZIP)
	if raw.is_empty():
		return {}
	var parsed: Variant = JSON.parse_string(raw.get_string_from_utf8())
	if not parsed is Dictionary or not ((parsed as Dictionary).get("state", null) is Dictionary):
		return {}
	return parsed

# ---------------------------------------------------------------- transport

## Write this phone's save to the cloud. `force` skips the rate limit (a
## player-initiated sync). Returns true when a write was sent.
func upload(state: Dictionary, version: int, saved_at: int, force: bool = false) -> bool:
	if _store == null:
		return false
	var now := Time.get_ticks_msec()
	if not force and now - _last_upload_ms < MIN_UPLOAD_GAP_MS:
		return false
	_last_upload_ms = now
	var s := summary({"state": state, "saved_at": saved_at})
	var desc := str(TranslationServer.translate("%s · %d museums")) % [
		str(TranslationServer.translate(str(DataLoader.get_venue(str(s["venue"])).get("name", s["venue"])))),
		int(s["museums"])]
	var played_ms := maxi(0, saved_at - int(state.get("first_launch_unix", saved_at))) * 1000
	_store.call("saveGame", SLOT, desc, encode(state, version, saved_at), played_ms, int(s["progress"]))
	return true

## Ask for the cloud save; the answer arrives on `loaded` ({} when there is none).
func download() -> void:
	if _store == null:
		return
	_loading = true
	_store.call("loadGame", SLOT, false)

func _on_game_saved(is_saved: bool, _name: String = "", _desc: String = "") -> void:
	saved.emit(is_saved)

func _on_game_loaded(json_data: Variant) -> void:
	_loading = false
	var d: Variant = JSON.parse_string(str(json_data)) if json_data is String else json_data
	if not d is Dictionary:
		loaded.emit({})
		return
	var content: Variant = (d as Dictionary).get("content", null)
	var bytes := PackedByteArray()
	if content is PackedByteArray:
		bytes = content
	elif content is Array:
		for b in (content as Array):
			bytes.append(int(b) & 0xFF)
	elif content is String:
		bytes = Marshalls.base64_to_raw(str(content))
	loaded.emit(decode(bytes))
