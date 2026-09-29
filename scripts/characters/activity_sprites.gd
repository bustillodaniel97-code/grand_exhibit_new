extends RefCounted
## Only active feeders own textures. Hand-only users load metadata, not frames.
const Motion := preload("res://scripts/characters/motion_sprites.gd")
const FRAMES := 24
const DURATION := 3.0
const RELEASE_FRAME := 9
const RELEASE_TIME := 1.125
static var _manifest: Dictionary = {}

static func _load_manifest() -> void:
	if not _manifest.is_empty():return
	var path := "res://art/npc_activities/activities.json"
	if not FileAccess.file_exists(path):return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not parsed is Dictionary or int(parsed.get("schema",0)) != 1:return
	var count := int(parsed.get("frames",FRAMES))
	var release := int(parsed.get("release_frame",RELEASE_FRAME))
	if count < FRAMES or count > 96 or release < 0 or release >= count:return
	# Art may gain samples; the simulation's release time and cycle stay fixed.
	if not is_equal_approx(float(parsed.get("duration",DURATION)),DURATION):return
	if not is_equal_approx(float(release)/float(count)*DURATION,RELEASE_TIME):return
	_manifest = parsed

static func frame_count() -> int:
	_load_manifest()
	return int(_manifest.get("frames",FRAMES))

static func release_frame() -> int:
	_load_manifest()
	return int(_manifest.get("release_frame",RELEASE_FRAME))

static func record_for(identity: Dictionary) -> Dictionary:
	if str(identity.get("role","")) != "visitor":return {}
	var base := Motion.base_for(identity)
	if base.is_empty():return {}
	_load_manifest()
	var record: Dictionary = _manifest.get("sets",{}).get(base,{})
	for field in ["role","age_group","gender","variant"]:
		if record.get(field) != identity.get(field):return {}
	return record

static func feeding_frames(identity: Dictionary) -> Array[Texture2D]:
	var records: Array = record_for(identity).get("feed",[])
	var textures: Array[Texture2D] = []
	if records.size() != frame_count():return textures
	for record in records:
		var texture := Motion._texture(record,"res://art/npc_activities/")
		if texture == null:return []
		textures.append(texture)
	return textures

static func feeding_frame(identity: Dictionary, index: int) -> Texture2D:
	var records: Array = record_for(identity).get("feed",[])
	if records.size()!=frame_count() or index<0 or index>=records.size():return null
	return Motion._texture(records[index],"res://art/npc_activities/")

static func hand(identity: Dictionary, back: bool, walking: bool, frame: int, feeding: bool = false) -> Vector2:
	var record := record_for(identity)
	if record.is_empty():return Vector2(0,-20)
	var p: Array
	if feeding:
		if record.get("feed",[]).size()!=frame_count():return Vector2(0,-20)
		p = record.feed[clampi(frame,0,frame_count()-1)].hand
	else:
		var view: Dictionary = record["back" if back else "front"]
		p = view.walk_hands[posmod(frame,8)] if walking else view.idle_hand
	return Vector2(float(p[0]),float(p[1]))
