extends SceneTree
## QA M5-5: ad-failure / airplane-mode paths (SPEC §8).
## - AdService.show_rewarded with context.simulate_failure -> RV placements grant
##   NOTHING and EventBus.toast_requested fires.
## - Airplane mode (AdService.debug_ads=false -> always fails): same guarantees.
## - IAPService.debug_iap=false -> iap_result(false) -> no grants, no iap_completed.
## - Welcome Back 2x ad failure -> no bonus cash; success path still pays exactly 1x extra.
## Run: godot --headless --path <repo> -s tests/qa/test_ad_failure.gd

var failures: int = 0
var toasts: Array = []
var grants: Array = []
var iap_done: Array = []

func check(cond: bool, msg: String) -> void:
	if cond:
		print("  PASS ", msg)
	else:
		failures += 1
		printerr("  FAIL ", msg)

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var EB: Node = root.get_node("EventBus")
	var DL: Node = root.get_node("DataLoader")
	var GS: Node = root.get_node("GameState")
	var ADS: Node = root.get_node("AdService")
	var IAP: Node = root.get_node("IAPService")
	DL.reload_all()
	GS.reset_to_new_game()
	GS.ready_flag = false
	EB.toast_requested.connect(func(t): toasts.append(t))
	EB.rv_reward_granted.connect(func(p, c): grants.append(p))
	EB.iap_completed.connect(func(p): iap_done.append(p))
	var RV: GDScript = load("res://scripts/monetization/rv_placements.gd")
	var IAPCat: GDScript = load("res://scripts/monetization/iap_catalog.gd")

	print("-- simulate_failure=true (debug ads on) --")
	RV.instant_cash()  # connects the static RV router
	await create_timer(0.6).timeout
	check("instant_cash" in grants, "baseline: debug ad success grants instant_cash")
	grants.clear()
	toasts.clear()
	var cash0: BigNumber = GS.cash.copy()
	ADS.show_rewarded("instant_cash", {"simulate_failure": true})
	await create_timer(0.6).timeout
	check(GS.cash.eq(cash0), "failed instant_cash ad grants NO cash")
	check(grants.is_empty(), "failed ad emits no rv_reward_granted")
	check(toasts.any(func(t): return "unavailable" in t), "failed ad fires 'Ad unavailable' toast (got %s)" % str(toasts))

	print("-- airplane mode: debug_ads=false --")
	ADS.debug_ads = false
	toasts.clear()
	grants.clear()
	cash0 = GS.cash.copy()
	var gems0: int = GS.gems
	RV.instant_cash()
	await create_timer(0.5).timeout
	check(GS.cash.eq(cash0), "airplane mode: instant_cash grants nothing")
	check(grants.is_empty(), "airplane mode: no rv_reward_granted")
	check(toasts.any(func(t): return "unavailable" in t), "airplane mode: toast fired")
	toasts.clear()
	RV.free_gems()
	await create_timer(0.5).timeout
	check(GS.gems == gems0, "airplane mode: free_gems grants nothing")
	check(toasts.any(func(t): return "unavailable" in t), "airplane mode: free_gems toast fired")
	toasts.clear()
	RV.income_x2()
	await create_timer(0.5).timeout
	check(int(GS.boosts.get("income_x2_until", 0)) == 0, "airplane mode: no x2 boost granted")
	check(GS.income_boost_active() == 1.0, "airplane mode: income multiplier stays 1.0")
	ADS.debug_ads = true

	print("-- IAP failure: debug_iap=false --")
	toasts.clear()
	iap_done.clear()
	gems0 = GS.gems
	cash0 = GS.cash.copy()
	IAP.debug_iap = false
	check(IAPCat.purchase("gems_pouch") == true, "purchase() initiates in release mode")
	await create_timer(0.5).timeout
	check(GS.gems == gems0, "failed IAP grants no gems")
	check(GS.cash.eq(cash0), "failed IAP grants no cash")
	check(iap_done.is_empty(), "failed IAP does not emit iap_completed")
	check(toasts.any(func(t): return "failed" in t.to_lower()), "failed IAP fires toast (got %s)" % str(toasts))
	IAP.debug_iap = true

	print("-- Welcome Back 2x ad failure -> no bonus cash --")
	var WB: PackedScene = load("res://scenes/ui/welcome_back.tscn")
	check(WB != null and WB.can_instantiate(), "welcome_back.tscn loads")
	var wb: Control = WB.instantiate()
	root.add_child(wb)
	var offline_amount := BigNumber.from_parts(1.0, 3)  # 1K already applied by SaveSystem
	wb.setup({"amount": offline_amount, "seconds": 7200})
	toasts.clear()
	grants.clear()
	cash0 = GS.cash.copy()
	ADS.debug_ads = false
	wb._on_watch_ad(2.0)
	await create_timer(0.5).timeout
	check(GS.cash.eq(cash0), "welcome_back ad failure: no bonus cash granted")
	check(not ("welcome_back" in grants), "welcome_back ad failure: no rv_reward_granted")
	check(toasts.any(func(t): return "unavailable" in t), "welcome_back ad failure: toast fired")
	ADS.debug_ads = true
	print("-- Welcome Back 2x success pays exactly +1x extra --")
	toasts.clear()
	wb._on_watch_ad(2.0)
	await create_timer(0.6).timeout
	check(GS.cash.eq(cash0.add(offline_amount)), "welcome_back 2x success adds exactly +1x (got +%s)"
		% GS.cash.sub(cash0).to_notation())
	check("welcome_back" in grants, "welcome_back success emits rv_reward_granted")
	# Leave wb in the tree; normal teardown frees it (see M5-1 teardown finding).

	print("---")
	if failures == 0:
		print("ALL QA AD-FAILURE TESTS PASSED")
	else:
		printerr("QA AD-FAILURE TESTS FAILED: %d" % failures)
	quit(0 if failures == 0 else 1)
