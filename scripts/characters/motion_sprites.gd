extends RefCounted
## Original rigged crowd. Transparent margins are restored by AtlasTexture,
## keeping the feet anchor stable without storing large empty image borders.
## Legacy cart/activity banks retain eight phases. Ordinary walking can upgrade
## one identity at a time without retiming those independently authored actions.
const WALK_FRAMES := 8
const MAX_WALK_FRAMES := 32
const DRAW_RECT := Rect2(-24, -60, 48, 72)
const LEGACY_SEATED_RECT := Rect2(-24, -56, 48, 64)
static var _manifest: Dictionary = {}
static var _cache: Dictionary = {}
const DIRECTION_CACHE_LIMIT := 32
static var _direction_cache: Dictionary = {}
static var _direction_lru: Array[String] = []

## Eight grid headings, starting +x and increasing toward +y. Quantizing in
## grid space matches the actual isometric camera, including straight screen
## horizontal/vertical paths. Zero movement keeps the last authoritative heading.
static func direction_index(delta: Vector2, previous: int = 0, hysteresis: float = 0.0) -> int:
 if delta.length_squared()<0.00000001:return previous
 if hysteresis>0.0:
  var previous_angle:=float(posmod(previous,8))*PI/4.0
  var difference:=absf(wrapf(delta.angle()-previous_angle,-PI,PI))
  if difference<=PI/8.0+clampf(hysteresis,0.0,PI/16.0):return posmod(previous,8)
 return posmod(roundi(delta.angle()/(PI/4.0)),8)

## A packet's complete arrays are authoritative. Optional metadata must agree;
## partial upgrades are rejected instead of silently clipping a longer cycle.
static func walk_frame_count(raw: Dictionary) -> int:
 var count: int=raw.get("front",{}).get("walk",[]).size()
 if count<WALK_FRAMES or count>MAX_WALK_FRAMES:return 0
 if raw.get("back",{}).get("walk",[]).size()!=count:return 0
 if int(raw.get("walk_frames",count))!=count:return 0
 return count

static func phase_frame(phase: float, count: int) -> int:
 return clampi(int(fposmod(phase,1.0)*float(count)),0,maxi(count-1,0))

## True-yaw art may be upgraded independently of the older front/back fallback.
## Keeping those fallback views at eight phases avoids doubling their cache.
static func direction_frame_count(raw: Dictionary) -> int:
 var sections: Dictionary=raw.get("directions",{})
 if sections.size()!=8:return 0
 var count: int=sections.get("0",{}).get("walk",[]).size()
 if count<WALK_FRAMES or count>MAX_WALK_FRAMES:return 0
 if int(raw.get("direction_walk_frames",count))!=count:return 0
 for i in 8:
  if sections.get(str(i),{}).get("walk",[]).size()!=count:return 0
 return count

## Extra headings are optional during migration; reject partial identity banks.
## Metadata is checked together, while decoded textures load only when needed.
static func _valid_directions(raw: Dictionary) -> bool:
 var count:=direction_frame_count(raw)
 if count==0:return false
 var sections: Dictionary=raw.get("directions",{})
 if sections.size()!=8:return false
 for i in range(8):
  var section: Dictionary=sections.get(str(i),{})
  var records: Array=section.get("walk",[]).duplicate()
  if records.size()!=count:return false
  records.append(section.get("idle",{}))
  for rec in records:
   if not rec is Dictionary:return false
   var filename:=str(rec.get("file",""))
   if filename!=filename.get_file() or not filename.ends_with(".png"):return false
   if not FileAccess.file_exists("res://art/npc_motion/"+filename) and not ResourceLoader.exists("res://art/npc_motion/"+filename):return false
   var canvas: Array=rec.get("canvas",[])
   if canvas.size()!=2 or rec.get("offset",[]).size()!=2:return false
   if int(canvas[0])!=192 or int(canvas[1])!=288:return false
 return true

static func direction_set(identity: Dictionary, heading: int) -> Dictionary:
 var packet:=get_set(identity)
 if not packet.has("directions"):return {}
 var key:=base_for(identity)+":"+str(posmod(heading,8))
 if _direction_cache.has(key):
  _direction_lru.erase(key);_direction_lru.append(key)
  return _direction_cache[key]
 var raw: Dictionary=packet.directions[str(posmod(heading,8))]
 var idle:=_texture(raw.get("idle",{}))
 if idle==null:return {}
 var frames: Array[Texture2D]=[]
 for rec in raw.walk:
  var tex:=_texture(rec)
  if tex==null:return {}
  frames.append(tex)
 var result:={"idle":idle,"walk":frames}
 if raw.get("idle_hand",[]).size()==2 and raw.get("walk_hands",[]).size()==frames.size():
  result.idle_hand=Vector2(float(raw.idle_hand[0]),float(raw.idle_hand[1]))
  var hands: Array[Vector2]=[]
  for point in raw.walk_hands:
   if point.size()!=2:return {}
   hands.append(Vector2(float(point[0]),float(point[1])))
  result.walk_hands=hands
 _direction_cache[key]=result
 _direction_lru.append(key)
 while _direction_lru.size()>DIRECTION_CACHE_LIMIT:
  _direction_cache.erase(_direction_lru.pop_front())
 # Characters retain their current packet independently of cache eviction.
 return result

