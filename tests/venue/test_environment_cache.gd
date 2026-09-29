extends "res://tests/venue/test_nav_reachability.gd"
## Campaign travel must not accumulate permanent references to every museum's
## rendered collection. In-place station upgrades should still reuse art.
const Props := preload("res://scenes/venue/floor/museum_props.gd")
func _check_all_venues() -> void:
 for venue in DL.venue_order()+["aurora_world","ironwood_citadel","pelagic_crown"]:
  _floor.retheme(str(venue))
  var current_only := true
  for path in Props._textures:
   if not str(path).begins_with("res://art/environment/%s-" % venue):current_only=false
  check(current_only,str(venue)+" does not retain previous museums' texture caches")
  check(not Props._textures.is_empty(),str(venue)+" still loads its active collection")
  var path: String=Props._textures.keys()[0]
  var texture: Texture2D=Props._textures[path]
  _floor._props_key=""
  _floor._rebuild_props()
  check(Props._textures.get(path)==texture,str(venue)+" station rebuild reuses active textures")
  print("ENVIRONMENT_CACHE ",venue," retained_textures=",Props._textures.size())
