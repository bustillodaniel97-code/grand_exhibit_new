extends RefCounted
## Blender render bridge: transparent art retains grid anchors and Y sorting.
const Iso := preload("res://scenes/venue/floor/iso.gd")
static var _textures: Dictionary = {}
const KITS := ["whispering_pines", "copper_kettle", "grand_river", "sunspire", "cloudrest", "aurora_world", "celestial_conservatory", "ironwood_citadel", "pelagic_crown", "chronos_spire", "empyrean_palace", "infinite_museum"]

## Do not retain every previous museum's art and animation for an entire
## campaign. Live draw callbacks keep their own references until retired.
static func retain_kit(venue: String) -> void:
 var prefix := "res://art/environment/%s-" % venue
 for path in _textures.keys():
  if not str(path).begins_with(prefix):_textures.erase(path)

static func painter(venue: String, kind: String, spec: Dictionary, fallback: Callable) -> Callable:
 if venue in ["celestial_conservatory","ironwood_citadel","pelagic_crown","chronos_spire","empyrean_palace","infinite_museum"]:return _collection_painter(venue,kind,spec,fallback)
 if kind not in ["planter", "bench", "cafe_table", "desk", "shelf", "rack", "crate", "kiosk", "case", "vitrine", "hanging", "counter_body", "info_body", "skeleton", "hung_skeleton", "statue", "plinth"] or venue not in KITS:
  return fallback
 if kind in ["rack", "crate", "kiosk"] and venue != "aurora_world":return fallback
 if venue not in ["whispering_pines", "copper_kettle", "sunspire", "cloudrest", "grand_river", "aurora_world"] and kind != "planter":return fallback
 if kind in ["statue", "plinth"] and venue not in ["sunspire", "aurora_world", "grand_river", "cloudrest"]:return fallback
 if venue == "cloudrest" and kind not in ["planter", "bench", "desk", "shelf", "case", "vitrine", "hanging", "counter_body", "statue"]:return fallback
 if venue == "grand_river" and kind not in ["planter", "bench", "desk", "shelf", "counter_body", "info_body", "statue", "case", "vitrine"]:return fallback
 if venue == "sunspire" and kind not in ["planter", "bench", "counter_body", "case", "vitrine", "statue", "plinth", "desk"]:return fallback
 if venue == "aurora_world" and kind not in ["planter", "plinth", "bench", "case", "vitrine", "hanging", "counter_body", "desk", "shelf", "rack", "crate", "kiosk", "statue"]:return fallback
 var path := "res://art/environment/%s-planter.png" % venue
 var pixels := 320.0
 var ortho := 4.0
 var target_z := .7
 var offset := Vector2.ZERO
 var shadow_size := Vector2(.60,.60)
 if venue == "aurora_world" and kind in ["desk", "shelf", "rack", "crate", "kiosk"]:
  # Rendered to the existing primitive footprint and height. Unauthored shapes
  # retain the procedural renderer instead of stretching a mismatched sprite.
  var dimensions := {"desk":Vector2(1.9,.6), "shelf":Vector2(2.0,.5),
   "rack":Vector2(1.2,.5), "crate":Vector2(.8,.6), "kiosk":Vector2(.34,.34)}
  var heights := {"desk":18.0, "shelf":30.0, "kiosk":30.0}
  var expected: Vector2 = dimensions[kind]
  var raw: Variant = spec.get("size",expected)
  var actual: Vector2 = raw if raw is Vector2 else Vector2(float(raw[0]),float(raw[1]))
  if not actual.is_equal_approx(expected):return fallback
  if str(spec.get("axis","x")) != "x" or not is_zero_approx(float(spec.get("rot",0))) or str(spec.get("mirror","")) != "":return fallback
  if heights.has(kind) and not is_equal_approx(float(spec.get("height",heights[kind])),float(heights[kind])):return fallback
  path = "res://art/environment/aurora_world-%s.png" % kind
  offset = expected*.5
  shadow_size = expected
 if venue == "cloudrest" and kind == "statue":
  if str(spec.get("id",""))!="cairn":return fallback
  path = "res://art/environment/cloudrest-cairn.png"
  shadow_size = Vector2(1.2,1.0)
  offset = shadow_size*.5
 if venue == "grand_river" and kind == "statue":
  if str(spec.get("id",""))!="orrery":return fallback
  path = "res://art/environment/grand_river-orrery.png"
  shadow_size = Vector2(1.4,1.2)
  offset = shadow_size*.5
 if venue == "aurora_world" and kind == "statue":
  var artifact := str(spec.get("id",""))
  if artifact not in ["voyager", "monolith", "telescope"]:return fallback
  path = "res://art/environment/aurora_world-%s.png" % artifact
  shadow_size = {"voyager":Vector2(1.4,1.2), "monolith":Vector2(1.2,1.0), "telescope":Vector2(1.6,1.2)}[artifact]
  offset = shadow_size*.5
 if venue == "aurora_world" and kind == "plinth":
  if str(spec.get("id", "")) != "orrery":return fallback
  path = "res://art/environment/aurora_world-orrery.png"
  offset = Vector2(.7,.7)
  shadow_size = Vector2(1.4,1.4)
 if kind == "cafe_table":
  if venue != "copper_kettle" or str(spec.get("seating", "four")) != "pair":return fallback
  path = "res://art/environment/copper_kettle-cafe-pair.png"
  shadow_size = Vector2(1.4,.9)
 if kind == "shelf" and venue != "aurora_world":
  if venue not in ["grand_river", "cloudrest"]:return fallback
  var raw: Variant = spec.get("size",Vector2(2.2,.5))
  var footprint: Vector2 = raw if raw is Vector2 else Vector2(float(raw[0]),float(raw[1]))
  if not (is_equal_approx(footprint.x,2.2) or is_equal_approx(footprint.x,3.8)) or not is_equal_approx(footprint.y,.5) or not is_equal_approx(float(spec.get("height",30)),30):return fallback
  if venue=="cloudrest" and not is_equal_approx(footprint.x,2.2):return fallback
  path = "res://art/environment/%s-shelf-%d.png" % [venue,roundi(footprint.x*100)]
  offset = footprint*.5
  shadow_size = footprint
 if kind == "hanging":
  var bird := str(spec.get("id",""))
  if venue == "aurora_world" and bird == "armillary":
   path = "res://art/environment/aurora_world-armillary.png"
   shadow_size = Vector2(.9,.9)
  elif venue == "cloudrest" and bird in ["condor", "kestrel"]:
   path = "res://art/environment/cloudrest-%s.png" % bird
   shadow_size = Vector2(2.5,.65) if bird == "condor" else Vector2(1.8,.5)
  else:return fallback
 if kind == "bench":
  if not is_zero_approx(float(spec.get("rot",0))) or str(spec.get("mirror","")) != "":return fallback
  var length := float(spec.get("len",1.5))
  var axis := str(spec.get("axis","x"))
  path = "res://art/environment/%s-bench-%d-%s-%d.png" % [venue,roundi(length*100),axis,int(bool(spec.get("flip",false)))]
  offset = Vector2(length*.5,.22) if axis == "x" else Vector2(.22,length*.5)
  shadow_size = Vector2(length,.50) if axis == "x" else Vector2(.50,length)
  if not ResourceLoader.exists(path) and not FileAccess.file_exists(path):return fallback
 if kind in ["case", "vitrine"]:
  var artifact := str(spec.get("id",""))
  if venue == "aurora_world":
   if not ((kind == "case" and artifact == "moonrock") or (kind == "vitrine" and artifact == "meteorite")):return fallback
   shadow_size = Vector2(2.0,1.0) if artifact == "moonrock" else Vector2(1.4,1.0)
  elif venue == "sunspire":
   if not ((kind == "case" and artifact == "scarabs") or (kind == "vitrine" and artifact == "sunmask")):return fallback
   shadow_size = Vector2(2.2,1.0) if artifact == "scarabs" else Vector2(1.4,1.0)
  elif venue == "grand_river":
   if not ((kind=="case" and artifact=="globe") or (kind=="vitrine" and artifact=="folio")):return fallback
   shadow_size = Vector2(1.2,1.0) if artifact=="globe" else Vector2(1.6,.9)
  elif venue == "cloudrest":
   if not ((kind == "case" and artifact == "clutch") or (kind == "vitrine" and artifact == "plumage")):return fallback
   shadow_size = Vector2(1.8,1.0) if artifact == "clutch" else Vector2(1.4,1.0)
  else:return fallback
  path = "res://art/environment/%s-%s.png" % [venue,artifact]
  offset = shadow_size*.5
 if kind == "desk" and venue != "aurora_world":
  if venue not in ["cloudrest", "grand_river", "whispering_pines", "copper_kettle", "sunspire"]:return fallback
  var footprint := Vector2(1.9,.6)
  var requested: Variant = spec.get("size",footprint)
  var actual: Vector2 = requested if requested is Vector2 else Vector2(float(requested[0]),float(requested[1]))
  if not is_equal_approx(float(spec.get("height",18)),18.0):return fallback
  if venue in ["whispering_pines", "copper_kettle", "sunspire"]:
   if not actual.is_equal_approx(Vector2(1.3,.6)):return fallback
   footprint = actual
   path = "res://art/environment/%s-desk-130.png" % venue
  elif venue == "grand_river":
   # Athenaeum reading desks are authored at 1.3x0.7 and 1.6x0.7; one render per width.
   if not is_equal_approx(actual.y,.7) or not (is_equal_approx(actual.x,1.3) or is_equal_approx(actual.x,1.6)):return fallback
   footprint = actual
   path = "res://art/environment/grand_river-desk-%d.png" % roundi(actual.x*100)
  else:
   if not actual.is_equal_approx(footprint):return fallback
   path = "res://art/environment/cloudrest-desk.png"
  offset = footprint*.5
  shadow_size = footprint
 if kind == "info_body":
  if venue not in ["whispering_pines", "copper_kettle", "grand_river"]:return fallback
  var expected: Vector2 = {"whispering_pines":Vector2(1.9,.7),"copper_kettle":Vector2(2,.7),"grand_river":Vector2(2,.65)}[venue]
  var requested: Variant = spec.get("size",expected)
  var footprint: Vector2 = requested if requested is Vector2 else Vector2(float(requested[0]),float(requested[1]))
  if not footprint.is_equal_approx(expected) or not is_equal_approx(float(spec.get("height",20)),20.0):return fallback
  path = "res://art/environment/%s-info_body.png" % venue
  shadow_size = footprint
  offset = shadow_size*.5
 if kind == "counter_body":
  var size_value: Variant = spec.get("size",Vector2(1.7,.6))
  var footprint: Vector2 = size_value if size_value is Vector2 else Vector2(float(size_value[0]),float(size_value[1]))
  var expected_width: float = {"whispering_pines":1.55,"grand_river":1.8}.get(venue,1.7)
  if not footprint.is_equal_approx(Vector2(expected_width,.6)) or not is_equal_approx(float(spec.get("height",21)),21.0):return fallback
  path = "res://art/environment/%s-counter_body.png" % venue
  var turn := posmod(roundi(float(spec.get("rot",0))/90.0),4)
  if turn!=0:
   path = "res://art/environment/%s-counter_body-%s.png" % [venue,{1:"west",2:"north",3:"east"}[turn]]
   if not ResourceLoader.exists(path) and not FileAccess.file_exists(path):return fallback
  offset = footprint*.5
  shadow_size = footprint
 if kind == "skeleton":
  if venue != "whispering_pines" or str(spec.get("id","")) != "dino":return fallback
  path = "res://art/environment/whispering_pines-skeleton.png"
  offset = Vector2(1.6,.6)
  shadow_size = Vector2(3.2,1.2)
  pixels = 512.0
  ortho = 5.6
  target_z = 1.0
 if kind == "hung_skeleton":
  if venue != "copper_kettle" or str(spec.get("id","")) != "whale":return fallback
  path = "res://art/environment/copper_kettle-hung_skeleton.png"
  shadow_size = Vector2(3.8,1.1)
  pixels = 512.0
  ortho = 6.4
  target_z = 1.0
 if venue == "sunspire" and kind in ["statue", "plinth"]:
  var artifact := str(spec.get("id",""))
  if not ((kind == "statue" and artifact in ["colossus", "lion"]) or (kind == "plinth" and artifact in ["obelisk", "solar_dial"])):return fallback
  path = "res://art/environment/sunspire-%s.png" % artifact
  offset = Vector2(.8,.6) if artifact == "colossus" else Vector2(.5,.5)
  shadow_size = Vector2(1.6,1.2) if artifact == "colossus" else Vector2.ONE
  pixels = 512.0
  ortho = 4.8
  target_z = 1.2
  if artifact == "lion":
   offset = Vector2(.6,.5)
   shadow_size = Vector2(1.2,1)
   pixels = 320.0
   ortho = 4.0
   target_z = .7
  if artifact == "solar_dial":
   offset = Vector2(.7,.7)
   shadow_size = Vector2(1.4,1.4)
   pixels = 320.0
   ortho = 4.0
   target_z = .7
 if not _textures.has(path):
  var texture: Texture2D
  if ResourceLoader.exists(path):
   texture = load(path) as Texture2D
  else:
   var image := Image.load_from_file(path)
   if image == null or image.is_empty():return fallback
   texture = ImageTexture.create_from_image(image)
  if texture == null:return fallback
  _textures[path] = texture
 var texture: Texture2D = _textures[path]
 var frames: Array[Texture2D] = []
 var motion: Dictionary = spec.get("_motion", {})
 if venue == "aurora_world" and kind == "plinth" and str(spec.get("id","")) == "orrery" and not motion.is_empty():
  for i in range(64):
   var frame_path := "res://art/environment/aurora_world-orrery-motion-%02d.png" % i
   if not _textures.has(frame_path):
    if not ResourceLoader.exists(frame_path):
     frames.clear()
     break
    _textures[frame_path] = load(frame_path) as Texture2D
   var frame: Texture2D = _textures[frame_path]
   if frame == null:
    frames.clear()
    break
   frames.append(frame)
 var a: Variant = spec.get("at", [0,0])
 var at: Vector2 = a if a is Vector2 else Vector2(float(a[0]),float(a[1]))
 # Render: 320px / 4 world units. Game: 30px / cos(45deg).
 var pixels_per_unit := pixels/ortho
 var scale := (30.0 / cos(PI/4.0)) / pixels_per_unit
 var size := Vector2(pixels,pixels)*scale
 var origin := Vector2(pixels*.5,pixels*.5+target_z*cos(asin(2.0/3.0))*pixels_per_unit)*scale
 return func(ci: CanvasItem) -> void:
  Iso.shadow(ci,at+offset-shadow_size*.5,shadow_size,.16)
  var displayed: Texture2D = texture
  if frames.size() == 64:
   displayed = frames[int(motion.get("frame",0)) % frames.size()]
  ci.draw_texture_rect(displayed,Rect2(Iso.to_screen(at+offset)-origin,size),false)

