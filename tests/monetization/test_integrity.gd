extends SceneTree
## test_integrity.gd — the adversarial half of the monetization suite (SPEC §12).
## Every case here was a live defect: each one granted real currency, or would have
## shipped a release build that gave everything away.
##
## Run: godot --headless --path <repo> -s tests/monetization/test_integrity.gd
## Exit 0 = all pass, 1 = any failure.
## Bootstrap mirrors test_monetization.gd: autoload singletons are not instantiated
## for a -s main script, so they are created as named root children.

var failures: int = 0

var EventBus: Node
var DataLoader: Node
var ClockGuard: Node
var Analytics: Node
var AdService: Node
var IAPService: Node
var GameState: Node
var SaveSystem: Node
var Economy: Node

var RV: GDScript
var IAPCat: GDScript
var Offers: GDScript
var MonoClock: GDScript
var Entitlements: GDScript
var Interstitials: GDScript
var Pricing: GDScript
var Consent: GDScript

var _grants: Array = []
var _toasts: Array = []
var _completed: Array = []

func check(cond: bool, msg: String) -> void:
	if cond:
		print("  PASS ", msg)
	else:
		failures += 1
		printerr("  FAIL ", msg)

func _init() -> void:
	call_deferred("run")

func run() -> void:
	_boot()
	GameState.reset_to_new_game()
	GameState.ready_flag = true
	root.get_node("Economy").set_process(false)
	root.get_node("SaveSystem").set_process(false)
	EventBus.rv_reward_granted.connect(func(p: String, _c: Dictionary) -> void: _grants.append(p))
	EventBus.toast_requested.connect(func(t: String) -> void: _toasts.append(t))
	EventBus.iap_completed.connect(func(p: String) -> void: _completed.append(p))

	_test_release_defaults()
	_test_ad_service_states()
	await _test_same_frame_rewarded_taps()
	await _test_unverified_reward_rejected()
	await _test_rewarded_daily_cap()
	_test_cooldown()
	await _test_rapid_tap_purchase()
	await _test_duplicate_receipt()
	_test_clock_forward_jump()
	_test_clock_rollback()
	_test_daily_reset_under_attack()
	_test_entitlements_and_interstitials()
	_test_pricing_is_honest()
	_test_consent_gate()

	print("---")
	if failures == 0:
		print("ALL MONETIZATION INTEGRITY TESTS PASSED")
	else:
		printerr("MONETIZATION INTEGRITY TESTS FAILED: %d" % failures)
	quit(0 if failures == 0 else 1)

func _boot() -> void:
	for pair in [["event_bus","EventBus"],["data_loader","DataLoader"],["clock_guard","ClockGuard"],
			["analytics","Analytics"],["ad_service","AdService"],["iap_service","IAPService"],
			["game_state","GameState"],["save_system","SaveSystem"],["economy","Economy"]]:
		if root.has_node(pair[1]):
			continue
		var n: Node = load("res://autoload/%s.gd" % pair[0]).new()
		n.name = pair[1]
		root.add_child(n)
	EventBus = root.get_node("EventBus")
	DataLoader = root.get_node("DataLoader")
	ClockGuard = root.get_node("ClockGuard")
	Analytics = root.get_node("Analytics")
	AdService = root.get_node("AdService")
	IAPService = root.get_node("IAPService")
	GameState = root.get_node("GameState")
	SaveSystem = root.get_node("SaveSystem")
	Economy = root.get_node("Economy")
	RV = load("res://scripts/monetization/rv_placements.gd")
	IAPCat = load("res://scripts/monetization/iap_catalog.gd")
	Offers = load("res://scripts/monetization/offer_system.gd")
	MonoClock = load("res://scripts/monetization/mono_clock.gd")
	Entitlements = load("res://scripts/monetization/entitlements.gd")
	Interstitials = load("res://scripts/monetization/interstitials.gd")
	Pricing = load("res://scripts/monetization/store_pricing.gd")
	Consent = load("res://scripts/monetization/consent.gd")

# ------------------------------------------------------- release build safety

