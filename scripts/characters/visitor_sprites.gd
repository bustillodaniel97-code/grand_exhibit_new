extends RefCounted
## Visitor-only compatibility API: eight front walk poses followed by seating.
const Motion := preload("res://scripts/characters/motion_sprites.gd")
static func frames(identity: Dictionary) -> Array:
 if str(identity.get("role",""))!="visitor":return []
 var packet:=Motion.get_set(identity)
 if packet.is_empty():return []
 var result: Array=packet.front.duplicate();result.append(packet.seated);return result
