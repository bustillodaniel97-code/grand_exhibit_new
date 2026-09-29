extends SceneTree
## Dig Site mini game: site generation, the pick/brush rules, energy, finds,
## recovering an artifact into the museum's collection (and its income bonus),
## and the screen's tap path.

var failures := 0

func check(ok: bool, message: String) -> void:
	if ok:
		print("PASS: ", message)
	else:
		failures += 1
		printerr("FAIL: ", message)

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var dl: Node = root.get_node("DataLoader")
	var gs: Node = root.get_node("GameState")
	var ec: Node = root.get_node("Economy")
	root.get_node("SaveSystem").set_process(false)
	ec.set_process(false)
	dl.reload_all()
	gs.reset_to_new_game()
	gs.ready_flag = true
	var DL: GDScript = load("res://scripts/digsite/dig_logic.gd")
	var DS: GDScript = load("res://scripts/digsite/dig_system.gd")
	var cfg: Dictionary = DS.config()
	var vid: String = gs.current_venue

	# --- every museum has a themed site of five artifacts
	for v in dl.venue_order():
		var arts: Array = DS.artifacts(str(v))
		check(arts.size() == 5 and str(DS.site_def(str(v)).get("name", "")) != "", "%s has a named site with five artifacts" % v)
		for a in arts:
			check(ResourceLoader.exists("res://art3d/artifacts/%s.glb" % str(a["shape"])), "%s/%s has a model (%s)" % [v, a["id"], a["shape"]])

	# --- generation
	var skull: Dictionary = DS.artifact(vid, "trex_skull")
	var a1: Dictionary = DL.generate(vid, skull, cfg, 42)
	var a2: Dictionary = DL.generate(vid, skull, cfg, 42)
	check(a1 == a2, "sites are deterministic per seed")
	check((a1["art_cells"] as Array).size() == 6, "the skull covers its six-cell footprint")
	var clash := false
	for i in a1["art_cells"]:
		clash = clash or i in (a1["rock"] as Array) or (a1["finds"] as Dictionary).has(str(i))
	check(not clash, "rocks and finds never sit on the artifact")
	check((a1["flags"] as Array).size() == 2, "two survey flags mark the artifact")

	# --- tools
	var site: Dictionary = DL.generate(vid, skull, cfg, 7)
	var art_i: int = int(site["art_cells"][0])
	var ax := art_i % int(site["cols"])
	var ay := art_i / int(site["cols"])
	var r: Dictionary = DL.dig(site, ax, ay, "brush", cfg)
	check(bool(r["ok"]) and int(r["removed"]) == 1 and DL.layers_at(site, art_i) == 2, "the brush clears one layer")
	r = DL.dig(site, ax, ay, "brush", cfg)
	check(DL.peeks(site, art_i), "one layer above the artifact, it peeks through")
	r = DL.dig(site, ax, ay, "pick", cfg)
	check(bool(r["cracked"]) and int(site["damage"]) == 1, "the pick breaking onto the artifact cracks it")
	var art2: int = int(site["art_cells"][1])
	var bx := art2 % int(site["cols"])
	var by := art2 / int(site["cols"])
	r = DL.dig(site, bx, by, "pick", cfg)
	check(int(r["removed"]) == 2 and not bool(r["cracked"]), "a pick through fresh soil is safe (3 -> 1)")
	r = DL.dig(site, bx, by, "brush", cfg)
	check(not bool(r["cracked"]) and DL.layers_at(site, art2) == 0, "the brush exposes the artifact safely")
	var rock_i: int = int(site["rock"][0])
	var rx := rock_i % int(site["cols"])
	var ry := rock_i / int(site["cols"])
	r = DL.dig(site, rx, ry, "brush", cfg)
	check(not bool(r["ok"]) and str(r["reason"]) == "rock", "the brush cannot break rock")
	r = DL.dig(site, rx, ry, "pick", cfg)
	check(bool(r["ok"]) and int(r["removed"]) == 1, "the pick chips rock one layer at a time")
	check(str(DL.dig(site, bx, by, "brush", cfg)["reason"]) == "empty", "a bare cell has nothing left to dig")
	for i in site["art_cells"]:
		while DL.layers_at(site, int(i)) > 0:
			DL.dig(site, int(i) % int(site["cols"]), int(i) / int(site["cols"]), "brush", cfg)
	check(DL.complete(site) and bool(site["done"]), "clearing every artifact cell completes the site")
	check(DL.quality(site) == 2, "one crack costs one star")

	# --- the system: energy, finds, recovery, collection bonus
	gs.dig_state = {}
	var base_mult: float = ec.income_multiplier(vid)
	check(DS.energy() == DS.max_energy(), "a new player starts with full energy")
	var cur: Dictionary = DS.current_site(vid)
	check(str(cur["artifact"]) != "" and DS.collection(vid).is_empty(), "the first site buries an uncollected artifact")
	var first_art := str(cur["artifact"])
	check(str(DS.artifact(vid, first_art).get("rarity", "")) == "common", "the first dig is a common find")
	var e0: int = DS.energy()
	var res: Dictionary = DS.swing(vid, 0, 0, "brush") if DL.layers_at(cur, 0) > 0 and not DL.is_rock(cur, 0) else DS.swing(vid, 0, 0, "pick")
	check(bool(res["ok"]) and DS.energy() == e0 - 1, "a swing costs one energy")
	# find a gems cell and dig it out
	var gem_key := ""
	for k in (cur["finds"] as Dictionary).keys():
		if str(cur["finds"][k]["kind"]) == "gems":
			gem_key = str(k)
	var gems_before: int = gs.gems
	var gi := int(gem_key)
	var got := {}
	for _n in 3:
		var rr: Dictionary = DS.swing(vid, gi % int(cur["cols"]), gi / int(cur["cols"]), "brush")
		if not (rr.get("find", {}) as Dictionary).is_empty():
			got = rr["find"]
	check(str(got.get("kind", "")) == "gems" and gs.gems > gems_before, "digging out a gem cache pays gems")
	# energy runs out
	gs.dig_state["energy"] = 0.0
	gs.dig_state["energy_t"] = int(Time.get_unix_time_from_system())
	check(str(DS.swing(vid, 1, 1, "pick").get("reason", "")) == "energy", "no energy, no swing")
	gs.dig_state["energy_t"] = int(Time.get_unix_time_from_system()) - DS.regen_seconds() * 5 - 3
	check(DS.energy() == 5, "energy regenerates over time (5 points)")
	gs.dig_state["energy"] = 999.0
	# recover the artifact with the brush (no cracks)
	var rec := {}
	for i in cur["art_cells"]:
		while DL.layers_at(cur, int(i)) > 0:
			var rr: Dictionary = DS.swing(vid, int(i) % int(cur["cols"]), int(i) / int(cur["cols"]), "brush")
			if bool(rr.get("complete", false)):
				rec = rr
	check(str(rec.get("artifact", "")) == first_art and int(rec.get("quality", 0)) == 3, "a careful dig recovers a 3-star artifact")
	check(DS.collection(vid).get(first_art, 0) == 3, "the artifact joins the museum's collection")
	check(int(rec.get("bonus_gems", 0)) > 0, "a first find pays gems")
	check(ec.income_multiplier(vid) > base_mult * 1.03, "the collection raises the museum's income")
	var nxt: Dictionary = DS.next_site(vid)
	check(str(nxt["artifact"]) != first_art, "the next site digs for something new")

	# --- the screen: tapping through to a recovery
	var screen: Control = (load("res://scenes/digsite/dig_site_screen.tscn") as PackedScene).instantiate()
	screen.size = Vector2(700, 1100)
	root.add_child(screen)
	await process_frame
	await process_frame
	var s2: Dictionary = DS.current_site(vid)
	screen.set_tool("brush")
	for i in s2["art_cells"]:
		while DL.layers_at(s2, int(i)) > 0:
			screen.swing_at(int(i) % int(s2["cols"]), int(i) / int(s2["cols"]))
	await create_timer(1.6).timeout
	var result: Control = screen.find_child("Result", true, false)
	check(result != null and result.visible, "recovering an artifact shows the result card")
	check(DS.collection(vid).size() == 2, "the screen path adds to the collection")
	var cam: Camera3D = screen.pit.camera
	var centre: Vector3 = screen.pit.cell_center(3, 4, 0.0)
	var cell: Array = screen.pit.cell_at(cam.unproject_position(Vector3(centre.x, -0.15, centre.z)))
	check(cell == [3, 4], "a tap on the pit resolves to its cell (%s)" % str(cell))
	screen.queue_free()
	await process_frame
	print("RESULT: ", "OK" if failures == 0 else "FAILED (%d)" % failures)
	quit(1 if failures > 0 else 0)
