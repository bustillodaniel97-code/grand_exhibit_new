extends RefCounted
## Four real views and two-step turning arcs, rendered together with the cart.
const Motion := preload("res://scripts/characters/motion_sprites.gd")
const DIRECTIONS := [Vector2.DOWN,Vector2.RIGHT,Vector2.UP,Vector2.LEFT]
const DRAW_RECT := Rect2(-48,-66,96,96)
const TURN_INTERVALS := 8
const ARC_CACHE_LIMIT := 12
const FOLDER := "res://art/npc_cart_steering/"
static var _manifest: Dictionary = {}
static var _sets: Dictionary = {}
static var _arcs: Dictionary = {}
static var _arc_order: Array[String] = []

static func _load_manifest() -> void:
	if not _manifest.is_empty():return
	if not FileAccess.file_exists(FOLDER+"steering.json"):return
	var parsed: Variant=JSON.parse_string(FileAccess.get_file_as_string(FOLDER+"steering.json"))
	if not parsed is Dictionary or int(parsed.get("schema",0))!=1:return
	var intervals := int(parsed.get("turn_intervals",0))
	var frames := int(parsed.get("walk_frames",Motion.WALK_FRAMES))
	if intervals<TURN_INTERVALS or intervals>32 or frames<Motion.WALK_FRAMES or frames>32:return
	_manifest=parsed

static func turn_intervals() -> int:
	_load_manifest()
	return int(_manifest.get("turn_intervals",TURN_INTERVALS))

static func walk_frame_count() -> int:
	_load_manifest()
	return int(_manifest.get("walk_frames",Motion.WALK_FRAMES))

static func _raw(identity: Dictionary) -> Dictionary:
	if str(identity.get("role",""))!="porter":return {}
	_load_manifest()
	var raw: Dictionary=_manifest.get("sets",{}).get(Motion.base_for(identity),{})
	for field in ["role","age_group","gender"]:
		if str(raw.get(field,""))!=str(identity.get(field,"")):return {}
	if int(raw.get("variant",-1))!=int(identity.get("variant",-2)):return {}
	return raw

static func get_set(identity: Dictionary) -> Dictionary:
	var raw:=_raw(identity)
	if raw.is_empty():return {}
	var base:=Motion.base_for(identity)
	if _sets.has(base):return _sets[base]
	var count := walk_frame_count()
	var result:={"steering":true,"walk_frames":count,"turn_intervals":turn_intervals()}
	for cargo in ["0","1"]:
		var state: Dictionary={}
		for direction in 4:
			var section: Dictionary=raw.get(cargo,{}).get(str(direction),{})
			var idle:=Motion._texture(section.get("idle",{}),FOLDER)
			var records: Array=section.get("walk",[])
			if idle==null or records.size()!=count:return {}
			var frames: Array[Texture2D]=[]
			for rec in records:
				var tex:=Motion._texture(rec,FOLDER)
				if tex==null:return {}
				frames.append(tex)
			state[str(direction)]={"idle":idle,"walk":frames}
		result[cargo]=state
	_sets[base]=result
	return result

static func direction_index(heading: Vector2) -> int:
	# Model yaw 0 faces grid +y; model positive yaw turns toward grid +x.
	return posmod(roundi((PI*.5-heading.angle())/(PI*.5)),4)

static func turn_frames(identity: Dictionary,start: int,direction: int,loaded: bool) -> Array:
	var raw:=_raw(identity)
	if raw.is_empty() or start<0 or start>3 or direction not in [-1,1]:return []
	var key:="%s:%d:%d:%d"%[Motion.base_for(identity),start,direction,int(loaded)]
	if _arcs.has(key):
		_arc_order.erase(key);_arc_order.append(key);return _arcs[key]
	var records: Array=raw.get("1" if loaded else "0",{}).get(str(start),{}).get(str(direction),[])
	if records.size()!=turn_intervals()-1:return []
	var frames: Array[Texture2D]=[]
	for rec in records:
		var tex:=Motion._texture(rec,FOLDER)
		if tex==null:return []
		frames.append(tex)
	_arcs[key]=frames;_arc_order.append(key)
	while _arc_order.size()>ARC_CACHE_LIMIT:_arcs.erase(_arc_order.pop_front())
	return frames
