extends SceneTree

## Adversarial diagnostic: an exit route failure enters exit_blocked, but the
## live visitor FSM must retry or retire it. This intentionally checks the
## current production behavior without editing the game code.
const Character = preload("res://scenes/venue/floor/character.gd")
var failures := 0

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var xdg := OS.get_environment("XDG_DATA_HOME")
	if OS.get_environment("GRAND_EXHIBIT_TEST_RUN") != "1" or not xdg.begins_with("/tmp/grand-audit-world"):
		printerr("AUDIT_REFUSED: requires GRAND_EXHIBIT_TEST_RUN=1 and XDG_DATA_HOME=/tmp/grand-audit-world")
		quit(2)
		return
	root.get_node("SaveSystem").set_process(false)
	var gs = root.get_node("GameState")
	gs.reset_to_new_game()
	gs.ready_flag = true
	var vf = load("res://scenes/venue/floor/venue_floor.gd").new()
	vf.size = Vector2(720, 760)
	root.add_child(vf)
	vf.set_process(false)
	gs.current_venue = "whispering_pines"
	vf.retheme("whispering_pines")
	var v = vf.Visitor.new()
	v.node = Character.new()
	vf._canvas.add_child(v.node)
	v.pos = vf._exit_wall_g + Vector2(0, 0.65)
	v.target = v.pos
	v.path = []
	v.state = "exit_blocked"
	vf._place(v.node, v.pos)
	vf._visitors.append(v)
	for i in 120:
		vf._update_visitors(0.05)
	var still_blocked: bool = (v in vf._visitors and v.state == "exit_blocked")
	print("EXIT_BLOCKED_DIAGNOSTIC still_present=", still_blocked,
		" state=", v.state, " visitors=", vf._visitors.size(),
		" unreachable=", vf._unreachable_targets)
	if still_blocked:
		failures += 1
	vf.free()
	quit(1 if failures else 0)
