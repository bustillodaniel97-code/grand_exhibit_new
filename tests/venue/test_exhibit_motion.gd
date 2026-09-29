extends "res://tests/venue/test_nav_reachability.gd"
## Exercise the real venue lifecycle: motion survives play, then disappears
## when changing museum or rebuilding props rather than retaining freed nodes.
func _check_all_venues() -> void:
 _floor.retheme("aurora_world")
 check(_floor._animated_exhibits.size() == 1, "Aurora registers exactly one orbital instrument")
 var entry: Dictionary = _floor._animated_exhibits[0]
 var node: Node2D = entry["node"]
 check(node.z_index == 8, "animated instrument retains observatory storey")
 var start: int = int(entry["state"]["frame"])
 _floor.advance_sim(.25)
 check(int(entry["state"]["frame"]) != start, "normal simulation advances instrument")
 var frame: int = int(entry["state"]["frame"])
 _floor._update_exhibit_motion(8.0)
 check(int(entry["state"]["frame"]) == frame, "complete revolution loops continuously")
 var hashes: Dictionary = {}
 for i in range(64):
  var path := "res://art/environment/aurora_world-orrery-motion-%02d.png" % i
  check(ResourceLoader.exists(path), "orbital frame %d is imported" % i)
  hashes[FileAccess.get_sha256(path)] = true
 check(hashes.size() == 64, "orbit contains 64 distinct renders rather than repeated stills")
 _floor._props_key = ""
 _floor._rebuild_props()
 check(node.is_queued_for_deletion(), "old animated node is retired on rebuild")
 check(_floor._animated_exhibits.size() == 1, "rebuild does not duplicate animated exhibits")
 _floor.retheme("grand_river")
 check(_floor._animated_exhibits.is_empty(), "switching museum clears orbital updates")
 _floor.advance_sim(.25)
 _floor.retheme("aurora_world")
 check(_floor._animated_exhibits.size() == 1, "returning to Aurora restores one instrument")
 _floor.retheme("ironwood_citadel")
 check(_floor._animated_exhibits.size()==1,"Ironwood registers one courtyard demonstration")
 entry=_floor._animated_exhibits[0]
 node=entry["node"]
 check(node.z_index==0,"siege demonstration stays on the ground-level court")
 start=int(entry["state"]["frame"])
 _floor.advance_sim(.25)
 check(int(entry["state"]["frame"])!=start,"normal play advances the demonstration")
 frame=int(entry["state"]["frame"])
 _floor._update_exhibit_motion(6.0)
 check(int(entry["state"]["frame"])==frame,"Ironwood loops its own six-second cycle")
 hashes.clear()
 for i in range(48):
  var path := "res://art/environment/ironwood_citadel-siege_engine-motion-%02d.png" % i
  check(ResourceLoader.exists(path),"demonstration frame %d is imported" % i)
  hashes[FileAccess.get_sha256(path)]=true
 check(hashes.size()==48,"demonstration has 48 distinct rendered positions")
 _floor._props_key=""
 _floor._rebuild_props()
 check(node.is_queued_for_deletion(),"rebuilding the court retires its previous animation")
 check(_floor._animated_exhibits.size()==1,"court rebuild keeps one demonstration")
 _floor.retheme("celestial_conservatory")
 check(_floor._animated_exhibits.is_empty(),"leaving Ironwood stops the demonstration updates")
 _floor.retheme("pelagic_crown")
 check(_floor._animated_exhibits.size()==1,"Pelagic registers one living lagoon")
 entry=_floor._animated_exhibits[0]
 node=entry["node"]
 check(node.z_index==0,"lagoon motion stays in the central ground-level collection")
 _floor.advance_sim(.25)
 frame=int(entry["state"]["frame"])
 check(frame>0,"normal play advances the manta")
 _floor._update_exhibit_motion(4.0)
 check(int(entry["state"]["frame"])==frame,"lagoon uses its own four-second loop")
 hashes.clear()
 for i in range(32):
  var path := "res://art/environment/pelagic_crown-crown_lagoon-motion-%02d.png" % i
  check(ResourceLoader.exists(path),"lagoon frame %d is imported" % i)
  hashes[FileAccess.get_sha256(path)]=true
 check(hashes.size()==32,"lagoon contains 32 distinct rendered swim poses")
 _floor._props_key=""
 _floor._rebuild_props()
 check(node.is_queued_for_deletion(),"lagoon rebuild retires its previous animated node")
 check(_floor._animated_exhibits.size()==1,"rebuilding preserves one living lagoon")
 _floor.retheme("whispering_pines")
 check(_floor._animated_exhibits.is_empty(),"leaving Pelagic stops its animated updates")
 _floor.retheme("chronos_spire")
 check(_floor._animated_exhibits.size()==1,"Chronos registers one clock mechanism")
 entry=_floor._animated_exhibits[0]
 node=entry["node"]
 check(node.z_index==0,"mechanism motion stays in the central ground-level collection")
 _floor.advance_sim(.25)
 frame=int(entry["state"]["frame"])
 check(frame>0,"normal play advances the gears and pendulum")
 _floor._update_exhibit_motion(4.0)
 check(int(entry["state"]["frame"])==frame,"mechanism uses its own four-second loop")
 hashes.clear()
 for i in range(32):
  var path := "res://art/environment/chronos_spire-age_engine-motion-%02d.png" % i
  check(ResourceLoader.exists(path),"mechanism frame %d is imported" % i)
  hashes[FileAccess.get_sha256(path)]=true
 check(hashes.size()==32,"mechanism contains 32 distinct rendered gear positions")
 _floor._props_key=""
 _floor._rebuild_props()
 check(node.is_queued_for_deletion(),"mechanism rebuild retires its previous animated node")
 check(_floor._animated_exhibits.size()==1,"rebuilding preserves one clock mechanism")
 _floor.retheme("whispering_pines")
 check(_floor._animated_exhibits.is_empty(),"leaving Chronos stops its animated updates")
 _floor.retheme("empyrean_palace")
 check(_floor._animated_exhibits.size()==1,"Empyrean registers one court fountain")
 entry=_floor._animated_exhibits[0]
 node=entry["node"]
 check(node.z_index==0,"fountain motion stays in the central ground-level collection")
 _floor.advance_sim(.25)
 frame=int(entry["state"]["frame"])
 check(frame>0,"normal play advances the fountain droplets")
 _floor._update_exhibit_motion(4.0)
 check(int(entry["state"]["frame"])==frame,"fountain uses its own four-second loop")
 hashes.clear()
 for i in range(32):
  var path := "res://art/environment/empyrean_palace-petal_fountain-motion-%02d.png" % i
  check(ResourceLoader.exists(path),"fountain frame %d is imported" % i)
  hashes[FileAccess.get_sha256(path)]=true
 check(hashes.size()==32,"fountain contains 32 distinct rendered water positions")
 _floor._props_key=""
 _floor._rebuild_props()
 check(node.is_queued_for_deletion(),"fountain rebuild retires its previous animated node")
 check(_floor._animated_exhibits.size()==1,"rebuilding preserves one court fountain")
 _floor.retheme("whispering_pines")
 check(_floor._animated_exhibits.is_empty(),"leaving Empyrean stops its animated updates")
 _floor.retheme("infinite_museum")
 check(_floor._animated_exhibits.size()==1,"Infinite Museum registers one armillary")
 entry=_floor._animated_exhibits[0]
 node=entry["node"]
 check(node.z_index==_floor.Iso.LEVEL_Z,"armillary motion stays in the raised central collection")
 _floor.advance_sim(.25)
 frame=int(entry["state"]["frame"])
 check(frame>0,"normal play advances the orbiting planets")
 _floor._update_exhibit_motion(6.0)
 check(int(entry["state"]["frame"])==frame,"armillary uses its own six-second loop")
 hashes.clear()
 for i in range(48):
  var path := "res://art/environment/infinite_museum-orrery_of_worlds-motion-%02d.png" % i
  check(ResourceLoader.exists(path),"armillary frame %d is imported" % i)
  hashes[FileAccess.get_sha256(path)]=true
 check(hashes.size()==48,"armillary contains 48 distinct rendered orbital positions")
 _floor._props_key=""
 _floor._rebuild_props()
 check(node.is_queued_for_deletion(),"armillary rebuild retires its previous animated node")
 check(_floor._animated_exhibits.size()==1,"rebuilding preserves one armillary")
 _floor.retheme("whispering_pines")
 check(_floor._animated_exhibits.is_empty(),"leaving Infinite Museum stops its animated updates")
