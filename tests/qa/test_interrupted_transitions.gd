extends SceneTree
## test_interrupted_transitions.gd — process death at the worst moment.
##
## Handoff P0.6, plus the manager assignment/replacement/stand-down validation
## from shared requirement 4. A phone kills the app whenever it likes: mid
## purchase, mid museum completion, mid porter delivery. The rule this suite
## enforces is that every one of those resolves to a state the player would
## accept — either the transaction happened completely or it did not happen at
## all, and never "money gone, nothing received" or "received twice".
##
## Process death is simulated the only honest way: write the real save through
## SaveSystem (envelope, checksum, version), wipe live state, and read it back.
## Poking GameState in memory would prove nothing about the envelope.
##
## Run: godot --headless --path <repo> -s tests/qa/test_interrupted_transitions.gd

## load() at runtime, NOT preload(): these helpers name autoloads at class scope
## and preloading them under -s compiles them before autoload names are bound,
## leaving dead objects whose calls silently no-op.
var DecorSystem: GDScript
var PrestigeSystem: GDScript
var ManagerSystem: GDScript

var failures := 0
var GS: Node
var DL: Node
var SS: Node
var EC: Node

func check(cond: bool, msg: String) -> void:
	if cond:
		print("  PASS ", msg)
	else:
		failures += 1
		printerr("  FAIL ", msg)

func _init() -> void:
	call_deferred("run")

const V1 := "whispering_pines"

func run() -> void:
	for pair in [["event_bus", "EventBus"], ["data_loader", "DataLoader"],
			["clock_guard", "ClockGuard"], ["analytics", "Analytics"],
			["ad_service", "AdService"], ["iap_service", "IAPService"],
			["game_state", "GameState"], ["save_system", "SaveSystem"],
			["economy", "Economy"]]:
		if root.has_node(pair[1]):
			continue
		var n: Node = (load("res://autoload/%s.gd" % pair[0]) as GDScript).new()
		n.name = pair[1]
		root.add_child(n)
	DecorSystem = load("res://scripts/meta/decor_system.gd") as GDScript
	PrestigeSystem = load("res://scripts/meta/prestige_system.gd") as GDScript
	ManagerSystem = load("res://scripts/managers/manager_system.gd") as GDScript
	GS = root.get_node("GameState")
	DL = root.get_node("DataLoader")
	SS = root.get_node("SaveSystem")
	EC = root.get_node("Economy")
	# The autosave clock must never fire while a test is doctoring state.
	SS.set_process(false)
	SS.autosave_interval_sec = 1 << 30
	GS.reset_to_new_game()
	GS.ready_flag = true
	_wipe_save()

	_test_kill_before_autosave_loses_the_purchase_cleanly()
	_test_kill_after_autosave_grants_exactly_once()
	_test_kill_during_venue_completion()
	_test_pending_delivery_survives_a_restart()
	_test_truncated_save_recovers()
	_test_manager_assignment_survives_a_restart()
	_test_manager_replacement_and_stand_down()

	print("---")
	print("interrupted transitions: %d failure(s)" % failures)
	quit(0 if failures == 0 else 1)

# --------------------------------------------------------------------- helpers

func _wipe_save() -> void:
	for p in [SS.save_path(), SS.save_path() + ".bak", SS.save_path() + ".corrupt"]:
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(p)

## Simulate process death: everything not written to disk is gone.
func _kill_and_relaunch() -> bool:
	GS.reset_to_new_game()
	GS.ready_flag = true
	return SS.load_game()

func _fund() -> void:
	GS.cash = BigNumber.from_parts(5.0, 9)
	GS.gems = 100000

# ----------------------------------------------------------------------- tests

func _test_kill_before_autosave_loses_the_purchase_cleanly() -> void:
	print("-- killed BEFORE the autosave: the purchase never happened --")
	_wipe_save()
	_fund()
	GS.venue_state(V1)["decor"] = {}
	GS.decor_owned = []
	SS.save_now()                                  # the last good save
	var cash_at_save: float = GS.cash.to_float_approx()

	check(DecorSystem.buy_decor(V1, "oak_bench"), "the player buys a bench")
	check(GS.cash.to_float_approx() < cash_at_save, "cash left the wallet in memory")

	# Power cut before the next autosave.
	check(_kill_and_relaunch(), "the app relaunches from the last save")
	check(not DecorSystem.owned(V1, "oak_bench"), "the bench is not placed")
	check(not GS.owns_decor_design("oak_bench"), "and the design is not owned")
	check(is_equal_approx(GS.cash.to_float_approx(), cash_at_save),
		"and crucially the money is BACK — never charged-without-goods")

