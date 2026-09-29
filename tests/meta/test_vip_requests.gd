extends SceneTree
## test_vip_requests.gd — "VIP tips as quests" (VisitorSystem requests).
##
## Proves: the wish chance and one-at-a-time rule; the target is the lowest
## upgradeable speed/value track, levels_ahead above it; accepting puts the VIP
## bubble on its cooldown; the request reads naturally; nothing is paid before
## the target; reaching it pays tip_mult x the tip plus gems, counts as a VIP
## tip (achievements) and clears it; an expired request lapses quietly; only
## VIPs make wishes.

var failures := 0

func check(ok: bool, message: String) -> void:
	if ok:
		print("  PASS ", message)
	else:
		failures += 1
		printerr("  FAIL ", message)

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	if not OS.has_environment("GRAND_EXHIBIT_TEST_RUN"):
		printerr("REFUSED: requires GRAND_EXHIBIT_TEST_RUN isolation"); quit(2); return
	var VS: GDScript = load("res://scripts/meta/visitor_system.gd")
	var gs: Node = root.get_node("GameState")
	var eb: Node = root.get_node("EventBus")
	var clock: Node = root.get_node("ClockGuard")
	root.get_node("SaveSystem").set_process(false)
	root.get_node("Economy").set_process(false)
	gs.reset_to_new_game()
	gs.ready_flag = true
	var BN: GDScript = load("res://scripts/core/big_number.gd")
	gs.add_cash(BN.from_parts(1.0, 6))  # some income so tips are worth something

	var cfg: Dictionary = VS.request_config()
	check(float(cfg.get("chance", 0)) > 0.0 and int(cfg.get("duration_s", 0)) > 0, "requests are tuned in data")
	check(VS.wants_request(0.0) and not VS.wants_request(0.999), "the wish chance comes from the data")

	var vid: String = gs.current_venue
	gs.set_dept_level(vid, "gallery", "value", 7)
	var target: Dictionary = VS.pick_target(vid)
	var lowest := 999
	for dept in root.get_node("DataLoader").core.get("departments", {}).keys():
		for track in ["speed", "value"]:
			lowest = mini(lowest, int(gs.dept_level(vid, str(dept), track)))
	check(int(target.get("level", -1)) == lowest and str(target.get("track", "")) in ["speed", "value"],
		"the target is the lowest upgradeable track")
	check(int(target["target"]) == lowest + int(cfg.get("levels_ahead", 3)), "levels_ahead above where it stands")

	check(VS.accept_request("local").is_empty(), "only VIPs make wishes")
	var r: Dictionary = VS.accept_request("collector")
	check(not r.is_empty() and str(r["type"]) == "collector" and str(r["venue"]) == vid, "a collector's wish is accepted")
	check(not VS.tip_ready(), "the VIP bubble goes on its cooldown")
	check(not VS.wants_request(0.0), "no second wish while one is in play")
	check(VS.request_text(r).contains("would love to see") and VS.request_text(r).contains(str(r["target"])),
		"the wish reads naturally: %s" % VS.request_text(r))
	check(VS.request_chip_text(r).contains("/%d" % int(r["target"])), "the chip shows progress: %s" % VS.request_chip_text(r))

	check(VS.check_request().is_empty(), "nothing is paid before the target")
	var tipped: Array = []
	eb.vip_tipped.connect(func(t: String, _a: Variant) -> void: tipped.append(t))
	var cash0: BigNumber = gs.cash.copy()
	var gems0: int = gs.gems
	gs.set_dept_level(vid, str(r["dept"]), str(r["track"]), int(r["target"]))
	var expect: Dictionary = VS.request_reward(r)  # after the upgrade: income (so the tip) rose
	var got: Dictionary = VS.check_request()
	check(not got.is_empty() and gs.gems == gems0 + int(expect["gems"]) and int(expect["gems"]) > 0, "meeting it pays gems")
	var mult := float(cfg.get("tip_mult", 5))
	check(gs.cash.sub(cash0).cmp(expect["cash"]) == 0
		and (expect["cash"] as BigNumber).cmp(VS.tip_value("collector").scale(mult)) == 0 and mult > 1.0,
		"and %sx the VIP's tip in cash" % str(mult))
	check(tipped == ["collector"] and VS.requests_met() == 1, "it counts as a VIP tip")
	check(VS.active_request().is_empty(), "and the request is done")

	# An expired request lapses quietly.
	(gs.visitors_state as Dictionary)["tip_ready"] = 0
	var r2: Dictionary = VS.accept_request("royal")
	check(not r2.is_empty(), "a royal patron's wish is accepted")
	((gs.visitors_state as Dictionary)["request"] as Dictionary)["until"] = int(clock.now()) - 1
	check(VS.active_request().is_empty() and not (gs.visitors_state as Dictionary).has("request"), "an expired wish lapses")
	check(VS.check_request().is_empty(), "and pays nothing")

	print("RESULT: ", "OK" if failures == 0 else "FAILED (%d)" % failures)
	quit(1 if failures > 0 else 0)