## The single worst defect this track had: both debug flags were plain `var … = true`
## with no build wiring, so an exported APK showed no ads, granted every reward, and
## completed every purchase without charging.
func _test_release_defaults() -> void:
	check(AdService.has_method("_default_debug_ads"), "ad_service exposes a build-derived default")
	check(IAPService.has_method("_default_debug_iap"), "iap_service exposes a build-derived default")
	var ad_src: String = FileAccess.get_file_as_string("res://autoload/ad_service.gd")
	var iap_src: String = FileAccess.get_file_as_string("res://autoload/iap_service.gd")
	check(ad_src.contains("OS.is_debug_build()") and ad_src.contains("OS.has_feature(\"release\")"),
		"debug_ads default reads the build, not a literal")
	check(iap_src.contains("OS.is_debug_build()") and iap_src.contains("OS.has_feature(\"release\")"),
		"debug_iap default reads the build, not a literal")
	check(not ad_src.contains("var debug_ads: bool = true"), "debug_ads is not hardcoded true")
	check(not iap_src.contains("var debug_iap: bool = true"), "debug_iap is not hardcoded true")
	# The suite itself runs in a debug build, so the simulator must be on here.
	check(OS.is_debug_build() == AdService.debug_ads, "debug_ads matches this build's debug flag")
	check(OS.is_debug_build() == IAPService.debug_iap, "debug_iap matches this build's debug flag")

func _test_ad_service_states() -> void:
	check(not AdService.is_ready(""), "is_ready('') is false, not a blanket true")
	check(not AdService.is_ready("nonexistent_placement_xyz") or
		AdService.state_of("nonexistent_placement_xyz") == AdService.READY,
		"is_ready is backed by real per-placement state")
	check(AdService.has_method("show_interstitial"), "interstitial format exists")
	check(AdService.has_method("consume_reward_token"), "reward tokens can be redeemed")
	check(not AdService.consume_reward_token("forged-token", "instant_cash"),
		"a forged reward token is rejected")

# ---------------------------------------------------------- rewarded integrity

## Three taps in one frame used to show three ads and pay three rewards. A mediation
## SDK can only display one ad at a time, so that was N rewards for one impression.
func _test_same_frame_rewarded_taps() -> void:
	_reset_rv()
	_grants.clear()
	var cash0: BigNumber = GameState.cash.copy()
	var one: BigNumber = RV.instant_cash_value()
	RV.instant_cash()
	RV.instant_cash()
	RV.instant_cash()
	await create_timer(0.8).timeout
	check(_grants.count("instant_cash") == 1,
		"3 same-frame taps grant exactly 1 instant_cash (granted %d)" % _grants.count("instant_cash"))
	check(GameState.cash.sub(cash0).cmp(one) == 0,
		"3 same-frame taps pay exactly one ad's worth (%s)" % GameState.cash.sub(cash0).to_notation())
	check(int(RV._state("instant_cash").get("count", 0)) == 1, "only one view counted")

	_grants.clear()
	var until0: int = int(GameState.boosts.get("income_x2_until", 0))
	RV.income_x2()
	RV.income_x2()
	await create_timer(0.8).timeout
	check(_grants.count("income_x2") == 1, "2 same-frame boost taps grant exactly 1")
	var gained: int = int(GameState.boosts.get("income_x2_until", 0)) - maxi(until0, MonoClock.now())
	check(gained <= RV.boost_hours_per_view() * 3600 + 5,
		"boost gained at most one view's worth (%ds)" % gained)

## The reward is authorised by a one-shot token minted when the ad actually
## completes — not by the ad_result signal, which anything can emit.
func _test_unverified_reward_rejected() -> void:
	_reset_rv()
	_grants.clear()
	var cash0: BigNumber = GameState.cash.copy()
	AdService.ad_result.emit("instant_cash", true, {})
	AdService.ad_result.emit("instant_cash", true, {"reward_token": "made-up"})
	await create_timer(0.1).timeout
	check(_grants.is_empty(), "forged success signals grant nothing")
	check(GameState.cash.eq(cash0), "forged success signals pay no cash")
	check(int(RV._state("instant_cash").get("count", 0)) == 0, "forged signals consume no daily view")

