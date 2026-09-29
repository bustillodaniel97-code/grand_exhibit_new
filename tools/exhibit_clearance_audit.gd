extends "res://tools/campaign_circulation_audit.gd"
## Observe real production segments against physical exhibits and working props,
## including legacy art that has not opted into complete navigation obstacles.
const WORKING := ["desk","shelf","cabinet","rack","crate","info_desk","trolley","machine"]
var _shape_venue := ""
var _shapes: Array = []
func _observe_step(kind: String,a: Vector2,b: Vector2,state: String) -> void:
 super._observe_step(kind,a,b,state)
 if _shape_venue!=_floor._theme.id:
  _shape_venue=_floor._theme.id;_shapes.clear()
  for spec in _floor._theme.exhibits+_floor._theme.props:
   if spec.has("id"):
    if spec.kind in ["mural","hanging","hung_skeleton"]:continue
   elif spec.kind not in WORKING:continue
   var rect: Rect2=_floor.Exhibits.solid_rect(spec)
   if rect.size.x>0 and rect.size.y>0:_shapes.append([rect.grow(-.01),str(spec.get("id",str(spec.kind)+str(spec.at)))])
 for item in _shapes:
  if _floor._plaza._interval(a,b,item[0]).is_finite():
   violations+=1
   if crossings.size()<12:crossings[kind+":"+state+" physical "+item[1]]=[str(a),str(b)]
