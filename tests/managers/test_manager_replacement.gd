extends SceneTree
## Atomic manager replacement and economy-visible team result regression.

const MS_PATH := "res://scripts/managers/manager_system.gd"
var failures := 0

func check(ok: bool, message: String) -> void:
	if ok:
		print("PASS  ", message)
	else:
		failures += 1
		printerr("FAIL  ", message)

func _init() -> void:
	call_deferred("run")

func run() -> void:
	var gs: Node = root.get_node("GameState")
	var eb: Node = root.get_node("EventBus")
	var economy: Node = root.get_node("Economy")
	var managers: GDScript = load(MS_PATH)
	gs.reset_to_new_game()
	managers.add_cards("docent_poppy", 1)
	managers.add_cards("usher_bram", 1)
	check(managers.assign("docent_poppy", "ticket"), "current manager fills the post")
	var before: float = float(economy.manager_multiplier_for("ticket"))
	var expected: float = float(managers.productivity_multiplier(
		managers.manager_def("usher_bram"), managers.state("usher_bram"))
	)
	var snapshots: Array = []
	eb.manager_assigned.connect(func(id: String, dept: String) -> void:
		snapshots.append({"id": id, "dept": dept,
			"team": managers.assigned_ids("ticket"),
			"mult": economy.manager_multiplier_for("ticket")}))
	check(managers.replace_assignment("docent_poppy", "usher_bram", "ticket"),
		"valid full-post replacement succeeds")
	check(managers.assigned_ids("ticket") == ["usher_bram"],
		"replacement leaves the stable final roster")
	check(absf(economy.manager_multiplier_for("ticket") - expected) < 0.0001
		and economy.manager_multiplier_for("ticket") > before,
		"Economy sees the resulting team productivity")
	check(snapshots.size() == 2, "replacement emits the existing two assignment events")
	var atomic := true
	for snapshot in snapshots:
		atomic = atomic and snapshot["team"] == ["usher_bram"] \
			and absf(float(snapshot["mult"]) - expected) < 0.0001
	check(atomic, "every listener observes the complete final team")

	var team_before: Array[String] = managers.assigned_ids("ticket")
	var event_count := snapshots.size()
	check(not managers.replace_assignment("docent_poppy", "usher_bram", "ticket"),
		"stale outgoing choice is rejected")
	check(managers.assigned_ids("ticket") == team_before and snapshots.size() == event_count,
		"stale choice changes no state and emits no event")
	check(not managers.replace_assignment("usher_bram", "barker_theo", "ticket"),
		"unowned wrong-specialty incoming manager is rejected")
	check(managers.assigned_ids("ticket") == team_before and snapshots.size() == event_count,
		"invalid incoming manager leaves team intact")

	# Replacement is not a shortcut around an open slot or cross-department posting.
	managers.unassign("usher_bram")
	event_count = snapshots.size()
	check(not managers.replace_assignment("usher_bram", "docent_poppy", "ticket"),
		"open or no-longer-current post is not replaceable")
	check(managers.assigned_ids("ticket").is_empty() and snapshots.size() == event_count,
		"failed open-slot replacement has no mutation or event")

	# The modal must expose the economic decision before asking for the swap.
	check(managers.assign("usher_bram", "ticket"), "restore current team for modal preview")
	var screen: Control = load("res://scenes/managers/managers_screen.tscn").instantiate()
	root.add_child(screen)
	await process_frame
	var modal_holders: Array[String] = ["usher_bram"]
	screen._open_post_replacement("docent_poppy", "ticket", modal_holders)
	await process_frame
	var copy := _control_text(screen)
	check(copy.contains("Incoming: Docent Poppy Vale") and copy.contains("Replace Head Usher Bram"),
		"modal explicitly names incoming and current staff")
	check(copy.contains("Team +5% → +3%"),
		"modal shows actual current and resulting Economy team productivity")
	check(copy.contains("Keep current team"), "modal offers an explicit no-change action")
	screen.queue_free()

	print("DONE failures=", failures)
	quit(0 if failures == 0 else 1)

func _control_text(node: Node) -> String:
	var out := ""
	if node is Label or node is Button:
		out += str(node.text) + "\n"
	for child in node.get_children():
		out += _control_text(child)
	return out