static func seated_draw_rect(texture: Texture2D) -> Rect2:
 # New seated renders retain the walk canvas so shoes below the old eight-pixel
 # baseline stay visible. AtlasTexture.get_size restores the complete canvas.
 return DRAW_RECT if texture != null and texture.get_size() == Vector2(192,288) else LEGACY_SEATED_RECT

static func base_for(identity: Dictionary) -> String:
 var role:=str(identity.get("role",""))
 var age:=str(identity.get("age_group",""))
 var gender:=str(identity.get("gender",""))
 var variant:=int(identity.get("variant",-1))
 if variant<0 or variant>2:return ""
 if role=="visitor":
  if age not in ["child","young_adult","middle_aged","elder"] or gender not in ["male","female"]:return ""
  return "visitor_%s_%s%s" % [age,gender,"" if variant==0 else "-v%d"%variant]
 if role not in ["employee","ticket","docent","promotions","porter"] or age not in ["young_adult","middle_aged","elder"]:return ""
 return "staff-%s-%d" % ["docent" if role=="employee" else role,variant]

static func _texture(record: Dictionary, folder: String = "res://art/npc_motion/") -> Texture2D:
 var filename:=str(record.get("file",""))
 if filename!=filename.get_file() or not filename.ends_with(".png"):return null
 var path:=folder+filename
 var source: Texture2D
 if ResourceLoader.exists(path):source=load(path) as Texture2D
 elif FileAccess.file_exists(path):
  var im:=Image.load_from_file(path)
  if im==null or im.is_empty():return null
  im.generate_mipmaps();source=ImageTexture.create_from_image(im)
 if source==null:return null
 var canvas: Array=record.get("canvas",[])
 var offset: Array=record.get("offset",[])
 if canvas.size()!=2 or offset.size()!=2:return null
 var full:=Vector2(float(canvas[0]),float(canvas[1]));var at:=Vector2(float(offset[0]),float(offset[1]))
 if at.x<0 or at.y<0 or (at+source.get_size()).x>full.x or (at+source.get_size()).y>full.y:return null
 var result:=AtlasTexture.new();result.atlas=source;result.region=Rect2(Vector2.ZERO,source.get_size())
 result.margin=Rect2(at,full-source.get_size());result.filter_clip=true
 return result

static func get_set(identity: Dictionary) -> Dictionary:
 var base:=base_for(identity)
 if base.is_empty():return {}
 if _manifest.is_empty():
  if not FileAccess.file_exists("res://art/npc_motion/motion.json"):return {}
  var parsed: Variant=JSON.parse_string(FileAccess.get_file_as_string("res://art/npc_motion/motion.json"))
  if not parsed is Dictionary or int(parsed.get("schema",0))!=1:return {}
  _manifest=parsed
 var raw: Dictionary=_manifest.get("sets",{}).get(base,{})
 if raw.is_empty():return {}
 var count:=walk_frame_count(raw)
 if count==0:return {}
 var want_role:=str(identity.get("role",""))
 if want_role=="employee":want_role="docent"
 if str(raw.get("role",""))!=want_role or str(raw.get("age_group",""))!=str(identity.get("age_group","")) or str(raw.get("gender",""))!=str(identity.get("gender","")):return {}
 if _cache.has(base):return _cache[base]
 var result:={"walk_frames":count,"stride_grid":float(raw.get("stride_grid",.63)),
  "cart_stride_grid":float(raw.get("cart_stride_grid",raw.get("stride_grid",.63))),
  "seating_foot_grid":float(raw.get("seating_foot_grid",float(raw.get("stride_grid",.63))*.30))}
 for view in ["front","back"]:
  var section: Dictionary=raw.get(view,{})
  var idle:=_texture(section.get("idle",{}))
  if idle==null:return {}
  var records: Array=section.get("walk",[])
  if records.size()!=count:return {}
  var frames: Array[Texture2D]=[]
  for rec in records:
   var tex:=_texture(rec)
   if tex==null:return {}
   frames.append(tex)
  result[view]=frames;result["idle_"+view]=idle
 if want_role=="visitor":
  var seated:=_texture(raw.get("seated",{}))
  if seated==null:return {}
  result.seated=seated
 if _valid_directions(raw):
  result.directions=raw.directions
  result.direction_walk_frames=direction_frame_count(raw)
 _cache[base]=result
 return result