## instant_cash and income_x2 had no cap and no persisted state at all: 20 ads in a
## row paid 20 times and rv_state["instant_cash"] came back absent.
func _test_rewarded_daily_cap() -> void:
	_reset_rv()
	var cap: int = RV.daily_cap("instant_cash")
	check(cap > 0, "instant_cash has a daily cap (%d)" % cap)
	for i in range(cap):
		RV.grant_instant_cash()
	check(int(RV._state("instant_cash").get("count", 0)) == cap, "cap views all counted")
	_grants.clear()
	var cash0: BigNumber = GameState.cash.copy()
	check(not RV.grant_instant_cash(), "the view past the cap is refused")
	check(GameState.cash.eq(cash0), "the view past the cap pays nothing")
	# And the cap holds through the real ad path, not just the direct grant.
	RV.instant_cash()
	await create_timer(0.6).timeout
	check(_grants.is_empty(), "capped placement grants nothing through the ad path")
	check(GameState.rv_state.has("instant_cash"), "instant_cash cap state is persisted in rv_state")
	check(GameState.rv_state.has("income_x2") or RV.daily_cap("income_x2") > 0,
		"income_x2 has cap state too")

func _test_cooldown() -> void:
	_reset_rv()
	check(RV.cooldown_seconds("instant_cash") > 0, "instant_cash declares a cooldown")
	RV.grant_instant_cash()
	check(RV.cooldown_left("instant_cash") > 0, "ready_at is written AND read back")
	check(RV.blocked_reason("instant_cash") == "cooldown", "entry is gated by the cooldown")
	check("unavailable" in RV.blocked_message("instant_cash"),
		"the cooldown block explains itself (got '%s')" % RV.blocked_message("instant_cash"))
	# Expiring the stamp releases the gate — the cooldown is a clock, not a latch.
	RV._state("instant_cash")["ready_at"] = MonoClock.now() - 1
	check(RV.blocked_reason("instant_cash") == "", "cooldown clears when it expires")

# --------------------------------------------------------------- IAP integrity

## Four taps on a limit-1 product used to grant four times: the limit was read at
## purchase() but only incremented after the async round trip.
func _test_rapid_tap_purchase() -> void:
	_reset_iap()
	_completed.clear()
	var gems0: int = GameState.gems
	var accepted: int = 0
	for i in range(4):
		if IAPCat.purchase("starter_bundle"):
			accepted += 1
	check(accepted == 1, "4 rapid taps on a limit-1 product accept exactly 1 (accepted %d)" % accepted)
	await create_timer(0.8).timeout
	check(_completed.count("starter_bundle") == 1,
		"exactly one iap_completed (got %d)" % _completed.count("starter_bundle"))
	var granted: int = GameState.gems - gems0
	var want: int = int(DataLoader.get_iap("starter_bundle").get("grants", {}).get("gems", 0))
	check(granted >= want and granted < want * 2,
		"gems granted once, not four times (got %d, one grant is %d)" % [granted, want])
	check(IAPCat.purchases_left_today("starter_bundle") == 0, "the daily slot is spent")

	# An unlimited product still refuses a second tap while the first is in flight.
	_completed.clear()
	check(IAPCat.purchase("gems_pouch"), "first tap on an unlimited product is accepted")
	check(not IAPCat.purchase("gems_pouch"), "second tap inside the round trip is refused")
	await create_timer(0.8).timeout
	check(_completed.count("gems_pouch") == 1, "unlimited product completes exactly once")

## Play Billing re-delivers unacknowledged purchases; the same token must not pay twice.
func _test_duplicate_receipt() -> void:
	_reset_iap()
	_completed.clear()
	var gems0: int = GameState.gems
	var receipt := {"purchase_token": "tok-dup-1", "order_id": "ORDER-1"}
	IAPService.iap_result.emit("gems_pouch", true, receipt)
	await create_timer(0.05).timeout
	var after_first: int = GameState.gems
	IAPService.iap_result.emit("gems_pouch", true, receipt)
	await create_timer(0.05).timeout
	check(after_first > gems0, "first delivery of a receipt grants")
	check(GameState.gems == after_first, "re-delivery of the same receipt grants nothing")
	check(_completed.count("gems_pouch") == 1, "re-delivery emits no second iap_completed")

# ------------------------------------------------------------- clock integrity

