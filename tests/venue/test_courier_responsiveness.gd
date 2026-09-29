extends SceneTree
## test_courier_responsiveness.gd — courier service responsiveness bounds.
##
## The 150-second full-service bound in test_courier_collections.gd stays
## untouched: round trips on large venues are travel-bound (~85 sim-sec each
## with the pinned walk cadence), which no planner tuning can shorten. These
## are the three separate checks that gate planning health instead:
##  1. STARVATION: with tills full and three couriers staged, every courier
##     must hold an active route search or admitted steps within 30 sim-sec.
##  2. PROGRESS: each eligible courier's search must measurably advance inside
##     a 15 sim-sec window (samples at t=30 and t=45). Job allocation alone
##     does not prove service: only growing step counts, same-job expansion
##     growth, or physical movement count. Unchanged arrays and brand-new
##     unexpanded jobs do not.
##  3. FIRST DELIVERY: the first single-sale batch must reach the archive
##     within 240 sim-seconds of scenario start: 30 starvation window plus 15
##     progress window plus 195 here, so the bound is a true total.
## Whispering_pines, seed 1201, bare _update_porters like the collections
## test. Starvation and progress fail on pre-rotation scheduling and pass with
## fair time-slicing (measured: all searching by t=2, first trip t=171).

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

## Per-porter planning snapshot: route-job identity and expansions, admitted
## steps, and position. Two snapshots delimit one measurement window.
func _progress_snapshot(floor_node: Node) -> Dictionary:
	var out: Dictionary = {}
	for p in floor_node._porters:
		var req: Dictionary = floor_node._cart_dispatch._find(p)
		out[p] = {
			"job": p.route_job.get_instance_id() if p.route_job != null else 0,
			"exp": int(p.route_job.expanded) if p.route_job != null else -1,
			"steps": (p.route_steps as Array).size(),
			"pos": (p.pos as Vector2),
			"phase": str(req.get("phase", "")),
			"cursor": int(req.get("check_cursor", -1)),
		}
	return out

func run() -> void:
	if not OS.has_environment("GRAND_EXHIBIT_TEST_RUN"):
		printerr("REFUSED: requires GRAND_EXHIBIT_TEST_RUN isolation")
		quit(2)
		return
	root.get_node("SaveSystem").set_process(false)
	var gs = root.get_node("GameState")
	gs.reset_to_new_game()
	gs.ready_flag = true
	seed(1201)
	var floor_node = load("res://scenes/venue/floor/venue_floor.tscn").instantiate()
	floor_node.set_size(Vector2(720, 760))
	root.add_child(floor_node)
	for n in root.get_children():
		n.process_mode = Node.PROCESS_MODE_DISABLED
	var vid := "whispering_pines"
	gs.current_venue = vid
	for dept in ["ticket", "archive", "gallery", "promotions"]:
		for track in ["staff", "speed", "value"]:
			gs.set_dept_level(vid, dept, track, 8)
	floor_node.retheme(vid)
	floor_node.set_rates(root.get_node("Economy").venue_rates(vid))
	floor_node._windows_active = floor_node._max_windows
	for w in floor_node._windows_active:
		floor_node._stacks[w] = 1
	var spawns: Dictionary = {}
	for p in floor_node._porters:
		spawns[p] = (p.pos as Vector2)
 # 1. Starvation: 30 sim-seconds in, nobody may still be waiting for a
 # first planning slice while requests are pending.
	for step in 600:
		floor_node._update_porters(.05)
	var starved: Array = []
	for p in floor_node._porters:
		var engaged: bool = p.route_job != null or not (p.route_steps as Array).is_empty() \
			or (p.pos as Vector2).distance_to(spawns[p]) > 0.05
		if not engaged:
			starved.append(floor_node._porters.find(p))
	check(starved.is_empty(), "no courier starves for planning within 30 sim-sec (starved=%s)" % str(starved))
 # 2. Progress under contention: an allocated job is not proof of service.
 # Sample every courier's search at 15 and 30 sim-sec; each eligible courier
 # must show measurable forward motion (growing expansions, admitted steps,
 # or physical movement). A scheduler that parks two searches while one runs
 # fails here even though every porter trivially "has" a job at some point.
	var snap_a: Dictionary = _progress_snapshot(floor_node)
	for step in 300:
		floor_node._update_porters(.05)
	var snap_b: Dictionary = _progress_snapshot(floor_node)
	var stalled: Array = []
	for p in floor_node._porters:
		var a: Dictionary = snap_a[p]
		var b: Dictionary = snap_b[p]
		# Progress means GROWTH, not mere possession: admitted steps must
		# extend, the same search must expand further, the porter must have
		# moved, or its planning must have advanced to a later phase / pose
		# cursor. Fairness covers every phase, so a porter legitimately deep
		# in envelope or validation work during the window is progress, while
		# a brand-new unexpanded job and an unchanged phase are not.
		var steps_grew: bool = int(b.get("steps", 0)) > int(a.get("steps", 0))
		var same_job_grew: bool = int(b.get("job", 0)) != 0 \
			and int(b.get("job", 0)) == int(a.get("job", 0)) \
			and int(b.get("exp", -1)) > int(a.get("exp", -1))
		var moved: bool = (b.pos as Vector2).distance_to(a.pos) > 0.05
		var phase_advanced: bool = str(b.get("phase", "")) != str(a.get("phase", "")) \
			or int(b.get("cursor", -1)) > int(a.get("cursor", -1))
		if not (steps_grew or same_job_grew or moved or phase_advanced):
			stalled.append(floor_node._porters.find(p))
			printerr("STALLED_PROGRESS p=", floor_node._porters.find(p),
				" before=", str(a), " after=", str(b))
	check(stalled.is_empty(), "every courier advances its search within 15 sim-sec windows (stalled=%s)" % str(stalled))
 # 3. First delivery: the service must complete end to end within 240
 # sim-seconds TOTAL (30 starvation window + 15 progress window + 195 here).
 # Planning runs unlimited from here: the per-call budget is a wall-clock
 # slice, so leaving it shipped made this bound a host-speed benchmark
 # (interleaved runs of identical code passed idle and failed under load).
 # Starvation and progress above keep the shipped budget - that is where
 # scheduler discrimination lives - while budget-limited service timing is
 # covered by test_cart_dispatch_service's 300s bound (~212s measured).
	floor_node._porter_planning_budget_usec = 0
	var start_trips: int = floor_node._porter_trips
	var delivered := false
	for step in 3900:
		floor_node._update_porters(.05)
		if floor_node._porter_trips > start_trips:
			delivered = true
			break
	check(delivered, "first single-sale batch reaches the archive within 240 sim-sec total")
	print("COURIER_RESPONSIVENESS checks=", checks, " failures=", failures)
	quit(0 if failures == 0 else 1)