## Original collection kits. Dimensions stay tied to navigation
## footprints; unknown exhibits and furniture use their authored fallback.
static func _collection_painter(venue: String,kind: String,spec: Dictionary,fallback: Callable) -> Callable:
 var key := kind
 var offset := Vector2.ZERO
 var footprint := Vector2(.6,.6)
 var artifacts := {
  "lunar_canopy":["statue",Vector2(2,1.5)],
  "comet_marker":["statue",Vector2(1.3,1)],
  "grand_alignment":["orrery",Vector2(1.6,1.2)],
  "living_biosphere":["tank",Vector2(2,1.1)],
  "moonseed":["vitrine",Vector2(1.4,1)],
  "meteor_garden":["case",Vector2(2.1,1)],
  "eclipse_lens":["plinth",Vector2(1.1,1.1)],
  "solar_sail":["hanging",Vector2(1.8,.4)],
 }
 var dimensions := {"desk":Vector2(1.9,.6),"rack":Vector2(1.2,.5),"kiosk":Vector2(.34,.34),"counter_body":Vector2(1.7,.6)}
 var heights := {"desk":18.0,"kiosk":30.0,"counter_body":21.0}
 if venue == "ironwood_citadel":
  artifacts={
   "iron_guard_west":["armor",Vector2(1.3,1.1)],
   "iron_guard_east":["armor",Vector2(1.3,1.1)],
   "warhorse":["statue",Vector2(2.5,1.2)],
   "founder_tomb":["casket",Vector2(1.7,1)],
   "siege_relics":["case",Vector2(1.9,1)],
   "iron_wyvern":["hanging",Vector2(1.8,1.7)],
   "gate_champion":["statue",Vector2(1.3,1)],
   "siege_engine":["statue",Vector2(2.2,1.4)],
  }
  dimensions["crate"]=Vector2(.8,.6)
  dimensions["cabinet"]=Vector2(.7,.5)
  heights["cabinet"]=34.0
 elif venue == "pelagic_crown":
  artifacts={
   "crown_whale":["hung_skeleton",Vector2(3.8,1.1)],
   "sunlit_reef":["tank",Vector2(1.8,1.1)],
   "midnight_reef":["tank",Vector2(1.8,1.1)],
   "coral_court_west":["coral",Vector2(1.7,1.2)],
   "coral_court_east":["coral",Vector2(1.7,1.2)],
   "tide_table":["touch_pool",Vector2(2.2,1.3)],
   "harbour_reef":["coral",Vector2(1.5,1)],
   "crown_lagoon":["tank",Vector2(5.2,3.9)],
  }
  dimensions["crate"]=Vector2(.8,.6)
  dimensions["cabinet"]=Vector2(.7,.5)
  dimensions["shelf"]=Vector2(2,.5)
  heights["cabinet"]=34.0
  heights["shelf"]=30.0
 elif venue == "chronos_spire":
  artifacts={
   "first_chime":["clockwork",Vector2(1.2,1)],
   "last_chime":["clockwork",Vector2(1.2,1)],
   "gate_clock":["clockwork",Vector2(1.2,1)],
   "age_engine":["orrery",Vector2(1.5,1.2)],
   "sealed_century":["casket",Vector2(1.7,1)],
   "watchmakers_table":["case",Vector2(1.9,1)],
   "millennium_key":["vitrine",Vector2(1.3,1)],
   "master_clock":["clockwork",Vector2(1.8,1.3)],
  }
  dimensions["crate"]=Vector2(.8,.6)
  dimensions["cabinet"]=Vector2(.7,.5)
  dimensions["shelf"]=Vector2(2,.5)
  heights["cabinet"]=34.0
  heights["shelf"]=30.0
 elif venue == "empyrean_palace":
  artifacts={
   "cloud_throne":["throne",Vector2(1.6,1.2)],
   "royal_guard_west":["armor",Vector2(1.3,1.1)],
   "royal_guard_east":["armor",Vector2(1.3,1.1)],
   "star_crown":["vitrine",Vector2(1.4,1)],
   "imperial_regalia":["case",Vector2(2,1)],
   "founding_dynasty":["casket",Vector2(1.8,1)],
   "cloud_chariot":["statue",Vector2(2.6,1.3)],
   "palace_herald":["statue",Vector2(1.4,1)],
   "petal_fountain":["tank",Vector2(2.6,2)],
  }
  for suffix in ["nw","ne","sw","se"]:artifacts["court_column_"+suffix]=["plinth",Vector2(.5,.5)]
  dimensions["crate"]=Vector2(.8,.6)
  dimensions["cabinet"]=Vector2(.7,.5)
  dimensions["shelf"]=Vector2(2,.5)
  heights["cabinet"]=34.0
  heights["shelf"]=30.0
 elif venue == "infinite_museum":
  artifacts={
   "leviathan":["skeleton",Vector2(2.8,1.3)],
   "first_light":["vitrine",Vector2(1.4,1)],
   "colossus_of_ages":["statue",Vector2(1.5,1.2)],
   "the_last_key":["plinth",Vector2(1.1,1.1)],
   "hall_of_wonders":["case",Vector2(2.2,1)],
   "orrery_of_worlds":["orrery",Vector2(2.6,2.3)],
   "the_founder":["statue",Vector2(1.4,1.1)],
   "sarcophagus_of_kings":["casket",Vector2(1.8,1.1)],
   "meridian_stone":["plinth",Vector2(1.2,1.2)],
   "sentinel_west":["statue",Vector2(1.2,1)],
   "sentinel_east":["statue",Vector2(1.2,1)],
   "unwritten_world":["vitrine",Vector2(1.4,1.2)],
   "first_discovery":["case",Vector2(1.8,1)],
  }
  for prefix in ["atrium_pier_","stair_pier_"]:
   for side in ["w","e"]:artifacts[prefix+side]=["plinth",Vector2(.5,.5)]
  dimensions["crate"]=Vector2(.8,.6)
  dimensions["cabinet"]=Vector2(.7,.5)
  dimensions["shelf"]=Vector2(2,.5)
  heights["cabinet"]=34.0
  heights["shelf"]=30.0
 var artifact := str(spec.get("id",""))
 if artifacts.has(artifact):
  var entry: Array=artifacts[artifact]
  if kind != str(entry[0]):return fallback
  key=artifact;footprint=entry[1]
  if venue=="infinite_museum" and (artifact.begins_with("atrium_pier_") or artifact.begins_with("stair_pier_")):key="collection_pier"
  if venue=="empyrean_palace" and artifact.begins_with("court_column_"):key="court_column"
  if kind not in ["hanging","hung_skeleton"]:offset=footprint*.5
 elif kind == "bench":
  var length := float(spec.get("len",1.5))
  if not is_equal_approx(length,1.5):return fallback
  var axis := str(spec.get("axis","x"))
  key="bench-150-%s-%d" % [axis,int(bool(spec.get("flip",false)))]
  footprint=Vector2(1.5,.5) if axis=="x" else Vector2(.5,1.5)
  offset=Vector2(.75,.22) if axis=="x" else Vector2(.22,.75)
 elif dimensions.has(kind):
  footprint=dimensions[kind];offset=footprint*.5
  if heights.has(kind) and not is_equal_approx(float(spec.get("height",heights[kind])),heights[kind]):return fallback
 elif kind != "planter":return fallback
 if kind not in ["planter","bench","hanging","hung_skeleton"]:
  var raw: Variant=spec.get("size",footprint)
  var actual: Vector2=raw if raw is Vector2 else Vector2(float(raw[0]),float(raw[1]))
  if not actual.is_equal_approx(footprint):return fallback
 var rotation := float(spec.get("rot",0))
 if str(spec.get("mirror",""))!="":return fallback
 if not is_zero_approx(rotation):
  if venue not in ["celestial_conservatory","ironwood_citadel","pelagic_crown","chronos_spire","empyrean_palace","infinite_museum"] or kind!="counter_body" or not is_equal_approx(rotation/90.0,roundf(rotation/90.0)):return fallback
  var turn := posmod(roundi(rotation/90.0),4)
  if turn!=0:key+="-"+{1:"west",2:"north",3:"east"}[turn]
  # The art is already turned about its center. Match the ground shadow to
  # that facing without moving the original center offset.
  if turn%2==1:footprint=Vector2(footprint.y,footprint.x)
 if kind not in ["planter","bench","hanging","hung_skeleton"] and str(spec.get("axis","x"))!="x":return fallback
 var path := "res://art/environment/%s-%s.png" % [venue,key]
 if not ResourceLoader.exists(path):return fallback
 if not _textures.has(path):_textures[path]=load(path) as Texture2D
 var texture: Texture2D=_textures[path]
 if texture==null:return fallback
 var motion: Dictionary=spec.get("_motion",{})
 var frames: Array[Texture2D]=[]
 var motion_count := 48 if venue=="ironwood_citadel" and key=="siege_engine" else 0
 if venue=="pelagic_crown" and key=="crown_lagoon":motion_count=32
 if venue=="chronos_spire" and key=="age_engine":motion_count=32
 if venue=="empyrean_palace" and key=="petal_fountain":motion_count=32
 if venue=="infinite_museum" and key=="orrery_of_worlds":motion_count=48
 if motion_count>0 and not motion.is_empty():
  for i in range(motion_count):
   var frame_path := "res://art/environment/%s-%s-motion-%02d.png" % [venue,key,i]
   if not ResourceLoader.exists(frame_path):
    frames.clear();break
   if not _textures.has(frame_path):_textures[frame_path]=load(frame_path) as Texture2D
   var frame: Texture2D=_textures[frame_path]
   if frame==null:
    frames.clear();break
   frames.append(frame)
 var raw_at: Variant=spec.get("at",[0,0])
 var at: Vector2=raw_at if raw_at is Vector2 else Vector2(float(raw_at[0]),float(raw_at[1]))
 var pixels := 320.0
 var ortho := 4.0
 var target_z := .7
 if venue=="pelagic_crown" and key in ["crown_lagoon","crown_whale"]:
  pixels=512;ortho=7.8 if key=="crown_lagoon" else 6.4;target_z=1.0
 if venue=="chronos_spire" and key=="master_clock":
  pixels=512;ortho=4.8;target_z=1.1
 if venue=="empyrean_palace" and key=="petal_fountain":
  pixels=512;ortho=5.2;target_z=.9
 if venue=="infinite_museum" and key=="orrery_of_worlds":
  pixels=512;ortho=5.2;target_z=1.2
 var density := pixels/ortho
 var scale := (30.0/cos(PI/4.0))/density
 var size := Vector2(pixels,pixels)*scale
 var origin := Vector2(pixels*.5,pixels*.5+target_z*cos(asin(2.0/3.0))*density)*scale
 return func(ci: CanvasItem) -> void:
  Iso.shadow(ci,at+offset-footprint*.5,footprint,.16)
  var displayed: Texture2D=texture if frames.is_empty() else frames[int(motion.get("frame",0))%frames.size()]
  ci.draw_texture_rect(displayed,Rect2(Iso.to_screen(at+offset)-origin,size),false)
