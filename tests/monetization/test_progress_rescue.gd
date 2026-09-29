extends SceneTree
## test_progress_rescue.gd — the contextual rewarded-ad rescue.
##
## The thing this must never become is a toll gate. The campaign has to stay
## completable with zero ads, so most of these assertions are about the offer
## NOT appearing: too early, too often, after a purchase, or when the player is
## merely poor rather than actually stuck.
##
## Run: godot --headless --path <repo> -s tests/monetization/test_progress_rescue.gd

## load() at runtime, NOT preload(). Under -s the main script compiles before
## autoload names are bound, and these three name GameState/DataLoader/Analytics
## at class scope. A preload compiles them too early: every call then silently
## no-ops against a dead GDScript and the suite reports a false green.
var Rescue: GDScript
var Entitlements: GDScript
var MonoClock: GDScript

var failures := 0
var GS: Node
var DL: Node
var ADS: Node
var ECON: Node

func check(cond: bool, msg: String) -> void:
	if cond:
		print("  PASS ", msg)
	else:
		failures += 1
		printerr("  FAIL ", msg)

func _init() -> void:
	call_deferred("run")

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
	var SS: Node = root.get_node("SaveSystem")
	SS.set_process(false)
	SS.autosave_interval_sec = 1 << 30
	Rescue = load("res://scripts/monetization/progress_rescue.gd") as GDScript
	Entitlements = load("res://scripts/monetization/entitlements.gd") as GDScript
	MonoClock = load("res://scripts/monetization/mono_clock.gd") as GDScript
	GS = root.get_node("GameState")
	DL = root.get_node("DataLoader")
	ADS = root.get_node("AdService")
	ECON = root.get_node("Economy")
	GS.reset_to_new_game()
	GS.ready_flag = true

	_test_contract_is_configured()
	_test_not_offered_in_the_first_minutes()
	_test_not_offered_when_not_stuck()
	_test_not_offered_without_income()
	_test_offered_when_genuinely_stuck()
	_test_preview_states_the_exact_reward()
	_test_cooldown_and_daily_cap()
	_test_dismiss_snoozes_longer_than_cooldown()
	_test_grant_requires_a_verified_token()

	print("---")
	print("progress rescue: %d failure(s)" % failures)
	quit(0 if failures == 0 else 1)

## Put the player far enough into the session that the age gate is satisfied.
func _age_session(seconds: int) -> void:
	GS.first_launch_unix = MonoClock.now() - seconds

## Drive the venue into a genuinely stuck state: upgrade costs grow
## geometrically with item level while income grows far more slowly, so raising
## levels is what actually pushes the cheapest purchase out of reach. Loops to a
## measured threshold rather than a magic level so a balance change cannot
## quietly turn this fixture back into "not stuck" and hollow out the test.
func _make_stuck() -> bool:
	var want: float = float(Rescue.cfg().get("stuck_eta_seconds", 600))
	var level: int = 1
	while level < 400:
		level += 25
		for dept_id in DL.core.get("departments", {}).keys():
			var items: Array = GS.dept_items(GS.current_venue, str(dept_id))
			for i in items.size():
				GS.set_item_level(GS.current_venue, str(dept_id), i, level)
		GS.cash = BigNumber.zero()
		if Rescue.cheapest_upgrade_eta(GS.current_venue) >= want:
			return true
	return false

func _reset_state() -> void:
	GS.rv_state.erase("progress_rescue")
	GS.rv_state.erase("entitlements")

func _test_contract_is_configured() -> void:
	print("-- the contract lives in data --")
	var c: Dictionary = Rescue.cfg()
	check(not c.is_empty(), "progress_rescue block exists in balance_core.json")
	for key in ["min_session_seconds", "stuck_eta_seconds", "reward_seconds_of_income",
			"cooldown_seconds", "dismiss_snooze_seconds", "max_offers_per_day"]:
		check(c.has(key), "contract defines %s" % key)
	check(int(c.get("dismiss_snooze_seconds", 0)) > int(c.get("cooldown_seconds", 0)),
		"an explicit 'no' snoozes for longer than the passive cooldown")

func _test_not_offered_in_the_first_minutes() -> void:
	print("-- never in the opening minutes --")
	_reset_state()
	_age_session(30)
	GS.cash = BigNumber.zero()
	var e: Dictionary = Rescue.eligible()
	check(not bool(e["ok"]), "not offered 30 seconds in")
	check(str(e["reason"]) == "session_too_short", "reason: %s" % str(e["reason"]))

func _test_not_offered_when_not_stuck() -> void:
	print("-- being poor is not being stuck --")
	_reset_state()
	_age_session(3600)
	# Rich enough to buy the cheapest upgrade outright: ETA 0.
	GS.cash = BigNumber.from_parts(9.0, 9)
	var e: Dictionary = Rescue.eligible()
	check(not bool(e["ok"]), "not offered when something is affordable right now")
	check(str(e["reason"]) == "not_stuck", "reason: %s" % str(e["reason"]))
	check(float(e["eta"]) < 1.0, "ETA is effectively zero (%.1fs)" % float(e["eta"]))