## Every daily cap keys off a calendar day. Winding the device clock forward used to
## roll every one of them over at once, and winding it back restored the state to be
## harvested again.
func _test_clock_forward_jump() -> void:
	_reset_rv()
	MonoClock.reset_session_anchor()
	var before: int = MonoClock.now()
	var day_before: String = MonoClock.today()
	RV.grant_free_gems()
	var count_before: int = int(RV._state("free_gems").get("count", 0))
	# Simulate the settings app moving the wall clock 30 days ahead mid-session.
	var real_now: int = ClockGuard.now()
	ClockGuard.set_script(ClockGuard.get_script())  # no-op; keep the autoload intact
	var jumped: int = _now_with_offset(30 * 86400)
	check(jumped - real_now >= 30 * 86400 - 5, "the harness really did move the clock")
	check(absi(MonoClock.now() - before) < 120,
		"a forward wall-clock jump does not move the guarded clock (moved %ds)"
		% (MonoClock.now() - before))
	check(MonoClock.today() == day_before, "the guarded calendar day does not roll over")
	check(int(RV._state("free_gems").get("count", 0)) == count_before,
		"the free-gems cap survives the jump")
	_clear_offset()

func _test_clock_rollback() -> void:
	MonoClock.reset_session_anchor()
	var high: int = MonoClock.now()
	_now_with_offset(-7 * 86400)
	var after: int = MonoClock.now()
	check(after >= high, "the guarded clock never runs backwards (%d >= %d)" % [after, high])
	_clear_offset()
	check(MonoClock.anomaly_count() > 0, "clock tampering is counted (%d)" % MonoClock.anomaly_count())
	check(GameState.rv_state.has(MonoClock.STATE_KEY), "the high-water mark rides in the save")

## The whole point: a cap that resets on the system date is not a cap.
func _test_daily_reset_under_attack() -> void:
	_reset_rv()
	for i in range(RV.daily_cap("free_gems")):
		RV.grant_free_gems()
	check(RV.remaining_free_gems() == 0, "free gems exhausted for the day")
	_reset_iap()
	IAPCat._reserve_slot("starter_bundle")  # spend the limit-1 slot for today
	check(IAPCat.purchases_left_today("starter_bundle") == 0, "the IAP daily limit is spent")
	_now_with_offset(2 * 86400)
	check(RV.remaining_free_gems() == 0, "a two-day forward jump does not refill the cap")
	check(IAPCat.purchases_left_today("starter_bundle") == 0,
		"the IAP daily limit does not refill either")
	_clear_offset()

# ------------------------------------------------------ entitlements / policy

func _test_entitlements_and_interstitials() -> void:
	GameState.rv_state.erase("entitlements")
	GameState.rv_state.erase("interstitial")
	check(not Entitlements.no_ads(), "a fresh player has no ad-free entitlement")
	check(not DataLoader.get_iap("no_ads").is_empty(), "an ad-free product exists in the catalog")
	Interstitials.note_session_start()
	check(Interstitials.blocked_reason() == "session_too_young",
		"no interstitial in the first seconds of a session (got '%s')" % Interstitials.blocked_reason())
	check(not Interstitials.maybe_show("test"), "a suppressed interstitial is not shown")
	Entitlements.record_purchase("no_ads")
	check(Entitlements.no_ads(), "buying the ad-free product grants the entitlement")
	check(Interstitials.blocked_reason() == "ad_free", "ad-free suppresses interstitials outright")
	check(Entitlements.has_ever_purchased(), "first purchase is recorded")
	# Restore path: a reinstall gets the non-consumable back, consumables stay spent.
	GameState.rv_state.erase("entitlements")
	check(not Entitlements.no_ads(), "wiping local state clears the entitlement")
	check(Entitlements.restore(["no_ads", "gems_pouch"]) == 1,
		"restore returns only the non-consumable")
	check(Entitlements.no_ads(), "restore re-applies the ad-free entitlement")

