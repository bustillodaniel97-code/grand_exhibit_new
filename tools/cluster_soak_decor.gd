extends SceneTree
## cluster_soak_decor.gd — WORLD-OPEN soak beyond the already-covered cases.
##
## Covered before: 600 simulated seconds fresh-load at 0.1s and 60Hz, plus a
## bench added at 60s, on current and 8174c748 baselines — no large freeze.
## This extends to: multiple venues, live furniture buy/place/swap + dept
## upgrades while guests are seated/walking, a mid-soak save/load (suspend),
## and compact census diffs to tell capacity waits from stalls.
## Deterministic seed is logged; run with an isolated /tmp/grand-audit-world
## profile. Exits 0 with a census summary; a stall is reported as STALLED_*,
## not hidden. It does NOT claim the authentic live freeze reproduced unless
## a large stationary gallery group actually appears.

## load() at runtime, NOT preload(): these helpers name autoloads at class scope
## and preloading them under -s compiles them before autoload names are bound,
## leaving dead objects whose calls silently no-op.
var DecorSystem: GDScript

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var xdg := OS.get_environment("XDG_DATA_HOME")
	if OS.get_environment("GRAND_EXHIBIT_TEST_RUN") != "1" or not xdg.begins_with("/tmp/grand-audit-world"):
		printerr("AUDIT_REFUSED: requires GRAND_EXHIBIT_TEST_RUN=1 and XDG_DATA_HOME=/tmp/grand-audit-world")
		quit(2)
		return
	var seed_used := 20260919
	seed(seed_used)
	print("CLUSTER_SOAK seed=", seed_used)
