extends SceneTree
## QA M5-6: performance sanity (headless wall-clock proxies).
## - Economy.venue_rates with fully-maxed departments x 10,000 calls < 2s
##   (proxy for per-tick economy cost; tick_hz=10 -> 100x real-time headroom).
## - match-3 engine: 1,000 fresh boards (generate + swap attempts + resolve
##   cascades) < 5s.
## Run: godot --headless --path <repo> -s tests/qa/test_performance.gd

var failures: int = 0

func check(cond: bool, msg: String) -> void:
	if cond:
		print("  PASS ", msg)
	else:
		failures += 1
		printerr("  FAIL ", msg)

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var DL: Node = root.get_node("DataLoader")
	var GS: Node = root.get_node("GameState")
	var ECON: Node = root.get_node("Economy")
	DL.reload_all()
	GS.reset_to_new_game()
	GS.ready_flag = false

	print("-- venue_rates x 10,000 with maxed departments --")
	var vid: String = GS.current_venue
	# Max out per mandate: promotions 25 staff, archive 12, gallery 12, levels 50.
	var vs: Dictionary = GS.venue_state(vid)
	vs["depts"]["promotions"]["staff"] = 25
	vs["depts"]["archive"]["staff"] = 12
	vs["depts"]["gallery"]["staff"] = 12
	vs["depts"]["ticket"]["staff"] = 10  # ticket max_staff per data
	for dept in ["promotions", "ticket", "archive", "gallery"]:
		GS.set_dept_level(vid, dept, "speed", 50)
		GS.set_dept_level(vid, dept, "value", 50)
	var warm: Dictionary = ECON.venue_rates(vid)
	check(warm.has("banked_per_s"), "venue_rates returns full dict when maxed")
	var t0: int = Time.get_ticks_msec()
	var sink: float = 0.0
	for i in range(10000):
		var r: Dictionary = ECON.venue_rates(vid)
		sink += r["arrival_per_s"]  # prevent any illusion the call is skippable
	var venue_ms: int = Time.get_ticks_msec() - t0
	print("  venue_rates x10,000 (maxed): %d ms (sink=%.1f)" % [venue_ms, sink])
	check(venue_ms < 2000, "venue_rates x10,000 < 2000ms (got %dms)" % venue_ms)

	print("-- match-3: 1,000 boards generate + resolve --")
	var M3: GDScript = load("res://scripts/events/match3_engine.gd")
	check(M3 != null and M3.can_instantiate(), "match3_engine.gd compiles")
	var t1: int = Time.get_ticks_msec()
	var clears: int = 0
	var rng := RandomNumberGenerator.new()
	rng.seed = 42
	for b in range(1000):
		var eng: RefCounted = M3.new(b)
		eng.set_team([0, 1, 2])
		eng.generate()
		# A few swap attempts per board: valid swaps trigger _resolve with cascades.
		for attempt in range(6):
			var a := Vector2i(rng.randi_range(0, 7), rng.randi_range(0, 7))
			var dir: Array[Vector2i] = [Vector2i(1, 0), Vector2i(0, 1)]
			var d: Vector2i = dir[rng.randi_range(0, 1)]
			var bp := a + d
			if bp.x > 7 or bp.y > 7:
				continue
			if eng.can_swap(a, bp):
				var res: Dictionary = eng.try_swap(a, bp)
				clears += int(res.get("cleared", 0))
		# Force one raw resolve pass too (covers cascade/refill path on every board).
		eng._resolve()
	var match3_ms: int = Time.get_ticks_msec() - t1
	print("  match-3 x1,000 boards: %d ms (cells cleared: %d)" % [match3_ms, clears])
	check(match3_ms < 5000, "match-3 x1,000 boards < 5000ms (got %dms)" % match3_ms)
	check(clears > 0, "match-3 boards actually resolved matches (cleared=%d)" % clears)

	print("---")
	if failures == 0:
		print("ALL QA PERFORMANCE TESTS PASSED")
	else:
		printerr("QA PERFORMANCE TESTS FAILED: %d" % failures)
	quit(0 if failures == 0 else 1)
