extends SceneTree
## Daily Gifts: one gift per local day, never reset by a missed day, the week
## repeats, every gift type pays, seven claims unlock 'Regular', the state is
## saved, and the screen's Claim button works.

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
	if not OS.has_environment("GRAND_EXHIBIT_TEST_RUN"):
		printerr("REFUSED: requires GRAND_EXHIBIT_TEST_RUN isolation"); quit(2); return
	var gs: Node = root.get_node("GameState")
	var ss: Node = root.get_node("SaveSystem")
	ss.set_process(false)
	root.get_node("Economy").set_process(false)
	var path: String = ss.save_path()
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)
	gs.reset_to_new_game()
	gs.ready_flag = true
	var DG: GDScript = load("res://scripts/meta/daily_gifts.gd")
	var DigSystem: GDScript = load("res://scripts/digsite/dig_system.gd")
	var ps: Node = root.get_node("PlatformServices")
	# Some income, so cash gifts are worth something.
	gs.add_cash(BigNumber.from_parts(1.0, 6))
	root.get_node("Economy").purchase_item_upgrade(gs.current_venue, "ticket", 0)

	var t0 := 1790000000  # a fixed day
	check(DG.days().size() == 7, "a week of seven gifts")
	check(DG.available(t0) and DG.day_index() == 0, "a new player has Day 1 waiting")
	var gems: int = gs.gems
	var got: Dictionary = DG.claim(t0)
	check(int(got.get("day", 0)) == 1 and gs.gems == gems + 5, "Day 1 pays 5 gems")
	check(not DG.available(t0) and DG.claim(t0 + 60).is_empty(), "one gift per day")
	var cash: BigNumber = gs.cash
	got = DG.claim(t0 + 86400)
	check(int(got.get("day", 0)) == 2 and gs.cash.gt(cash), "Day 2 pays minutes of income")
	# Skip four days: progress waits rather than resetting.
	DigSystem.call("settle_energy")
	var energy := float(gs.dig_state.get("energy", 0.0))
	got = DG.claim(t0 + 6 * 86400)
	check(int(got.get("day", 0)) == 3, "a missed day doesn't reset the week")
	check(float(gs.dig_state.get("energy", 0.0)) >= energy + 14.0, "Day 3 pays dig energy")
	DG.claim(t0 + 7 * 86400)
	var until_before := int(gs.boosts.get("income_x2_until", 0))
	got = DG.claim(t0 + 8 * 86400)
	check(int(got.get("day", 0)) == 5 and int(gs.boosts.get("income_x2_until", 0)) > until_before, "Day 5 adds x2 income time")
	DG.claim(t0 + 9 * 86400)
	got = DG.claim(t0 + 10 * 86400)
	var cards := 0
	for v in (got.get("cards", {}) as Dictionary).values():
		cards += int(v)
	check(int(got.get("day", 0)) == 7 and cards > 0, "Day 7 pays gems and a Specialist Case (%d cards)" % cards)
	check(ps.is_unlocked("WEEK_OF_GIFTS"), "seven gifts unlock 'Regular'")
	got = DG.claim(t0 + 11 * 86400)
	check(int(got.get("day", 0)) == 1, "after Day 7 the week starts again")
	check(DG.total() == 8, "every claim is counted")

	var saved: Dictionary = gs.to_save_dict()
	gs.reset_to_new_game()
	gs.from_save_dict(JSON.parse_string(JSON.stringify(saved)))
	check(DG.total() == 8 and DG.day_index() == 1, "the calendar survives save and load")

	# The screen: today's gift is claimable with one tap.
	gs.event_state["daily_gifts"]["last"] = ""
	var screen: Control = (load("res://scenes/meta/daily_gifts_screen.tscn") as PackedScene).instantiate()
	root.add_child(screen)
	await process_frame
	var btn: Button = screen.find_child("ClaimGift", true, false)
	check(btn != null and btn.text.begins_with("Claim Day 2"), "the screen offers today's gift (%s)" % (btn.text if btn else "none"))
	btn.pressed.emit()
	await process_frame
	check(not DG.available() and DG.total() == 9, "tapping Claim collects it")
	check(btn.text == "Come back tomorrow", "then the button says come back tomorrow")
	screen.queue_free()
	await create_timer(0.8).timeout
	gs.reset_to_new_game()
	print("RESULT: ", "OK" if failures == 0 else "FAILED (%d)" % failures)
	quit(1 if failures > 0 else 0)
