extends SceneTree
## test_data.gd — all data/*.json parse; cost curves monotonic; venue order sorted.
## Run: godot --headless --path <repo> -s tests/core/test_data.gd

var failures := 0

func check(cond: bool, msg: String) -> void:
	if cond:
		print("  PASS ", msg)
	else:
		failures += 1
		print("  FAIL ", msg)

func _init() -> void:
	call_deferred("run")

func run() -> void:
	for pair in [["event_bus","EventBus"],["data_loader","DataLoader"],["clock_guard","ClockGuard"],["analytics","Analytics"],["ad_service","AdService"],["iap_service","IAPService"],["game_state","GameState"],["save_system","SaveSystem"],["economy","Economy"]]:
		var n: Node = load("res://autoload/%s.gd" % pair[0]).new()
		n.name = pair[1]
		root.add_child(n)

	# Under -s the main script compiles before autoload names are bound;
	# access the bootstrapped singletons via local aliases instead.
	var EventBus: Node = root.get_node("EventBus")
	var DataLoader: Node = root.get_node("DataLoader")
	var ClockGuard: Node = root.get_node("ClockGuard")
	var Analytics: Node = root.get_node("Analytics")
	var GameState: Node = root.get_node("GameState")
	var SaveSystem: Node = root.get_node("SaveSystem")
	var Economy: Node = root.get_node("Economy")

	print("-- every data/*.json parses --")
	var dir := DirAccess.open("res://data")
	check(dir != null, "data dir opens")
	var files: Array = []
	if dir:
		dir.list_dir_begin()
		var fn: String = dir.get_next()
		while fn != "":
			if fn.ends_with(".json"):
				files.append(fn)
			fn = dir.get_next()
		dir.list_dir_end()
	check(files.size() >= 8, "found %d data files (>= 8)" % files.size())
	for fn in files:
		var text := FileAccess.get_file_as_string("res://data/" + fn)
		var parsed: Variant = JSON.parse_string(text)
		check(typeof(parsed) == TYPE_DICTIONARY, "%s parses to Dictionary" % fn)

	print("-- DataLoader maps populated --")
	check(not DataLoader.core.is_empty(), "core loaded")
	check(DataLoader.venues.size() >= 1, "venues loaded (%d)" % DataLoader.venues.size())
	for dept_id in ["promotions", "ticket", "archive", "gallery"]:
		check(not DataLoader.dept_def(dept_id).is_empty(), "dept def: %s" % dept_id)

	print("-- venue_order sorted by 'order' --")
	var order: Array = DataLoader.venue_order()
	check(order.size() == DataLoader.venues.size(), "venue_order covers all venues")
	var sorted_ok := true
	var prev := -1
	for vid in order:
		var o: int = int(DataLoader.get_venue(vid).get("order", 0))
		if o <= prev:
			sorted_ok = false
		prev = o
	check(sorted_ok, "venue_order strictly ascending: %s" % str(order))

	print("-- upgrade_cost strictly monotonic in level --")
	for dept_id in ["promotions", "ticket", "archive", "gallery"]:
		for track in ["staff", "speed", "value"]:
			var mono := true
			var prev_cost := BigNumber.zero()
			for lvl in range(0, 31):
				var c: BigNumber = DataLoader.upgrade_cost(dept_id, track, lvl, 1.0, 0)
				if c.lte(prev_cost):
					mono = false
				prev_cost = c
			check(mono, "cost monotonic %s/%s (lvls 0-30)" % [dept_id, track])

	print("-- venue cost exponent scales costs --")
	var c1: BigNumber = DataLoader.upgrade_cost("ticket", "speed", 5, 1.0, 0)
	var c2: BigNumber = DataLoader.upgrade_cost("ticket", "speed", 5, 1.0, 3)
	check(is_equal_approx(c2.to_float_approx(), c1.to_float_approx() * 1000.0), "cost_exp 3 = x1000")

	print("-- reputation thresholds strictly increasing --")
	var th: Array = DataLoader.core.get("reputation", {}).get("thresholds_mantissa", [])
	check(th.size() >= 10, "rep thresholds present (%d)" % th.size())
	var th_ok := true
	for i in range(1, th.size()):
		if float(th[i]) <= float(th[i - 1]):
			th_ok = false
	check(th_ok, "thresholds strictly increasing")

	print("-- economy config sane --")
	var eco: Dictionary = DataLoader.core.get("economy", {})
	check(int(eco.get("offline_cap_hours", 0)) > 0, "offline_cap_hours > 0")
	check(int(eco.get("tick_hz", 0)) >= 1, "tick_hz >= 1")

	print("-- lootbox rarity weights sum to 1.0 (if present) --")
	for box_id in DataLoader.lootboxes.keys():
		var w: Dictionary = DataLoader.lootboxes[box_id].get("rarity_weights", {})
		if w.is_empty():
			continue
		var sum := 0.0
		for k in w.keys():
			sum += float(w[k])
		check(absf(sum - 1.0) < 0.001, "lootbox %s weights sum 1.0 (got %f)" % [box_id, sum])

	print("-- venue-1 pacing guardrails --")
	# First upgrade must be affordable within 60s of fresh-game income.
	GameState.reset_to_new_game()
	var vid: String = DataLoader.venue_order()[0]
	var rate: float = Economy.current_cash_per_second().to_float_approx()
	var cheapest := INF
	for dept_id in ["promotions", "ticket", "archive", "gallery"]:
		for track in ["staff", "speed", "value"]:
			var lvl: int = GameState.dept_level(vid, dept_id, track)
			if track == "staff":
				lvl = int(GameState.venue_state(vid)["depts"][dept_id]["staff"])
			var c: float = DataLoader.upgrade_cost(dept_id, track, lvl, 1.0, 0).to_float_approx()
			if c < cheapest:
				cheapest = c
	check(rate > 0.0, "fresh income rate > 0 (%f/s)" % rate)
	check(cheapest / rate < 60.0, "first upgrade affordable in %.1fs (< 60s)" % (cheapest / rate))
	var venue_caps: Array[int] = []
	for venue_id in DataLoader.venue_order():
		venue_caps.append(int(DataLoader.get_venue(venue_id).get("track_level_cap", 0)))
	check(venue_caps[0] <= 20,
		"intro venue is deliberately short (track cap %d <= 20)" % venue_caps[0])
	check(venue_caps.max() <= 100,
		"no venue asks for levels beyond the reference-style cap (max %d)" % venue_caps.max())
	var caps_grow := true
	for i in range(1, venue_caps.size()):
		caps_grow = caps_grow and venue_caps[i] >= venue_caps[i - 1]
	check(caps_grow and venue_caps.back() == 100,
		"venue caps grow then hold the reference-style Lv.100 ceiling %s" % str(venue_caps))

	print("RESULT: ", "ALL PASS" if failures == 0 else "%d FAILURES" % failures)
	quit(0 if failures == 0 else 1)