func _test_kill_after_autosave_grants_exactly_once() -> void:
	print("-- killed AFTER the autosave: granted once, not twice --")
	_wipe_save()
	_fund()
	GS.venue_state(V1)["decor"] = {}
	GS.decor_owned = []
	check(DecorSystem.buy_decor(V1, "oak_bench"), "the player buys a bench")
	SS.save_now()
	var cash_after: float = GS.cash.to_float_approx()
	var slots_after: int = DecorSystem.slots_used(V1)

	check(_kill_and_relaunch(), "relaunch reads the save")
	check(DecorSystem.owned(V1, "oak_bench"), "the bench is still there")
	check(GS.owns_decor_design("oak_bench"), "the design is still owned")
	check(DecorSystem.slots_used(V1) == slots_after,
		"exactly one slot is used, not two (%d)" % DecorSystem.slots_used(V1))
	check(is_equal_approx(GS.cash.to_float_approx(), cash_after),
		"and the player was not charged a second time on load")

	# Relaunching repeatedly must stay idempotent.
	check(_kill_and_relaunch(), "second relaunch")
	check(DecorSystem.slots_used(V1) == slots_after,
		"still one slot after a second relaunch")

func _test_kill_during_venue_completion() -> void:
	print("-- killed mid museum-completion: the ladder stays one-way --")
	_wipe_save()
	_fund()
	# Earn the gate the normal way rather than forcing the flag.
	var need: int = PrestigeSystem.milestones_required(V1)
	var authored: Array = DL.milestones.get(V1, [])
	var done: Array = []
	for i in mini(need, authored.size()):
		done.append(str((authored[i] as Dictionary).get("id", "m%d" % i)))
	GS.venue_state(V1)["milestones"] = done
	for dept in ["ticket", "archive", "promotions", "gallery"]:
		for track in ["staff", "speed", "value"]:
			GS.set_dept_level(V1, dept, track, int(DL.get_venue(V1).get("track_level_cap", 100)))
	for did in DL.decor:
		if PrestigeSystem.decor_met(V1):break
		DecorSystem.grant_event_decor(did,V1)
	SS.save_now()
	check(PrestigeSystem.gate_met(V1), "decorated completion fixture satisfies gate")

	var before_venue: String = GS.current_venue
	check(PrestigeSystem.graduate(), "the museum completes")
	var after_venue: String = GS.current_venue
	check(after_venue != before_venue, "the player moved to the next museum")
	check(GS.venue_is_closed(before_venue), "the old museum is recorded closed")

	# Power cut immediately after graduating but before any autosave: the player
	# is back in the old museum, which is correct — the completion did not
	# persist, so it did not happen. What must NEVER happen is a half state:
	# moved on AND the old venue still open, or closed AND still current.
	check(_kill_and_relaunch(), "relaunch from the pre-completion save")
	check(GS.current_venue == before_venue, "they are back in the museum they were completing")
	check(not GS.venue_is_closed(before_venue), "and it is not marked closed")

	# Now do it properly: complete, save, die.
	check(PrestigeSystem.graduate(), "complete it again")
	SS.save_now()
	check(_kill_and_relaunch(), "relaunch after the completion was saved")
	check(GS.current_venue == after_venue, "the player is in the new museum")
	check(GS.venue_is_closed(before_venue), "the old one is closed for good")
	check(not GS.venues_unlocked.is_empty(), "unlocks persisted")

func _test_pending_delivery_survives_a_restart() -> void:
	print("-- saved mid porter delivery: banked cash is not lost --")
	_wipe_save()
	GS.reset_to_new_game()
	GS.ready_flag = true
	_fund()
	# Money sitting on a cashier that no porter has collected yet.
	var items: Array = GS.dept_items(V1, "ticket")
	check(items.size() > 0, "the ticket hall has at least one station")
	items[0]["pending"] = BigNumber.from_parts(4.25, 6).to_save()
	# collect_item clamps to the VENUE ledger so a tap can never mint cash the
	# simulation has not produced. Mirror the station pile into it, exactly as a
	# real tick would have done when the visitor paid.
	GS.pending_cash[V1] = BigNumber.from_parts(4.25, 6)
	var pending_before: float = EC.item_pending(V1, "ticket", 0).to_float_approx()
	check(pending_before > 0.0, "a station is holding %.0f uncollected" % pending_before)

	SS.save_now()
	check(_kill_and_relaunch(), "relaunch")
	var pending_after: float = EC.item_pending(V1, "ticket", 0).to_float_approx()
	check(is_equal_approx(pending_after, pending_before),
		"the uncollected pile came back intact (%.0f -> %.0f)" % [pending_before, pending_after])
	check(EC.collect_item(V1, "ticket", 0).to_float_approx() > 0.0,
		"and it can still be collected after the restart")

