extends SceneTree
## test_monetization.gd — monetization branch tests (SPEC §12).
## Run: godot --headless --path <repo> -s tests/monetization/test_monetization.gd
## Exit 0 = all pass, 1 = any failure.
## Autoload singletons are not registered for a -s main script, so we bootstrap
## them as named root children and shadow their names with member variables
## (same pattern as tests/core). Monetization modules are load()ed at runtime.
## Ad success is simulated via the public grant handlers / manual ad_result
## emits; IAP success uses the debug IAPService's real 0.4s timer.

var failures: int = 0

# Autoload shadows (assigned in run()).
var EventBus: Node
var DataLoader: Node
var ClockGuard: Node
var Analytics: Node
var AdService: Node
var IAPService: Node
var GameState: Node
var SaveSystem: Node
var Economy: Node

# Monetization modules (GDScript with static funcs).
var RV: GDScript
var IAPCat: GDScript
var Deals: GDScript
var Offers: GDScript

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
	root.get_node("SaveSystem").set_process(false)  # Economy._process must not tick during tests

	_test_instant_cash_math()
	_test_free_gems_cap()
	_test_income_x2_stack_and_cap()
	_test_ad_failure_toast()
	_test_daily_deals()
	await _test_offer_triggers()
	await _test_purchases()
	_test_prices_end_in_9()

	print("---")
	if failures == 0:
		print("ALL MONETIZATION TESTS PASSED")
	else:
		printerr("MONETIZATION TESTS FAILED: %d" % failures)
	quit(0 if failures == 0 else 1)

## SceneTree bootstrap: instantiate the 9 project autoloads as named root children.
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
	Deals = load("res://scripts/monetization/daily_deals.gd")
	Offers = load("res://scripts/monetization/offer_system.gd")

# ---------------------------------------------------------------------- tests

func _test_instant_cash_math() -> void:
	var rate: BigNumber = Economy.current_cash_per_second()
	check(rate.gt(BigNumber.zero()), "instant_cash: venue income rate is positive")
	var before: BigNumber = GameState.cash
	RV.grant_instant_cash()
	var expected: BigNumber = before.add(rate.scale(15.0 * 60.0))
	check(GameState.cash.cmp(expected) == 0,
		"instant_cash: grant = 15min x rate (got %s, want %s)" % [
			GameState.cash.sub(before).to_notation(), rate.scale(900.0).to_notation()])

func _test_free_gems_cap() -> void:
	var before: int = GameState.gems
	RV.grant_free_gems()
	RV.grant_free_gems()
	RV.grant_free_gems()
	check(GameState.gems == before + 15, "free_gems: 3 views grant 3x5 gems")
	check(int(GameState.rv_state["free_gems"]["count"]) == 3, "free_gems: count tracked in rv_state")
	RV.grant_free_gems()  # 4th must be blocked
	check(GameState.gems == before + 15, "free_gems: daily cap 3 blocks 4th grant")
	check(int(GameState.rv_state["free_gems"]["count"]) == 3, "free_gems: blocked view not counted")
	check(RV.remaining_free_gems() == 0, "free_gems: remaining hits 0 at cap")
	# Day rollover: stale day string resets the counter.
	GameState.rv_state["free_gems"]["day"] = "2000-01-01"
	check(RV.remaining_free_gems() == 3, "free_gems: day rollover resets the daily cap")

func _test_income_x2_stack_and_cap() -> void:
	var now: int = ClockGuard.now()
	RV.grant_income_x2()
	var until1: int = int(GameState.boosts["income_x2_until"])
	check(absi(until1 - (now + 2 * 3600)) <= 2, "income_x2: first view sets +2h")
	RV.grant_income_x2()
	var until2: int = int(GameState.boosts["income_x2_until"])
	check(absi(until2 - (now + 4 * 3600)) <= 2, "income_x2: second view stacks to +4h")
	RV.grant_income_x2()
	RV.grant_income_x2()
	RV.grant_income_x2()  # would be +10h, must cap at +8h
	var until5: int = int(GameState.boosts["income_x2_until"])
	check(absi(until5 - (now + 8 * 3600)) <= 2, "income_x2: stacks cap at +8h")
	check(GameState.income_boost_active() == 2.0, "income_x2: boost multiplier active")
	check(RV.income_x2_remaining_seconds() > 7 * 3600, "income_x2: remaining stack time reported")

func _test_ad_failure_toast() -> void:
	RV._ensure_connected()
	var got_toast: Array = [""]
	var cb: Callable = func(text: String) -> void: got_toast[0] = text
	EventBus.toast_requested.connect(cb)
	AdService.ad_result.emit("income_x2", false, {})
	EventBus.toast_requested.disconnect(cb)
	check(got_toast[0] == "Ad unavailable — try again soon", "ad failure: toast emitted")

