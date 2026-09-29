extends SceneTree
## Achievements: data-driven, tracked locally on every build (so a storefront
## wired later back-fills them), unlocked from real game events, and saved.

var failures := 0

func check(ok: bool, message: String) -> void:
	if ok:
		print("PASS: ", message)
	else:
		failures += 1
		printerr("FAIL: ", message)

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var gs: Node = root.get_node("GameState")
	var ec: Node = root.get_node("Economy")
	var ps: Node = root.get_node("PlatformServices")
	root.get_node("SaveSystem").set_process(false)
	ec.set_process(false)
	root.get_node("DataLoader").reload_all()
	gs.reset_to_new_game()
	gs.ready_flag = true
	check(ps.definitions().size() >= 10, "achievements are defined in data")
	check(ps.backend == "none", "without a store SDK the offline backend is used")
	check(ps.unlocked().is_empty(), "a new game has no achievements")
	var got: Array = []
	ps.achievement_unlocked.connect(func(id: String, _d: Dictionary) -> void: got.append(id))
	gs.add_cash(BigNumber.from_parts(1.0, 9))
	check(ec.purchase_upgrade(gs.current_venue, "ticket", "speed"), "buy an upgrade")
	check(ps.is_unlocked("FIRST_UPGRADE") and "FIRST_UPGRADE" in got, "the first upgrade unlocks 'Open for Business'")
	var WS: GDScript = load("res://scripts/meta/wing_system.gd")
	var ids: Array = []
	for m in root.get_node("DataLoader").milestones.get(gs.current_venue, []):
		ids.append(str(m["id"]))
	gs.venue_state(gs.current_venue)["milestones"] = ids
	gs.cash = BigNumber.from_parts(1.0, 60)
	WS.renovate(gs.current_venue, "hall_of_giants")
	check(ps.is_unlocked("SECOND_FLOOR"), "renovating a floor unlocks 'Going Up'")
	WS.renovate(gs.current_venue, "sky_terrace")
	check(ps.is_unlocked("GRAND"), "grandeur III unlocks 'Simply Grand'")
	check(not ps.is_unlocked("MAGNIFICENT"), "grandeur IV is still ahead")
	var save: Dictionary = gs.to_save_dict()
	gs.reset_to_new_game()
	check(ps.unlocked().is_empty(), "a reset clears them")
	gs.from_save_dict(save)
	check(ps.is_unlocked("GRAND") and ps.is_unlocked("FIRST_UPGRADE"), "achievements survive save and load")
	print("RESULT: ", "OK" if failures == 0 else "FAILED (%d)" % failures)
	quit(1 if failures > 0 else 0)
