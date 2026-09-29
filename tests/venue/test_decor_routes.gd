extends "res://tests/venue/test_operational_routes.gd"
## Reuse the actual service, visitor, seat, wall and cliff probes with full decor.
func _prepare_venue(vid: String) -> void:
 var gs: Node=root.get_node("GameState")
 for dept in ["ticket", "archive", "gallery", "promotions"]:
  for track in ["speed", "value", "staff"]:gs.set_dept_level(vid,dept,track,int(DL.get_venue(vid).track_level_cap))
 gs.venue_state(vid)["decor"]={}
 if OS.get_environment("GRAND_EXHIBIT_DECOR_BASELINE")=="1":return
 var placed: Dictionary=gs.venue_state(vid)["decor"]
 var ids: Array=DL.decor.keys()
 for slot in mini(int(DL.get_venue(vid).decor_slots), ids.size()):
  placed[str(slot)]=ids[slot]
