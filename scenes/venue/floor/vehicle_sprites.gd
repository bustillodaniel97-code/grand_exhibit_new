extends RefCounted
## Original Blender fleet. Ground anchors use the same dimetric projection as Iso.
static var _manifest: Dictionary={}
static var _textures: Dictionary={}
static func manifest() -> Dictionary:
 if _manifest.is_empty():
  var data: Variant=JSON.parse_string(FileAccess.get_file_as_string("res://art/vehicles/fleet.json"))
  if data is Dictionary:_manifest=data
 return _manifest
static func assign(car: Dictionary,venue: String,index: int,background: bool=false) -> void:
 var profiles: Dictionary=manifest().get("profiles",{})
 var profile: Array=profiles.get(venue,profiles.get("whispering_pines",[]))
 if profile.size()!=6:return
 var entry: Array=profile[4+posmod(index,2) if background else posmod(index,4)]
 car.vehicle=str(entry[0]);car.paint=int(entry[1])
static func direction(car: Dictionary) -> String:
 var axis: Vector2=car.get("axis",Vector2.RIGHT)
 return ("x_plus" if float(car.dir)>0 else "x_minus") if absf(axis.x)>absf(axis.y) else ("y_plus" if float(car.dir)>0 else "y_minus")
static func sprite(car: Dictionary) -> Dictionary:
 var key:="%s:%d:%s" % [str(car.get("vehicle","")),int(car.get("paint",0)),direction(car)]
 return manifest().get("sprites",{}).get(key,{})
static func draw(ci: CanvasItem,car: Dictionary,ground_center: Vector2) -> bool:
 var record:=sprite(car)
 if record.is_empty():return false
 var file: String=record.file
 if not _textures.has(file):_textures[file]=load("res://art/vehicles/"+file)
 var texture: Texture2D=_textures[file]
 if texture==null:return false
 ci.draw_texture_rect(texture,Rect2(ground_center+Vector2(record.offset[0],record.offset[1]),Vector2(record.size[0],record.size[1])),false)
 return true

## Replacements vary the model and paint after an offscreen trip has ended.
static func assign_trip(car: Dictionary,venue: String,trip: int) -> void:
 var profiles: Dictionary=manifest().get("profiles",{})
 var profile: Array=profiles.get(venue,profiles.get("whispering_pines",[]))
 if profile.is_empty():return
 var entry: Array=profile[posmod(trip*5+trip/6,profile.size())]
 car.vehicle=str(entry[0]);car.paint=posmod(int(entry[1])+trip/3,2)
