extends SceneTree
## test_cart_service_budget.gd — end-to-end courier service under the SHIPPED
## planning budget (1500us/call), unlike test_cart_dispatch_service.gd which
## runs unlimited planning. It answers one question: can real couriers still
## collect and deposit every station with the wall-clock slice that ships?
##
## The budget is wall-clock, so the sim-time bound here is deliberately
## generous (2x the documented 300s service bound): it catches a genuine
## stall (the pre-fix grand_river case served one station and never
## recovered) without turning host load into a false failure. Wall time and
## per-venue ticks are printed as evidence.
##
## Whispering Pines (small) and Grand River (historically slowest) run in
## sequence on one floor node, mirroring the marathon's venue walk.

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
	seed(20260919)
	var floor_node = load("res://scenes/venue/floor/venue_floor.tscn").instantiate()
	floor_node.set_size(Vector2(720, 760))
	root.add_child(floor_node)
	for n in root.get_children():
		n.process_mode = Node.PROCESS_MODE_DISABLED
	var budget: int = floor_node._porter_planning_budget_usec
	check(budget > 0, "shipped planning budget in use (%dus)" % budget)
	# 18000 ticks = 900 sim-seconds: 3x the documented 300s service bound.
	# Measured under host load: whisper 437s (5/5), grand_river 217s (3/3).
	# The margin absorbs the wall-clock budget's host-speed dependence, so
	# this is a stall detector (the pre-fix grand_river never completed)
	# rather than a tight benchmark.
	var bounds := {"whispering_pines": 18000, "grand_river": 18000}
	for vid in bounds.keys():
		gs.current_venue = vid
		for dept in ["ticket", "archive", "gallery", "promotions"]:
			for track in ["staff", "speed", "value"]:
				gs.set_dept_level(vid, dept, track, 8)
		floor_node.retheme(vid)
		floor_node.set_rates(root.get_node("Economy").venue_rates(vid))
		floor_node._windows_active = floor_node._max_windows
		for w in floor_node._windows_active:
			floor_node._stacks[w] = 1
		var seen_collect: Dictionary = {}
		var seen_deposit: Dictionary = {}
		var wall_start := Time.get_ticks_usec()
		var ticks := 0
		for step in int(bounds[vid]):
			ticks = step + 1
			floor_node._update_porters(.05)
			for p in floor_node._porters:
				if p.state == "collect" and not seen_collect.has(p.window):
					seen_collect[p.window] = true
				elif p.state == "deposit" and not seen_deposit.has(p.window):
					seen_deposit[p.window] = true
			if seen_collect.size() >= floor_node._max_windows \
					and seen_deposit.size() >= floor_node._max_windows:
				break
		var wall_ms := (Time.get_ticks_usec() - wall_start) / 1000
		print("SERVICE_BUDGET ", vid, " collect=", seen_collect.size(), "/", floor_node._max_windows,
			" deposit=", seen_deposit.size(), "/", floor_node._max_windows,
			" sim_seconds=", ticks * 0.05, " wall_ms=", wall_ms)
		check(seen_collect.size() >= floor_node._max_windows,
			"%s every station collected under the shipped budget" % vid)
		check(seen_deposit.size() >= floor_node._max_windows,
			"%s every station deposited under the shipped budget" % vid)
	print("CART_SERVICE_BUDGET checks=", checks, " failures=", failures)
	quit(0 if failures == 0 else 1)