func _test_pricing_is_honest() -> void:
	var best: String = Pricing.best_value_id()
	check(best != "", "a best-value tier is computable")
	var best_rate: float = float(DataLoader.get_iap(best).get("grants", {}).get("gems", 0)) \
		/ Pricing.price_usd(DataLoader.get_iap(best))
	var beaten: Array = []
	for pid in DataLoader.iap_products.keys():
		var def: Dictionary = DataLoader.iap_products[pid]
		if str(def.get("kind", "")) != "gems" or str(def.get("tag", "")) != "regular":
			continue
		var rate: float = float(def.get("grants", {}).get("gems", 0)) / Pricing.price_usd(def)
		if rate > best_rate + 0.0001:
			beaten.append(pid)
	check(beaten.is_empty(), "BEST VALUE really is the best gems-per-dollar (beaten by %s)" % str(beaten))
	# An entry-tier pack cannot claim a bonus over itself.
	check(Pricing.bonus_pct(DataLoader.get_iap("gems_pouch")) == 0,
		"the entry pouch claims no bonus over itself")
	# A saving is only claimed where the anchor genuinely exceeds the price.
	var lying: Array = []
	for pid in DataLoader.iap_products.keys():
		var d: Dictionary = DataLoader.iap_products[pid]
		if Pricing.savings_pct(d) > 0 and Pricing.alacarte_usd(d) <= Pricing.price_usd(d):
			lying.append(pid)
	check(lying.is_empty(), "no product claims a saving it cannot show (%s)" % str(lying))
	# Nothing in the catalog or the shopfront invents social proof.
	var claim_found: bool = false
	for line in FileAccess.get_file_as_string("res://scenes/store/store_screen.gd").split("\n"):
		if str(line).strip_edges().begins_with("#"):
			continue  # the header explains why we do not make this claim
		if str(line).to_upper().contains("MOST POPULAR"):
			claim_found = true
	check(not claim_found, "the store makes no unsupported popularity claim")

func _test_consent_gate() -> void:
	check(Consent.has_method("required"), "a consent gate exists")
	check(typeof(Consent.policy()) == TYPE_DICTIONARY, "the policy block is readable")
	check(Consent.policy().has("child_directed"), "child-directed treatment is declared in data")
	Consent.reset_choice()
	check(Consent.required(), "a cleared choice asks again")
	check(not Analytics.consent_granted(), "analytics stops writing when consent is withdrawn")
	Consent.set_choice(true, false)
	check(not Consent.required(), "a recorded choice stops the prompt")
	check(Analytics.consent_granted(), "granting consent re-enables analytics")
	check(not Consent.personalized_ads(), "personalization stays off unless explicitly chosen")
	check(IAPService.has_method("restore_purchases"), "a restore-purchases entry point exists")

# ------------------------------------------------------------------- helpers

func _reset_rv() -> void:
	for pid in RV.PLACEMENTS:
		GameState.rv_state.erase(pid)
	RV._in_flight.clear()

func _reset_iap() -> void:
	IAPCat._in_flight.clear()
	for key in GameState.rv_state.keys():
		if str(key).begins_with("iap_"):
			GameState.rv_state.erase(key)
	GameState.rv_state.erase(IAPCat.RECEIPTS_KEY)

## Move the clock the way a player with the settings app would: ClockGuard.now() is
## the only system-clock reader below MonoClock, so shadowing it here is exactly the
## attack surface. Returns the shifted reading.
func _now_with_offset(seconds: int) -> int:
	ClockGuard.set_meta("test_offset", seconds)
	if not ClockGuard.has_meta("patched"):
		ClockGuard.set_meta("patched", true)
		ClockGuard.set_script(_offset_clock_script())
	return ClockGuard.now()

func _clear_offset() -> void:
	ClockGuard.set_meta("test_offset", 0)

func _offset_clock_script() -> GDScript:
	var src := """
extends Node
var _highest_seen_unix: int = 0
func now() -> int:
	return int(Time.get_unix_time_from_system()) + int(get_meta("test_offset", 0))
func validate_elapsed(from_unix: int, to_unix: int, cap_seconds: int) -> int:
	if from_unix <= 0 or to_unix <= 0:
		return 0
	if to_unix < from_unix - 60:
		EventBus.clock_anomaly.emit("rollback")
		return 0
	return mini(maxi(to_unix - from_unix, 0), cap_seconds)
func note_seen(unix_time: int) -> void:
	_highest_seen_unix = maxi(_highest_seen_unix, unix_time)
"""
	var gd := GDScript.new()
	gd.source_code = src
	gd.reload()
	return gd
