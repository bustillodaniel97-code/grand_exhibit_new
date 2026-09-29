extends SceneTree
## test_exit_blocked_recovery.gd — WORLD-LATENT regression.
##
## _begin_exit parks a visitor in exit_blocked when the plaza route is empty,
## but _update_visitors had no handler, so the synthetic probe stranded forever.
## The fix retries the outdoor leg on a 1s backoff (geometry-safe, no teleport)
## and replans the city plan after 8 failures (releasing a stale park spot).
## This test injects a real exit_blocked visitor and requires forward progress.

const Character := preload("res://scenes/venue/floor/character.gd")

var failures := 0
var checks := 0

func check(ok: bool, label: String) -> void:
	checks += 1
	if ok:
		print("PASS ", label)
	else:
		failures += 1
		printerr("FAIL ", label)

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	if not OS.has_environment("GRAND_EXHIBIT_TEST_RUN"):
		printerr("REFUSED: requires GRAND_EXHIBIT_TEST_RUN isolation")
		quit(2)
		return
	root.get_node("SaveSystem").set_process(false)
	var gs = root.get_node("GameState")
	gs.reset_to_new_game()
	gs.ready_flag = true
	var VF = load("res://scenes/venue/floor/venue_floor.gd")
	var floor_node = load("res://scenes/venue/floor/venue_floor.tscn").instantiate()
	root.add_child(floor_node)
	for n in root.get_children():
		n.process_mode = Node.PROCESS_MODE_DISABLED
	gs.current_venue = "whispering_pines"
	floor_node.retheme("whispering_pines")
	# Build a genuine exit plan, then force the blocked state as _begin_exit
	# does when the plaza route is empty.
	var v = VF.Visitor.new()
	v.node = Character.new()
	v.node.set_look_slot(0)
	floor_node._canvas.add_child(v.node)
	floor_node._place(v.node, floor_node._exit_wall_g + Vector2(0, 0.65))
	v.pos = floor_node._exit_wall_g + Vector2(0, 0.65)
	v.target = v.pos
	v.path = []
	v.city_plan = floor_node._journeys.plan(v)
	v.state = "exit_blocked"
	if typeof(v.get("exit_retry")) != TYPE_NIL:
		v.set("exit_retry", 0.0)
	if typeof(v.get("exit_attempts")) != TYPE_NIL:
		v.set("exit_attempts", 0)
	floor_node._visitors.append(v)
	var start_pos: Vector2 = v.pos
	# The live plaza route for a real plan is routable, so the blocked visitor
	# must resume the exit leg within a few seconds — not strand forever.
	var recovered := false
	for i in 120:
		floor_node._update_visitors(0.05)
		floor_node._journeys.advance(0.05)
		if v.state != "exit_blocked":
			recovered = true
			break
	check(recovered, "exit_blocked retries the plaza route and resumes exit")
	check(v.state in ["exit", "city"], "blocked visitor returns to exit/city, not a new teleport (state=%s)" % v.state)
	# No wall traversal: the visitor either still walks the indoor leg or has a
	# real outdoor route appended; it never jumps to the sidewalk entry.
	if recovered and v.state == "exit":
		check(v.pos.distance_to(start_pos) < 6.0 or not v.path.is_empty(),
			"recovered exit keeps a continuous path (no teleport)")
	# Population stays bounded: the retry never duplicates the visitor.
	check(floor_node._visitors.count(v) == 1, "retry does not duplicate the visitor")
	# Venue change still clears everyone, including a blocked visitor.
	var stuck = VF.Visitor.new()
	stuck.node = Character.new()
	stuck.node.set_look_slot(1)
	floor_node._canvas.add_child(stuck.node)
	stuck.pos = floor_node._exit_wall_g + Vector2(0, 0.65)
	stuck.target = stuck.pos
	stuck.city_plan = floor_node._journeys.plan(stuck)
	stuck.state = "exit_blocked"
	if typeof(stuck.get("exit_retry")) != TYPE_NIL:
		stuck.set("exit_retry", 1.0)
	floor_node._visitors.append(stuck)
	floor_node.retheme("copper_kettle")
	check(floor_node._visitors.is_empty(), "venue change clears blocked visitors")
	print("EXIT_BLOCKED_RECOVERY checks=", checks, " failures=", failures)
	quit(0 if failures == 0 else 1)