func _test_truncated_save_recovers() -> void:
	print("-- a half-written save must not brick the game --")
	_wipe_save()
	_fund()
	SS.save_now()
	var whole: String = FileAccess.get_file_as_string(SS.save_path())
	check(whole.length() > 40, "there is a save to truncate")

	# A process killed mid-write leaves a prefix of the JSON, not valid JSON.
	var f := FileAccess.open(SS.save_path(), FileAccess.WRITE)
	f.store_string(whole.substr(0, int(whole.length() * 0.6)))
	f.close()

	GS.reset_to_new_game()
	GS.ready_flag = true
	var loaded: bool = SS.load_game()
	check(not loaded, "the truncated save is refused rather than half-applied")
	check(FileAccess.file_exists(SS.save_path() + ".corrupt"),
		"the damaged file is preserved as .corrupt for support")
	check(not SS.has_save(), "and the slot is clear, so the game starts fresh instead of crashing")

	# The game must be fully playable from here.
	GS.reset_to_new_game()
	GS.ready_flag = true
	_fund()
	check(DecorSystem.buy_decor(V1, "oak_bench"), "a fresh game is playable after the corruption")
	SS.save_now()
	check(_kill_and_relaunch(), "and can save and reload normally again")

func _test_manager_assignment_survives_a_restart() -> void:
	print("-- manager assignment persists across process death --")
	_wipe_save()
	GS.reset_to_new_game()
	GS.ready_flag = true
	_fund()

	# A manager may only take a post in their OWN specialty, so the department is
	# read off the manager rather than guessed. Guessing "ticket" was the test's
	# bug, not the system's — the refusal was correct.
	var mid: String = ""
	var dept: String = ""
	for id in DL.managers.keys():
		var spec: String = str(ManagerSystem.manager_def(str(id)).get("specialty", ""))
		if spec != "":
			mid = str(id)
			dept = spec
			break
	check(mid != "", "there is a manager with a specialty (%s -> %s)" % [mid, dept])
	ManagerSystem.add_cards(mid, 50)
	check(ManagerSystem.owned(mid), "the manager is owned")

	check(ManagerSystem.assign(mid, dept), "the manager is assigned to %s" % dept)
	check(str(ManagerSystem.assigned_to(mid)) == dept, "assignment is recorded")
	var mult_before: float = EC.manager_multiplier_for(dept)
	check(mult_before > 1.0, "and it actually changes the department's output (x%.2f)" % mult_before)

	SS.save_now()
	check(_kill_and_relaunch(), "relaunch")
	check(str(ManagerSystem.assigned_to(mid)) == dept, "still assigned after the restart")
	check(is_equal_approx(EC.manager_multiplier_for(dept), mult_before),
		"and the department still gets the bonus")

func _test_manager_replacement_and_stand_down() -> void:
	print("-- replacement and stand-down through the normal API --")
	var ids: Array = []
	for id in DL.managers.keys():
		ids.append(str(id))
	ids.sort()
	check(ids.size() >= 2, "there are at least two managers (%d)" % ids.size())
	if ids.size() < 2:
		return

	for id in ids:
		ManagerSystem.add_cards(str(id), 50)
	# Two managers who share a specialty, since only those can contest one post.
	var by_spec: Dictionary = {}
	var dept := ""
	var a := ""
	var b := ""
	for id in ids:
		if not ManagerSystem.owned(str(id)):
			continue
		var spec: String = str(ManagerSystem.manager_def(str(id)).get("specialty", ""))
		if spec == "":
			continue
		if not by_spec.has(spec):
			by_spec[spec] = []
		(by_spec[spec] as Array).append(str(id))
		if (by_spec[spec] as Array).size() == 2:
			dept = spec
			a = str((by_spec[spec] as Array)[0])
			b = str((by_spec[spec] as Array)[1])
			break
	check(dept != "", "two owned managers share a specialty (%s: %s, %s)" % [dept, a, b])
	if dept == "":
		return

	ManagerSystem.unassign(a)
	ManagerSystem.unassign(b)
	var slots: int = ManagerSystem.assignment_slots(dept)
	check(slots >= 1, "the department has %d assignment slot(s)" % slots)

	check(ManagerSystem.assign(a, dept), "first manager takes a post")
	check(ManagerSystem.assigned_ids(dept).has(a), "and is listed on the department sheet")

	# Stand-down frees the post without destroying the manager.
	check(ManagerSystem.unassign(a), "stand-down works")
	check(str(ManagerSystem.assigned_to(a)) == "", "the manager is off duty")
	check(ManagerSystem.owned(a), "but is still owned — standing down is not dismissal")
	check(not ManagerSystem.assigned_ids(dept).has(a), "and off the department sheet")

	# Replacement: b takes the post a vacated.
	check(ManagerSystem.assign(b, dept), "a replacement takes the post")
	check(ManagerSystem.assigned_ids(dept).has(b), "the replacement is on the sheet")
	check(not ManagerSystem.assigned_ids(dept).has(a), "the predecessor is not")
	check(ManagerSystem.assigned_ids(dept).size() <= ManagerSystem.assignment_slots(dept),
		"the department never holds more managers than it has posts (%d/%d)"
			% [ManagerSystem.assigned_ids(dept).size(), ManagerSystem.assignment_slots(dept)])

	SS.save_now()
	check(_kill_and_relaunch(), "relaunch")
	check(ManagerSystem.assigned_ids(dept).has(b), "the replacement survived the restart")
	check(str(ManagerSystem.assigned_to(a)) == "", "and the stood-down manager is still off duty")
