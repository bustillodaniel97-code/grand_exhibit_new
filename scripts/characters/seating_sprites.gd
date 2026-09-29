extends RefCounted
## Metadata is shared; each resting visitor owns and releases its action images.
const Motion := preload("res://scripts/characters/motion_sprites.gd")
const FRAMES := 9
const DURATION := .8
const SEAT_HEIGHT := 8.5
static var _manifest: Dictionary = {}

static func _load_manifest() -> void:
	if not _manifest.is_empty():return
	var path := "res://art/npc_seating/seating.json"
	if not FileAccess.file_exists(path):return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not parsed is Dictionary or int(parsed.get("schema",0)) != 1:return
	var count := int(parsed.get("frames",FRAMES))
	if count < FRAMES or count > 65:return
	if not is_equal_approx(float(parsed.get("duration",DURATION)),DURATION):return
	if not is_equal_approx(float(parsed.get("seat_pixels",SEAT_HEIGHT)),SEAT_HEIGHT):return
	_manifest = parsed

static func frame_count() -> int:
	_load_manifest()
	return int(_manifest.get("frames",FRAMES))

static func record_for(identity: Dictionary) -> Dictionary:
	if str(identity.get("role","")) != "visitor":return {}
	var base := Motion.base_for(identity)
	if base.is_empty():return {}
	_load_manifest()
	var record: Dictionary = _manifest.get("sets",{}).get(base,{})
	for field in ["role","age_group","gender","variant"]:
		if record.get(field) != identity.get(field):return {}
	return record

static func frame(identity: Dictionary, index: int) -> Texture2D:
	var count := frame_count()
	if index<0 or index>=count*2:return null
	var frames: Array=record_for(identity).get("front" if index<count else "back",[])
	if frames.size()!=count:return null
	return Motion._texture(frames[index%count],"res://art/npc_seating/")
