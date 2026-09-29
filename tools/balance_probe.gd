extends SceneTree
## Headless balance probe: a greedy player in one museum. Every simulated
## second it banks income, buys the cheapest affordable upgrade (department
## tracks and station items), and lets quests/milestones evaluate. Prints a
## timeline so unlock gates and prices can be tuned against real progress.
##
##   GRAND_EXHIBIT_TEST_RUN=1 godot --headless --path . -s tools/balance_probe.gd -- venue=whispering_pines hours=6
func _initialize() -> void:call_deferred("run")
func run() -> void:
	var args := {}
	for a in OS.get_cmdline_user_args():
		var kv := (a as String).split("=", true, 1)
		if kv.size() == 2: args[kv[0]] = kv[1]
	var gs: Node = root.get_node("GameState")
	var ec: Node = root.get_node("Economy")
	var dl: Node = root.get_node("DataLoader")
	root.get_node("SaveSystem").set_process(false)
	ec.set_process(false)
	gs.reset_to_new_game(); gs.ready_flag = true
	var vid := str(args.get("venue", gs.current_venue))
	if vid != gs.current_venue:
		gs.venues_unlocked.append(vid); gs.current_venue = vid
	var QS: GDScript = load("res://scripts/meta/quest_system.gd")
	var WS: GDScript = load("res://scripts/meta/wing_system.gd")
	QS.ensure_active_quests(vid)
	var hours := float(args.get("hours", "4"))
	var ms_seen := 0
	var next_report := 0.0
	var depts := ["ticket", "gallery", "archive", "promotions"]
	for t in range(int(hours * 3600.0)):
		ec._tick(1.0)
		# Greedy: cheapest affordable purchase, a few per second at most.
		for _k in 4:
			var best := {}
			var best_cost: BigNumber = null
			for d in depts:
				for tr in ["staff", "speed", "value"]:
					var lvl: int = gs.dept_items(vid, d).size() if tr == "staff" else gs.dept_level(vid, d, tr)
					if tr != "staff" and lvl >= ec.track_max_level(vid, tr): continue
					if tr == "staff" and lvl >= ec.max_staff(vid, d): continue
					var c: BigNumber = ec._cost(vid, d, tr, lvl)
					if best_cost == null or c.lt(best_cost):
						best_cost = c; best = {"d": d, "tr": tr}
				for i in gs.dept_items(vid, d).size():
					if gs.item_level(vid, d, i) >= ec.item_max_level(): continue
					var ic: BigNumber = ec.item_upgrade_cost(vid, d, i)
					if best_cost == null or ic.lt(best_cost):
						best_cost = ic; best = {"d": d, "i": i}
			if best_cost == null or gs.cash.lt(best_cost): break
			if best.has("i"): ec.purchase_item_upgrade(vid, best["d"], best["i"])
			else: ec.purchase_upgrade(vid, best["d"], best["tr"])
		if t % 5 == 0: QS.evaluate(vid)
		var nw: Dictionary = WS.next_wing(vid)
		if not nw.is_empty() and WS.status(vid, str(nw["id"])) == "ready":
			var wp: BigNumber = WS.price(vid, str(nw["id"]))
			if WS.renovate(vid, str(nw["id"])):
				print("WING %s at %d min for %s" % [nw["id"], t / 60, wp.to_notation()])
		var ms: int = (gs.venue_state(vid).get("milestones", []) as Array).size()
		if ms != ms_seen or float(t) >= next_report:
			if ms != ms_seen: print("MILESTONE ", ms, " at ", t / 60, " min")
			ms_seen = ms
			next_report = float(t) + 1800.0
			var r: Dictionary = ec.venue_rates(vid)
			print("t=%dmin cash=%s rate=%s/s rep=%d gal.value=%d tix.speed=%d staff=%s" % [t / 60, gs.cash.to_notation(),
				(r["banked_per_s"] as BigNumber).to_notation(), gs.rep_level(), gs.dept_level(vid, "gallery", "value"),
				gs.dept_level(vid, "ticket", "speed"), str(depts.map(func(d): return gs.dept_items(vid, d).size()))])
			print("   ref gallery.value cost L10=%s L20=%s L30=%s L40=%s" % [ec._cost(vid, "gallery", "value", 10).to_notation(),
				ec._cost(vid, "gallery", "value", 20).to_notation(), ec._cost(vid, "gallery", "value", 30).to_notation(), ec._cost(vid, "gallery", "value", 40).to_notation()])
	quit(0)