# Long-soak support: GRAND_SOAK_SCALE multiplies the per-venue simulated
# seconds (default 900). A scale-4 run covers 3 sim-hours in one logged
# background process instead of many short tool calls.
	var scale := 1
	if OS.has_environment("GRAND_SOAK_SCALE"):
		scale = clampi(int(OS.get_environment("GRAND_SOAK_SCALE")), 1, 8)
	var ticks_per_venue := 9000 * scale
	print("CLUSTER_SOAK scale=", scale, " ticks_per_venue=", ticks_per_venue)
	DecorSystem = load("res://scripts/meta/decor_system.gd") as GDScript
	var saves = root.get_node("SaveSystem")
	saves.set_process(false)
	var gs = root.get_node("GameState")
	gs.reset_to_new_game()
	gs.ready_flag = true
	# Fund so decor/upgrades can be bought live mid-soak.
	gs.cash = BigNumber.from_parts(5.0, 9)
	gs.gems = 100000
	var venues: Array[String] = ["whispering_pines", "copper_kettle", "grand_river"]
	var total_stalled := 0
	var recoveries := 0
	var giveups := 0
	var track_state: Dictionary = {}
	for vi in venues.size():
		var vid: String = venues[vi]
		gs.current_venue = vid
		var f: Node = load("res://scenes/venue/floor/venue_floor.tscn").instantiate()
		f.size = Vector2(720, 760)
		root.add_child(f)
		for n in root.get_children():
			n.process_mode = Node.PROCESS_MODE_DISABLED
		f._porter_planning_budget_usec = 0
		f.set_rates(root.get_node("Economy").venue_rates(vid))
		var birth: Dictionary = {}
		var last_pos: Dictionary = {}
		# 900 simulated seconds per venue at 0.1s ticks.
		for tick in ticks_per_venue:
			var elapsed: float = (tick + 1) * 0.1
			# Live mutations while guests are active (beyond the covered bench-at-60s).
			if tick == 600:
				var ok: bool = DecorSystem.buy_decor(vid, "oak_bench")
				print("CLUSTER_SOAK venue=", vid, " t=60s buy oak_bench=", ok, " seats=", f._seats.size())
			if tick == 1800:
				var ok2: bool = DecorSystem.buy_decor(vid, "brass_fountain")
				print("CLUSTER_SOAK venue=", vid, " t=180s buy brass_fountain=", ok2, " seats=", f._seats.size())
			if tick == 3000:
				# Dept upgrade while walking/seated: exercises route invalidation.
				gs.set_dept_level(vid, "gallery", "speed", 2)
				f.set_rates(root.get_node("Economy").venue_rates(vid))
				print("CLUSTER_SOAK venue=", vid, " t=300s gallery speed->2")
			if tick == 3600:
				# Live removal with guests seated/walking: the seat fix must
				# release occupants to standing/leaving without freezing them.
				var removed: bool = DecorSystem.remove_decor(vid, "oak_bench")
				print("CLUSTER_SOAK venue=", vid, " t=360s remove oak_bench=", removed,
					" seats=", f._seats.size(), " visitors=", f._visitors.size())
			if tick == 3900:
				var replaced: bool = DecorSystem.place_decor(vid, "oak_bench")
				print("CLUSTER_SOAK venue=", vid, " t=390s re-place oak_bench=", replaced,
					" seats=", f._seats.size())
			if tick == 4500:
				# Suspend/resume: save, wipe live state, reload (process death).
				saves.save_now()
				gs.reset_to_new_game()
				gs.ready_flag = true
				var reloaded: bool = saves.load_game()
				print("CLUSTER_SOAK venue=", vid, " t=450s suspend/resume reloaded=", reloaded)
				f.set_rates(root.get_node("Economy").venue_rates(vid))
			f.advance_sim(0.1)
			for v in f._visitors:
				var id: int = v.node.get_instance_id()
				if not birth.has(id):
					birth[id] = elapsed
					last_pos[id] = {"pos": v.pos, "t": elapsed}
				else:
					var rec: Dictionary = last_pos[id]
					if (v.pos as Vector2).distance_to(rec["pos"]) > 0.05:
						rec["pos"] = v.pos
						rec["t"] = elapsed
			if tick % 300 == 299:
				var states: Dictionary = {}
				for v in f._visitors:
					states[v.state] = int(states.get(v.state, 0)) + 1
				print("CLUSTER_SOAK venue=", vid, " seconds=", elapsed, " states=", states,
					" visitors=", f._visitors.size(), " departed=", f._journeys.completed,
					" unreachable=", f._unreachable_targets)
			# Every 120s, report actors stationary >60s (potential stall, not capacity).
			if tick % 1200 == 1199:
				var stalled: Array = []
				for v in f._visitors:
					var id2: int = v.node.get_instance_id()
					var rec2: Dictionary = last_pos.get(id2, {})
					if rec2.is_empty():
						continue
					var idle_for: float = elapsed - float(rec2.get("t", elapsed))
					if idle_for > 60.0 and v.state in ["browse", "crowd", "queue", "to_crowd", "rest"]:
						# Blocker identity: which porter cart (if any) covers the
						# visitor's next waypoint or target. This is the check the
						# previous soak could not answer - "cart-blocked" was an
						# inference from player-visible behaviour.
						var aim: Vector2 = (v.path as Array)[0] if not (v.path as Array).is_empty() else (v.target as Vector2)
						var blockers: Array = []
						for pi in f._porters.size():
							var pp = f._porters[pi]
							if not pp.staged: continue
							var d: float = (pp.pos as Vector2).distance_to(aim)
							if d <= 1.2:
								blockers.append({"porter": pi, "state": pp.state,
									"pos": str(pp.pos), "dist": snappedf(d, 0.01),
									"motion": not (pp.motion_step as Dictionary).is_empty()})
						stalled.append({"id": id2, "state": v.state, "idle_for": idle_for,
							"pos": str(v.pos), "target": str(v.target),
							"path_len": (v.path as Array).size(), "seat": v.seat,
							"crowd_travel": snappedf(v.crowd_travel, 0.1),
							"blockers": blockers})
				if not stalled.is_empty():
					total_stalled += stalled.size()
					print("STALLED_CANDIDATES venue=", vid, " t=", elapsed, " count=", stalled.size(), " ", stalled.slice(0, 5))
				# Visitor recovery: re-holds (target changed while walking to the
				# crowd), admissions after a timeout, and give-ups. A soak that
				# recovers proves the fix path fires in vivo; one that does not is
				# the next bug.
				for v in f._visitors:
					var id3: int = v.node.get_instance_id()
					var seen: Dictionary = track_state.get(id3, {})
					if seen.is_empty():
						track_state[id3] = {"state": v.state, "target": v.target}
						continue
					if str(seen.get("state", "")) == "to_crowd" and v.state == "to_crowd" \
							and not (v.target as Vector2).is_equal_approx(seen.get("target", v.target)):
						print("RECOVERY venue=", vid, " t=", elapsed, " id=", id3,
							" to_crowd re-held from ", str(seen.get("target")), " to ", str(v.target))
						recoveries += 1
					if v.state == "admission_full" and str(seen.get("state", "")) != "admission_full":
						print("RECOVERY venue=", vid, " t=", elapsed, " id=", id3,
							" gave up after sealed crowd slots")
						giveups += 1
					track_state[id3] = {"state": v.state, "target": v.target}
				# Compact census sample (first 5) for evidence.
				var census: Array = f.visitor_census() if f.has_method("visitor_census") else []
				print("CENSUS venue=", vid, " t=", elapsed, " sample=", census.slice(0, 5))
		# Venue change with active guests: retheme must clear without leaking.
		if vi + 1 < venues.size():
			var before: int = f._visitors.size()
			gs.current_venue = venues[vi + 1]
			f.retheme(venues[vi + 1])
			print("CLUSTER_SOAK venue change ", vid, "->", venues[vi + 1],
				" cleared=", before, " now=", f._visitors.size())
		f.queue_free()
		await create_timer(0.1).timeout
	print("CLUSTER_SOAK_DONE venues=", venues.size(), " total_stalled_candidates=", total_stalled,
		" to_crowd_recoveries=", recoveries, " crowd_giveups=", giveups)
	if total_stalled > 0:
		print("CLUSTER_SOAK_RESULT: stationary candidates seen; inspect STALLED_CANDIDATES above — not yet proven as the authentic live freeze")
	else:
		print("CLUSTER_SOAK_RESULT: no large stationary gallery group in this soak; WORLD-OPEN remains open")
	quit(0)
