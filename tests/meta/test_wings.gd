extends SceneTree
## Wings (data/wings.json + scripts/meta/wing_system.gd): floors that open while
## you play a museum, in order, behind its goal milestones, each raising income,
## department slots and upgrade caps, and together the museum's grandeur.

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
	var WS: GDScript = load("res://scripts/meta/wing_system.gd")
	var PS: GDScript = load("res://scripts/meta/prestige_system.gd")
	var BN: GDScript = load("res://scripts/core/big_number.gd")
	var vid: String = gs.current_venue

	var wings: Array = WS.wings(vid)
	var ids := wings.map(func(w: Dictionary) -> String: return str(w["id"]))
	check(ids == ["hall_of_giants", "sky_terrace", "gilded_facade"], "museum 1 opens 2F, 3F, then the facade: %s" % str(ids))
	check(WS.floor_layouts(vid).size() == 2, "two wings are real floors with a 3D layout")
	check(WS.status(vid, "hall_of_giants") == "locked", "2F starts locked")
	check("milestone 2" in WS.requirement_text(vid, WS.wing(vid, "hall_of_giants")), "locked wing names its milestone")
	check(WS.grandeur_tier(vid) == 1 and WS.grandeur_name(vid) == "Humble", "a new museum is Humble")

	var base_cap: int = ec.track_max_level(vid, "speed")
	var base_staff: int = ec.max_staff(vid, "gallery")

	# Meet the first gate.
	var ms: Array = []
	for m in dl.milestones.get(vid, []):
		ms.append(str(m["id"]))
	gs.venue_state(vid)["milestones"] = ms.slice(0, 2)
	var base_income: float = ec.income_multiplier(vid)  # milestones carry their own bonus
	check(WS.status(vid, "hall_of_giants") == "ready", "two milestones make 2F ready")
	check(WS.status(vid, "sky_terrace") == "locked", "3F still needs its own milestone")
	var price: BigNumber = WS.price(vid, "hall_of_giants")
	check(not price.lt(BN.from_float(2000.0)), "price never undercuts the wing's floor (%s)" % price.to_notation())
	gs.cash = BN.zero()
	check(not WS.renovate(vid, "hall_of_giants"), "renovation needs the cash")
	check(not WS.is_open(vid, "hall_of_giants"), "a failed renovation opens nothing")

	gs.cash = price.add(BN.from_float(10.0))
	var fired := []
	var cb := func(v: String, w: String) -> void: fired.append([v, w])
	root.get_node("EventBus").wing_renovated.connect(cb)
	check(WS.renovate(vid, "hall_of_giants"), "2F renovates when ready and affordable")
	check(fired == [[vid, "hall_of_giants"]], "renovation announces itself on the EventBus")
	check(gs.cash.lt(BN.from_float(11.0)), "renovation charges the shown price")
	check(not WS.renovate(vid, "hall_of_giants"), "an open wing cannot be bought twice")

	check(absf(ec.income_multiplier(vid) / base_income - 1.5) < 0.001, "2F multiplies income by 1.5")
	check(ec.track_max_level(vid, "speed") == base_cap + 5, "2F adds five upgrade levels")
	check(ec.max_staff(vid, "gallery") == base_staff + 3, "2F adds three gallery slots")
	check(WS.grandeur_tier(vid) == 2 and WS.grandeur_name(vid) == "Restored", "one wing makes the museum Restored")

	# Order is enforced even when a later wing's requirement is met.
	gs.venue_state(vid)["milestones"] = ms
	gs.cash = BN.from_parts(1.0, 60)
	check(not WS.renovate(vid, "gilded_facade"), "wings open in order (facade waits for 3F)")
	check(WS.renovate(vid, "sky_terrace"), "3F renovates next")

	# The museum is not complete until every wing is open.
	for track in PS.core_tracks():
		gs.set_dept_level(vid, str(track[0]), str(track[1]), int(dl.get_venue(vid)["track_level_cap"]))
	var DS: GDScript = load("res://scripts/meta/decor_system.gd")
	gs.gems = 1 << 30
	var decor_ids: Array = dl.decor.keys()
	decor_ids.sort_custom(func(a, b) -> bool: return DS.piece_decor_points(a) > DS.piece_decor_points(b))
	for d in decor_ids:
		if PS.decor_met(vid):
			break
		DS.buy_decor(vid, d)
	check(not PS.gate_met(vid), "graduation waits for the last wing")
	check("Gilded Facade" in PS.block_reason(), "the block reason names the next wing: " + PS.block_reason())
	check(WS.renovate(vid, "gilded_facade"), "the facade renovates last")
	check(PS.gate_met(vid), "every wing open completes the museum")
	check(WS.grandeur_tier(vid) == 4 and WS.grandeur_name(vid) == "Magnificent", "three wings make it Magnificent")

	# Venues without authored wings get one per upper storey plus the facade.
	var auto: Array = WS.wings("chronos_spire")
	check(auto.size() == 4, "Chronos Spire's three upper storeys become three wings plus the facade (%d)" % auto.size())
	check(str(auto[0]["label"]) == "2F" and int(auto[0]["req_milestones"]) == 1, "auto wings unlock floor by floor")
	check(str(auto.back()["id"]) == "gilded_facade", "every museum ends with its facade")
	check(WS.wings("whispering_pines").size() == 3, "authored wings are used as written")

	root.get_node("EventBus").wing_renovated.disconnect(cb)
	print("RESULT: ", "OK" if failures == 0 else "FAILED (%d)" % failures)
	quit(1 if failures > 0 else 0)
