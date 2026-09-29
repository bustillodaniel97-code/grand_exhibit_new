extends SceneTree
## venue_switch_probe.gd — reproduce the engine ERROR seen on device on every
## venue switch:
##   E godot: ERROR: Condition "!is_inside_tree()" is true. Returning: false
##   E godot:    at: can_process (scene/main/node.cpp:867)
## Loads the real shell (main.tscn) so popups/HUD/music exist, then performs a
## real graduation and reports whether the error appears. Diagnostic only.

var PrestigeSystem: GDScript

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var xdg := OS.get_environment("XDG_DATA_HOME")
	if OS.get_environment("GRAND_EXHIBIT_TEST_RUN") != "1" or not xdg.begins_with("/tmp/grand-audit-world"):
		printerr("AUDIT_REFUSED: requires GRAND_EXHIBIT_TEST_RUN=1 and XDG_DATA_HOME=/tmp/grand-audit-world")
		quit(2)
		return
	PrestigeSystem = load("res://scripts/meta/prestige_system.gd") as GDScript
	var ss := root.get_node("SaveSystem")
	ss.set_process(false)
	var gs := root.get_node("GameState")
	gs.reset_to_new_game()
	gs.ready_flag = true
	var vid: String = str(gs.current_venue)
	var to_vid := "copper_kettle"
	if to_vid not in gs.venues_unlocked:
		gs.venues_unlocked.append(to_vid)
	# Real shell: HUD, side rail, popup layer, music.
	var main: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	for n in root.get_children():
		if n != main:
			n.process_mode = Node.PROCESS_MODE_DISABLED
	await process_frame
	await process_frame
	print("SWITCH_PROBE switching ", vid, " -> ", to_vid, " via prestige_performed")
	gs.close_venue(vid)
	gs.current_venue = to_vid
	gs.venue_state(to_vid)
	(root.get_node("EventBus") as Node).prestige_performed.emit(vid, to_vid)
	print("SWITCH_PROBE now=", gs.current_venue)
	for i in 20:
		await process_frame
	print("SWITCH_PROBE done (any engine ERROR above is the reproduced defect)")
	quit(0)