func _test_not_offered_without_income() -> void:
	print("-- zero income is a different problem --")
	_reset_state()
	_age_session(3600)
	GS.cash = BigNumber.zero()
	# Strip the venue down so nothing earns.
	for dept_id in DL.core.get("departments", {}).keys():
		GS.set_dept_level(GS.current_venue, str(dept_id), "staff", 0)
	var e: Dictionary = Rescue.eligible()
	check(not bool(e["ok"]), "not offered to a player earning nothing")
	check(str(e["reason"]) in ["no_income", "not_stuck"],
		"reason: %s" % str(e["reason"]))
	GS.reset_to_new_game()
	GS.ready_flag = true

func _test_offered_when_genuinely_stuck() -> void:
	print("-- offered when the cheapest upgrade is genuinely far away --")
	_reset_state()
	_age_session(3600)
	check(_make_stuck(), "the fixture could be driven into a stuck state")
	var eta: float = Rescue.cheapest_upgrade_eta(GS.current_venue)
	var e: Dictionary = Rescue.eligible()
	check(eta >= float(Rescue.cfg().get("stuck_eta_seconds", 600)),
		"the fixture is actually stuck (ETA %.0fs)" % eta)
	check(bool(e["ok"]), "the offer is available (reason: %s)" % str(e["reason"]))
	check((e["reward"] as BigNumber).to_float_approx() > 0.0, "and carries a positive reward")

func _test_preview_states_the_exact_reward() -> void:
	print("-- the player is told exactly what they get, before the ad --")
	var p: Dictionary = Rescue.preview()
	check(bool(p["available"]), "preview reports availability")
	var minutes: int = int(p["minutes"])
	check(minutes == 15, "reward is stated in minutes of income (%d)" % minutes)
	var expected: BigNumber = ECON.current_cash_per_second().scale(float(minutes) * 60.0)
	check(is_equal_approx((p["amount"] as BigNumber).to_float_approx(),
			expected.to_float_approx()),
		"the previewed amount equals %d minutes of current income" % minutes)
	check(str(p["amount_text"]) != "", "and is renderable (%s)" % str(p["amount_text"]))

func _test_cooldown_and_daily_cap() -> void:
	print("-- rare by construction --")
	_reset_state()
	_age_session(3600)
	_make_stuck()
	check(bool(Rescue.eligible()["ok"]), "eligible before the first offer")

	Rescue.mark_offered()
	var e: Dictionary = Rescue.eligible()
	check(not bool(e["ok"]) and str(e["reason"]) == "cooldown",
		"a shown offer starts a cooldown (%s)" % str(e["reason"]))

	# Burn the daily allowance, stepping past the cooldown each time.
	var cap: int = int(Rescue.cfg().get("max_offers_per_day", 3))
	var st: Dictionary = GS.rv_state["progress_rescue"]
	for _i in range(cap - 1):
		st["last_offer"] = 0
		Rescue.mark_offered()
	st["last_offer"] = 0
	var capped: Dictionary = Rescue.eligible()
	check(not bool(capped["ok"]) and str(capped["reason"]) == "daily_cap",
		"the daily cap of %d holds even with the cooldown elapsed (%s)"
			% [cap, str(capped["reason"])])

func _test_dismiss_snoozes_longer_than_cooldown() -> void:
	print("-- 'not now' means longer than 'not yet' --")
	_reset_state()
	_age_session(3600)
	_make_stuck()
	check(bool(Rescue.eligible()["ok"]), "eligible before dismissal")
	Rescue.dismiss()
	var e: Dictionary = Rescue.eligible()
	check(not bool(e["ok"]) and str(e["reason"]) == "snoozed",
		"dismissing suppresses the offer (%s)" % str(e["reason"]))
	var st: Dictionary = GS.rv_state["progress_rescue"]
	check(int(st["snoozed_until"]) - MonoClock.now()
			> int(Rescue.cfg().get("cooldown_seconds", 900)),
		"and for longer than a plain cooldown")

func _test_grant_requires_a_verified_token() -> void:
	print("-- no token, no money --")
	_reset_state()
	_age_session(3600)
	GS.cash = BigNumber.zero()
	var before: float = GS.cash.to_float_approx()

	check(not Rescue.claim({}), "a claim with no token is refused")
	check(not Rescue.claim({"reward_token": "forged-token"}),
		"a forged token is refused")
	check(GS.cash.to_float_approx() == before, "and nothing was paid out")

	# A genuine token, minted the way AdService mints one at show time.
	var token: String = ADS._mint_token(Rescue.placement())
	check(Rescue.claim({"reward_token": token}), "a real token pays out")
	check(GS.cash.to_float_approx() > before, "cash actually increased")

	var after: float = GS.cash.to_float_approx()
	check(not Rescue.claim({"reward_token": token}),
		"the same token cannot be redeemed twice")
	check(GS.cash.to_float_approx() == after, "and the replay paid nothing")