func _test_daily_deals() -> void:
	var shelf: Array = Deals.shelf()
	check(shelf.size() == 3, "daily deals: shelf has 3 slots")
	var all_daily: bool = true
	for pid in shelf:
		if str(DataLoader.get_iap(str(pid)).get("tag", "")) != "daily":
			all_daily = false
	check(all_daily, "daily deals: shelf items all tagged daily")
	check(Deals.seconds_until_refresh() > 0, "daily deals: refresh countdown in future")
	# Auto-refresh when refresh_at is in the past.
	GameState.daily_deals["refresh_at"] = ClockGuard.now() - 5
	var shelf2: Array = Deals.shelf()
	check(shelf2.size() == 3 and Deals.refresh_at() > ClockGuard.now(), "daily deals: auto-refresh when due")
	# Force refresh: cost + cap.
	GameState.add_gems(100)
	var gems_before: int = GameState.gems
	check(Deals.force_refresh(), "daily deals: force refresh succeeds")
	check(GameState.gems == gems_before - 10, "daily deals: force refresh costs 10 gems")
	check(Deals.force_refresh() and Deals.force_refresh(), "daily deals: 2 more force refreshes ok")
	check(Deals.force_refreshes_left() == 0, "daily deals: force cap reached after 3")
	check(not Deals.force_refresh(), "daily deals: 4th force refresh blocked by cap")

func _test_offer_triggers() -> void:
	Offers.check_triggers()
	check(Offers._status("offer_venue2") == "", "offers: venue_2 offer hidden before unlock")
	# Simulate prestige into the 2nd venue.
	GameState.venues_unlocked.append("copper_kettle")
	EventBus.prestige_performed.emit("whispering_pines", "copper_kettle")
	check(Offers._status("offer_venue2") == "shown", "offers: venue_2_start trigger shows offer")
	check(Offers._status("offer_venue2_gems") == "shown", "offers: second venue_2 offer also shown")
	var ids: Array = Offers.active_offers().map(func(o: Dictionary) -> String: return str(o["id"]))
	check("offer_venue2" in ids, "offers: shown offer listed as active")
	check(Offers.seconds_left("offer_venue2") > 23 * 3600, "offers: expiry countdown ~24h")
	check(Offers._status("offer_rep10") == "", "offers: rep_10 offer hidden at rep 1")
	# Buy the venue-2 offer: routes through iap_catalog (debug IAP succeeds).
	var gems_before: int = GameState.gems
	check(Offers.buy("offer_venue2"), "offers: buy initiates purchase")
	await create_timer(0.6).timeout
	check(Offers._status("offer_venue2") == "bought", "offers: purchase marks offer bought")
	check(GameState.gems >= gems_before + 300, "offers: starter bundle gems granted")
	var ids2: Array = Offers.active_offers().map(func(o: Dictionary) -> String: return str(o["id"]))
	check("offer_venue2" not in ids2, "offers: bought offer leaves active list")

func _test_purchases() -> void:
	# Gems product via the real (debug) async purchase flow.
	var gems_before: int = GameState.gems
	check(IAPCat.purchase("gems_pouch"), "purchase: initiate accepted")
	await create_timer(0.6).timeout
	check(GameState.gems == gems_before + 80, "purchase: gems pack grants 80 gems")
	check(int(GameState.rv_state["iap_gems_pouch"]["count"]) == 1, "purchase: daily count tracked")
	# Cash pack: grant = cash_seconds x current income (direct success handler).
	var rate: BigNumber = Economy.current_cash_per_second()
	var cash_before: BigNumber = GameState.cash
	IAPCat.apply_grants("cash_hour")
	var want: BigNumber = cash_before.add(rate.scale(3600.0))
	check(GameState.cash.cmp(want) == 0, "purchase: cash_seconds x income granted (%s)" % rate.scale(3600.0).to_notation())
	# Insight pack.
	IAPCat.apply_grants("insight_scholar")
	check(GameState.insight.gte(BigNumber.from_float(150.0)), "purchase: insight pack granted")
	# Bundle with a box grant drew cards (starter bundle bought in the offer test).
	IAPCat.apply_grants("inspection_prep_bundle")
	var total_cards: int = 0
	for mid in GameState.managers_state.keys():
		total_cards += int(GameState.managers_state[mid]["cards"])
	check(total_cards >= 8, "purchase: starter bundle box drew cards (%d)" % total_cards)
	# limit_per_day: starter_bundle limit is 1 and the offer buy consumed it.
	check(not IAPCat.purchase("starter_bundle"), "purchase: limit_per_day blocks repeat buy")

func _test_prices_end_in_9() -> void:
	var bad: Array = []
	for pid in DataLoader.iap_products.keys():
		var price: String = str(DataLoader.iap_products[pid].get("price_usd", ""))
		if not price.ends_with("9"):
			bad.append(pid)
	check(bad.is_empty(), "catalog: all %d prices end in 9 (bad: %s)" % [
		DataLoader.iap_products.size(), str(bad)])
	# Offer iap_ids all resolve to real products.
	var missing: Array = []
	for oid in DataLoader.offers.keys():
		if DataLoader.get_iap(str(DataLoader.offers[oid].get("iap_id", ""))).is_empty():
			missing.append(oid)
	check(missing.is_empty(), "offers: all %d offer iap_ids exist in store_iap.json (bad: %s)" % [
		DataLoader.offers.size(), str(missing)])
