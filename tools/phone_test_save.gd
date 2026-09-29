extends SceneTree
## phone_test_save.gd — author the "every level reachable" save for phone QA.
##
## For each venue: complete its milestones, cap every core track, and furnish
## it enough to satisfy the decor gate, so the Prestige screen can graduate
## through all twelve museums by tapping once per venue. Funds are effectively
## unlimited. Writes through the real SaveSystem (envelope + checksum) and
## prints the path so it can be pushed to the phone's app files dir.
##
## Diagnostic only, isolated profile.

var DecorSystem: GDScript
var PrestigeSystem: GDScript

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var xdg := OS.get_environment("XDG_DATA_HOME")
	if OS.get_environment("GRAND_EXHIBIT_TEST_RUN") != "1" or not xdg.begins_with("/tmp/grand-audit-world"):
		printerr("AUDIT_REFUSED: requires GRAND_EXHIBIT_TEST_RUN=1 and XDG_DATA_HOME=/tmp/grand-audit-world")
		quit(2)
		return
	DecorSystem = load("res://scripts/meta/decor_system.gd") as GDScript
	PrestigeSystem = load("res://scripts/meta/prestige_system.gd") as GDScript
	var ss := root.get_node("SaveSystem")
	ss.set_process(false)
	ss.autosave_interval_sec = 1 << 30
	var gs := root.get_node("GameState")
	var dl := root.get_node("DataLoader")
	gs.reset_to_new_game()
	gs.ready_flag = true
	gs.cash = BigNumber.from_parts(9.9, 30)
	gs.gems = 999999
	# Reputation-gated screens (Decor Rep 2, Managers Rep 6, Expedition Rep 7,
	# plus inspection/event days) are part of the device sweep, so the fixture
	# unlocks them rather than making the campaign grind reputation first.
	gs.reputation_xp = BigNumber.from_parts(9.9, 12)
	var order: Array = dl.venue_order()
	for vid_v in order:
		var vid := str(vid_v)
		if vid not in gs.venues_unlocked:
			gs.venues_unlocked.append(vid)
		var need: int = PrestigeSystem.milestones_required(vid)
		var authored: Array = dl.milestones.get(vid, [])
		var done: Array = []
		for i in mini(need, authored.size()):
			done.append(str((authored[i] as Dictionary).get("id", "m%d" % i)))
		gs.venue_state(vid)["milestones"] = done
		var cap: int = int(dl.get_venue(vid).get("track_level_cap", 100))
		for dept in ["ticket", "archive", "promotions", "gallery"]:
			for track in ["staff", "speed", "value"]:
				gs.set_dept_level(vid, dept, track, cap)
		for did_v in dl.decor:
			var did := str(did_v)
			if PrestigeSystem.decor_met(vid):
				break
			if not DecorSystem.buy_decor(vid, did):
				DecorSystem.grant_event_decor(did, vid)
		print("PHONE_SAVE ", vid, " milestones=", done.size(), "/", need,
			" decor_met=", PrestigeSystem.decor_met(vid),
			" operations_met=", PrestigeSystem.operations_met(vid))
	gs.current_venue = str(order[0])
	gs.venue_state(gs.current_venue)
	# The current venue must be graduateable so the campaign can advance.
	print("PHONE_SAVE first_venue=", gs.current_venue,
		" can_graduate=", PrestigeSystem.can_graduate(),
		" block=", PrestigeSystem.block_reason())
	ss.save_now()
	print("PHONE_SAVE path=", ss.save_path())
	quit(0)
