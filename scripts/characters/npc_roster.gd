extends RefCounted
## Role owns the spawn pool; age and gender only select appearance within it.
const AGES := ["child", "young_adult", "middle_aged", "elder"]
const GENDERS := ["male", "female"]
const STAFF_ROLES := ["employee", "ticket", "docent", "promotions", "porter"]
const VISITOR_COUNT := 24
const RESERVED_HOST := {"id": "ellis_finch", "role": "host", "age_group": "middle_aged", "gender": "male"}
static func visitor(slot: int) -> Dictionary:
    var s := posmod(slot, VISITOR_COUNT)
    var group: int = s % 8
    return {"id": "visitor_%s_%s_%d" % [AGES[group / 2], GENDERS[group % 2], s / 8],
        "role": "visitor", "age_group": AGES[group / 2], "gender": GENDERS[group % 2], "variant": s / 8}
static func employee(role: String, variant: int) -> Dictionary:
    if role not in STAFF_ROLES:
        return {}
    var v := posmod(variant, 3)
    return {"id": "%s_%d" % [role, v], "role": role,
        "age_group": AGES[1 + v], "gender": GENDERS[v % 2], "variant": v}
static func compatible(role: String, look: Dictionary) -> bool:
    var candidate: String = str(look.get("role", ""))
    if candidate == "host":
        return role in ["", "host"] and look.get("id", "") == RESERVED_HOST.id
    if candidate == "visitor":
        return role in ["", "visitor"] and not bool(look.get("is_staff", false))
    if candidate in STAFF_ROLES:
        return role in ["", candidate] and str(look.get("age_group", "")) != "child" and bool(look.get("is_staff", false))
    return false
