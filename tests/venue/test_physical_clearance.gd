extends "res://tests/venue/test_nav_reachability.gd"
const WORKING := ["desk","shelf","cabinet","rack","crate","info_desk","trolley","machine"]
func _check_all_venues() -> void:
 var count := 0
 for vid in DL.venue_order():
  root.get_node("GameState").current_venue=str(vid)
  _floor.retheme(str(vid))
  for spec in _floor._theme.exhibits+_floor._theme.props:
   if spec.has("id"):
    if spec.kind in ["mural","hanging","hung_skeleton"]:continue
   elif spec.kind not in WORKING:continue
   var label: String=str(vid)+"/"+str(spec.get("id",str(spec.kind)+str(spec.at)))
   var rect: Rect2=_floor.Exhibits.solid_rect(spec)
   check(spec.get("solid_footprint",false),label+" opts into its physical bounds")
   check(rect.size.x>0 and rect.size.y>0,label+" has nonempty physical bounds")
   count+=1
   for u in [.15,.5,.85]:
    for v in [.15,.5,.85]:
     var id: Vector2i=_floor._nav_id(rect.position+rect.size*Vector2(u,v))
     check(_floor._nav.is_in_boundsv(id) and _floor._nav.is_point_solid(id),label+" body is not walkable")
  for spec in _floor._theme.exhibits:
   if spec.has("views"):check(_floor.browse_spots().has(spec.id),str(vid)+"/"+str(spec.id)+" authored audience positions are registered")
   for point in _floor.browse_spots().get(spec.id,[]):
    check(not _floor._nav.is_point_solid(_floor._nav_id(point)),str(vid)+"/"+str(spec.id)+" raw view is clear: "+str(point))
  for dept in ["gallery","promotions"]:
   for point in _floor._stations(dept):check(not _floor._nav.is_point_solid(_floor._nav_id(point)),str(vid)+" "+dept+" staff stand clear: "+str(point))
 print("PHYSICAL_PIECES_CHECKED ",count)
 var E=_floor.Exhibits
 check(E.solid_rect({"kind":"kelp","at":[3,4],"r":.3}).is_equal_approx(Rect2(2.7,3.7,.6,.6)),"centred kelp reserves its actual rock base")
 check(E.solid_rect({"kind":"desk","at":[4,4],"size":[2,1],"rot":90}).is_equal_approx(Rect2(4.5,3.5,1,2)),"rotated footprint keeps the actual centre and turned extents")
