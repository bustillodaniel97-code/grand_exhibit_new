extends SceneTree
const Roster := preload("res://scripts/characters/npc_roster.gd")
const Character := preload("res://scenes/venue/floor/character.gd")
var failures := 0
func check(ok: bool, message: String) -> void:
    if not ok:
        failures += 1
        printerr("FAIL: " + message)
func _initialize() -> void:
    check(not Roster.compatible("visitor", Roster.RESERVED_HOST), "Ellis never enters visitor pool")
    check(not Roster.compatible("ticket", Roster.RESERVED_HOST), "Ellis never enters employee pool")
    var counts := {}
    for i in range(Roster.VISITOR_COUNT):
        var profile: Dictionary = Roster.visitor(i)
        var group: String = profile.age_group + "/" + profile.gender
        counts[group] = int(counts.get(group, 0)) + 1
        check(profile.role == "visitor", "visitor pool contains only visitors")
        check(not Roster.compatible("ticket", profile), "employee rejects visitor identity")
    check(counts.size() == 8, "all eight age/gender groups exist")
    for count in counts.values(): check(count == 3, "each group has three variants")
    for role in Roster.STAFF_ROLES:
        for i in range(3):
            var profile: Dictionary = Roster.employee(role, i)
            profile.is_staff = true
            check(profile.age_group != "child", "staff are adults")
            check(not Roster.compatible("visitor", profile), "visitor rejects staff identity")
        var staff := Character.new()
        staff.set_painter_mode(true)
        staff.set_uniform(Color.TEAL, 0, role)
        var before := staff.look_key()
        staff.set_look_slot(0)
        staff.randomize_look(7)
        check(staff.is_staff and staff.actor_role == role and staff.look_key() == before, "visitor setters cannot overwrite staff")
        staff.free()
    var visitor := Character.new()
    visitor.set_painter_mode(true)
    visitor.set_look_slot(0)
    visitor.set_uniform(Color.TEAL, 0, "ticket")
    check(not visitor.is_staff and visitor.actor_role == "visitor", "staff setter cannot overwrite visitor")
    check(visitor.age_scale() < 1.0, "child visual scale is smaller")
    visitor.set_painter_mode(false)
    visitor.apply_look({"is_staff": true, "role": "ticket"})
    check(not visitor.is_staff, "raw staff look cannot contaminate visitor")
    visitor.free()
    print("NPC role and demographic checks: ", failures, " failures")
    quit(1 if failures else 0)
