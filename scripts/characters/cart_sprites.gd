extends RefCounted
## Original trolley and porter rendered together for correct hand/prop occlusion.
## Cargo is one protected archive case; its contents represent the current batch.
const Motion := preload("res://scripts/characters/motion_sprites.gd")
const Steering := preload("res://scripts/characters/cart_steering_sprites.gd")
const DRAW_RECT := Rect2(-42,-66,84,84)
static var _manifest: Dictionary = {}
static var _cache: Dictionary = {}

static func get_set(identity: Dictionary) -> Dictionary:
	if str(identity.get("role",""))!="porter":return {}
	var steering:=Steering.get_set(identity)
	if not steering.is_empty():return steering
	var base:=Motion.base_for(identity)
	if base.is_empty():return {}
	if _manifest.is_empty():
		var path:="res://art/npc_carts/carts.json"
		if not FileAccess.file_exists(path):return {}
		var parsed: Variant=JSON.parse_string(FileAccess.get_file_as_string(path))
		if not parsed is Dictionary or int(parsed.get("schema",0))!=1:return {}
		_manifest=parsed
	var raw: Dictionary=_manifest.get("sets",{}).get(base,{})
	if raw.is_empty():return {}
	for field in ["role","age_group","gender"]:
		if str(raw.get(field,""))!=str(identity.get(field,"")):return {}
	if int(raw.get("variant",-1))!=int(identity.get("variant",-2)):return {}
	if _cache.has(base):return _cache[base]
	var count := int(_manifest.get("walk_frames",_manifest.get("cart_walk_frames",Motion.WALK_FRAMES)))
	if count<Motion.WALK_FRAMES or count>32:return {}
	var result: Dictionary={"walk_frames":count}
	for cargo in ["0","1"]:
		var state: Dictionary={}
		for view in ["front","back"]:
			var section: Dictionary=raw.get(cargo,{}).get(view,{})
			var idle:=Motion._texture(section.get("idle",{}),"res://art/npc_carts/")
			if idle==null:return {}
			var records: Array=section.get("walk",[])
			if records.size()!=count:return {}
			var frames: Array[Texture2D]=[]
			for rec in records:
				var tex:=Motion._texture(rec,"res://art/npc_carts/")
				if tex==null:return {}
				frames.append(tex)
			state[view]=frames;state["idle_"+view]=idle
		result[cargo]=state
	_cache[base]=result
	return result
