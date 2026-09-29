extends SceneTree
## courier_diagnostic.gd — deterministic porter-collection diagnostic.
## Seeds RNG, runs ONE venue like test_courier_collections (bare
## _update_porters), and logs per-porter state/route/blocker each second so a
## stall can be attributed instead of guessed. Isolated profile only.

var _jobwatch_state: Dictionary = {}

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var xdg := OS.get_environment("XDG_DATA_HOME")
	if OS.get_environment("GRAND_EXHIBIT_TEST_RUN") != "1" or not xdg.begins_with("/tmp/grand-courier"):
		printerr("AUDIT_REFUSED: requires GRAND_EXHIBIT_TEST_RUN=1 and XDG_DATA_HOME=/tmp/grand-courier")
		quit(2)
		return
	var seed_used := 1201
	seed(seed_used)
	print("COURIER_DIAG seed=", seed_used)
	root.get_node("SaveSystem").set_process(false)
	var gs = root.get_node("GameState")
	gs.reset_to_new_game()
	gs.ready_flag = true
	var floor_node = load("res://scenes/venue/floor/venue_floor.tscn").instantiate()
	floor_node.set_size(Vector2(720, 760))
	root.add_child(floor_node)
	for n in root.get_children():
		n.process_mode = Node.PROCESS_MODE_DISABLED
	var vid := "whispering_pines"
	for arg in OS.get_cmdline_user_args():
		if str(arg).begins_with("venue="):
			vid = str(arg).get_slice("=", 1)
	gs.current_venue = vid
	for dept in ["ticket", "archive", "gallery", "promotions"]:
		for track in ["staff", "speed", "value"]:
			gs.set_dept_level(vid, dept, track, 8)
	floor_node.retheme(vid)
	floor_node.set_rates(root.get_node("Economy").venue_rates(vid))
	floor_node._windows_active = floor_node._max_windows
	for w in floor_node._windows_active:
		floor_node._stacks[w] = 1
	var mode := "bare"
	var budget := -1
	for arg in OS.get_cmdline_user_args():
		if str(arg).begins_with("mode="):
			mode = str(arg).get_slice("=", 1)
		if str(arg).begins_with("budget="):
			budget = int(str(arg).get_slice("=", 1))
	if budget > 0:
		floor_node._porter_planning_budget_usec = budget
		print("COURIER_DIAG budget override usec=", budget)
	print("COURIER_DIAG venue=", vid, " windows=", floor_node._windows_active,
		" porters=", floor_node._porters.size(), " mode=", mode)
	if mode == "spawncheck":
		var Geo := load("res://scenes/venue/floor/cart_traffic_geometry.gd")
		for i in floor_node._porters.size():
			for j in range(i + 1, floor_node._porters.size()):
				var a = floor_node._porters[i]
				var b = floor_node._porters[j]
				print("SPAWNCHECK p", i, " at=", str(a.pos), " hdg=", str(a.heading),
					" vs p", j, " at=", str(b.pos), " hdg=", str(b.heading),
					" overlap=", str(Geo.overlap(a.pos, Geo.heading(a), b.pos, Geo.heading(b), 0.0)))
		quit(0)
		return
	if mode == "stallsite":
		var stuck := Vector2(14.46068, 14.71068)
		var layout2 = floor_node._porter_layout
		print("STALLSITE crowd_slots_near:")
		for i in floor_node._crowd.size():
			var slot: Vector2 = floor_node._crowd_slot(i)
			if slot.distance_to(stuck) < 3.0:
				print("STALLSITE slot", i, "=", str(slot))
		print("STALLSITE porter_bays_drops_counters:")
		for d in layout2.drops:
			print("STALLSITE drop=", str((d as Dictionary).get("at", "?")))
		for c in layout2.counters:
			print("STALLSITE counter=", str((c as Dictionary).get("at", "?")))
		var oid: Vector2i = floor_node._nav_id(stuck)
		print("STALLSITE stuck_cell=", str(oid), " solid=", str(floor_node._nav.is_point_solid(oid)))
		var tid: Vector2i = floor_node._nav_id(Vector2(14.0, 14.45))
		print("STALLSITE target_cell=", str(tid), " solid=", str(floor_node._nav.is_point_solid(tid)))
		print("STALLSITE nav_ids_stuck_to_target=", str(floor_node._nav_ids(stuck, Vector2(14.0, 14.45)).size()))
		quit(0)
		return
	if mode == "overlaptrace":
		# Replicate test_cart_dispatch_service's sequential venue drive so an
		# order-dependent overlap can be told from a fresh-venue pass-by.
		# venues=comma,list (default: all in loader order).
		var Geo2 := load("res://scenes/venue/floor/cart_traffic_geometry.gd")
		var venues: Array = []
		for arg in OS.get_cmdline_user_args():
			if str(arg).begins_with("venues="):
				for name in str(arg).get_slice("=", 1).split(",", false):
					venues.append(name)
		if venues.is_empty():
			venues = root.get_node("DataLoader").venue_order()
		for vname in venues:
			gs.current_venue = vname
			for dept in ["ticket", "archive", "gallery", "promotions"]:
				for track in ["staff", "speed", "value"]:
					gs.set_dept_level(vname, dept, track, 8)
			floor_node.retheme(vname)
			floor_node.set_rates(root.get_node("Economy").venue_rates(vname))
			floor_node._windows_active = floor_node._max_windows
			for w in floor_node._windows_active:
				floor_node._stacks[w] = 1
			var logged := 0
			var venue_overlaps := 0
			for step in 6000:
				floor_node._update_porters(.05)
				for a in floor_node._porters.size():
					var pa = floor_node._porters[a]
					for b in range(a + 1, floor_node._porters.size()):
						var pb = floor_node._porters[b]
						if absf(floor_node._porter_layout._height_at(pa.pos) - floor_node._porter_layout._height_at(pb.pos)) >= 73.0:continue
						if not Geo2.overlap(pa.pos, Geo2.heading(pa), pb.pos, Geo2.heading(pb)):continue
						venue_overlaps += 1
						if logged < 12:
							print("OVERLAP venue=%s t=%.2f a=%d/%s at=%s h=%s curs=%d/%d | b=%d/%s at=%s h=%s curs=%d/%d dist=%.3f" % [
								vname, (step + 1) * 0.05, a, pa.state, str(pa.pos), str(Geo2.heading(pa)), pa.route_cursor, pa.route_steps.size(),
								b, pb.state, str(pb.pos), str(Geo2.heading(pb)), pb.route_cursor, pb.route_steps.size(),
								pa.pos.distance_to(pb.pos)])
							logged += 1
			print("OVERLAPTRACE venue=%s total=%d" % [vname, venue_overlaps])
		quit(0)
		return
	if mode == "corridor":
		var layoutc = floor_node._porter_layout
		var navc: AStarGrid2D = floor_node._nav
		for yi in range(8, 47):
			var y := float(yi) * 0.25
			var row := "y=%.2f" % y
			for xi in [3, 5, 8]:
				var at := Vector2(float(xi) * 0.25, y)
				var id := Vector2i(xi, yi)
				var solid := (not navc.region.has_point(id)) or navc.is_point_solid(id)
				var in_rect := false
				for rect in layoutc.counter_rects:
					if (rect as Rect2).has_point(at):
						in_rect = true
						break
				var near_staff := false
				for st in layoutc.fixed_staff:
					if (st as Vector2).distance_to(at) < 1.0:
						near_staff = true
						break
				row += " x=%.2f solid=%s rect=%s staff=%s fits=%s" % [
					at.x, str(solid), str(in_rect), str(near_staff),
					str(layoutc.fits(at, Vector2.DOWN, false))]
			print("CORRIDOR ", row)
		quit(0)
		return
	if mode == "routeprobe":
		var router = floor_node._porter_router
		var layout = floor_node._porter_layout
		var probe_at := Vector2(6.0, 6.0)
		var t00 := Time.get_ticks_usec()
		for i in 2000:
			layout.fits(probe_at + Vector2(0.001 * (i % 7), 0.001 * (i % 13)), Vector2.DOWN, false)
		print("COURIER_DIAG fits microbench: 2000 calls wall_usec=", Time.get_ticks_usec() - t00)
		for i in mini(3, floor_node._porters.size()):
			var pp = floor_node._porters[i]
			var dock: Dictionary = floor_node._porter_counter(i % floor_node._windows_active)
			var t0 := Time.get_ticks_usec()
			var res: Array = router.route(pp.pos, pp.heading, dock.at, dock.heading)
			var dt := Time.get_ticks_usec() - t0
			print("COURIER_DIAG direct route p=%d from=%s to=%s steps=%d expanded=%d wall_usec=%d" % [
				i, str(pp.pos), str(dock.at), res.size(), router.last_expanded, dt])
		var layout2 = floor_node._porter_layout
		print("COURIER_DIAG fit cache: hits=%d misses=%d size=%d" % [
			layout2._fit_hits, layout2._fit_misses, layout2._fit_cache.size()])
		quit(0)
		return
	var start: int = floor_node._porter_trips
	var traj: bool = mode == "traj" or mode == "long"
	var max_steps := 3000
	if mode == "long":
		max_steps = 6000
	if mode == "jobwatch":
		max_steps = 1400
	for step in max_steps:
		if mode == "full":
			floor_node.advance_sim(.05)
		else:
			floor_node._update_porters(.05)
		if step % 20 == 19:
			var t: float = (step + 1) * 0.05
			var states: Dictionary = {}
			for p in floor_node._porters:
				var jobinfo := "none"
				if p.route_job != null:
					jobinfo = "%s exp=%d" % [p.route_job.status, p.route_job.expanded]
				var req: Dictionary = floor_node._cart_dispatch._find(p)
				var reqinfo := "noreq"
				if not req.is_empty():
					reqinfo = "%s tried=%d" % [str(req.get("phase", "?")), int(req.get("tried", -9))]
				var key: String = "%s job=%s steps=%d/%d req=%s pos=%s tgt=%s" % [
					p.state, jobinfo, p.route_cursor, p.route_steps.size(), reqinfo,
					str(p.pos), str(p.target)]
				states[key] = int(states.get(key, 0)) + 1
			var disp = floor_node._cart_dispatch
			var active_phase := "none"
			var act: Dictionary = disp.active
			if not act.is_empty():
				active_phase = "%s tried=%s rev=%d" % [
					str(act.get("phase", "?")),
					str(act.get("tried", "?")), int(disp.revision)]
			print("COURIER_DIAG t=%.1f trips=%d plan_usec=%d grants=%d active=%s states=%s" % [
				t, floor_node._porter_trips - start, floor_node._porter_planning_usec,
				floor_node._cart_dispatch.grants, active_phase, str(states)])
		if traj and step % 10 == 9:
			var parts: Array = []
			for p in floor_node._porters:
				parts.append("%s|%s|%d/%d" % [str(Vector2(roundf(p.pos.x * 1000.0) / 1000.0,
					roundf(p.pos.y * 1000.0) / 1000.0)), p.state,
					p.route_cursor, p.route_steps.size()])
			print("TRAJ t=%.2f trips=%d %s" % [(step + 1) * 0.05,
				floor_node._porter_trips - start, " ".join(parts)])
		if mode == "jobwatch":
			for pi in floor_node._porters.size():
				var pp = floor_node._porters[pi]
				var jid := 0
				var jst := "none"
				var exp := -1
				if pp.route_job != null:
					jid = pp.route_job.get_instance_id()
					jst = str(pp.route_job.status)
					exp = pp.route_job.expanded
				var key := "jw%d" % pi
				var rec: Dictionary = _jobwatch_state.get(key, {})
				if int(rec.get("jid", 0)) != jid:
					var req: Dictionary = floor_node._cart_dispatch._find(pp)
					print("JOBWATCH t=%.2f p=%d job %s->%s state=%s exp=%s pos=%s hdg=%s dock=%s/%s phase=%s" % [
						(step + 1) * 0.05, pi, str(rec.get("jid", 0)), str(jid),
						pp.state, str(exp), str(pp.pos), str(pp.heading),
						str((pp.dock as Dictionary).get("at", "?")),
						str((pp.dock as Dictionary).get("heading", "?")),
						str(req.get("phase", "-"))])
					_jobwatch_state[key] = {"jid": jid}
		if floor_node._porter_trips - start >= floor_node._windows_active:
			break
	print("COURIER_DIAG_DONE trips=", floor_node._porter_trips - start,
		" dispatch=", floor_node._cart_dispatch.status_summary() if floor_node._cart_dispatch.has_method("status_summary") else "n/a")
	quit(0)
