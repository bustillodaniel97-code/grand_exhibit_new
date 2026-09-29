extends RefCounted
## Adult role-specific front walking poses; full directional sets live in Motion.
const Motion := preload("res://scripts/characters/motion_sprites.gd")
static func frames(identity: Dictionary) -> Array:
 if str(identity.get("role","")) not in ["employee","ticket","docent","promotions","porter"]:return []
 var packet:=Motion.get_set(identity)
 return [] if packet.is_empty() else packet.front
