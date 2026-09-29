extends SceneTree
## test_admob.gd — the AdMob backend (admob_ads.gd) against a fake of the
## Poing Studios godot-admob-plugin's GDScript classes, then AdService driving it.
##
## Proves: no plugin degrades to no ads; start sets the content rating and the
## child-directed flag; one load per format with the configured unit, npa=1
## until the player consents; a shown ad is spent, destroyed and replaced;
## earned+dismissed pays, early close doesn't, a late reward is honoured; no
## fill and errors report their reasons; interstitials show and warm up. Through
## AdService: one loaded ad readies every rewarded placement, the result carries
## a one-shot reward token, a second show is refused, the game is muted under
## the ad, a stalled load times out, and the interstitial policy doesn't spend
## a slot when nothing is loaded.
## What still needs a device: the real plugin on Android and iOS.

var AdMob: GDScript
var failures := 0

func check(cond: bool, msg: String) -> void:
	if cond:
		print("  PASS ", msg)
	else:
		failures += 1
		printerr("  FAIL ", msg)

func _init() -> void:
	call_deferred("run")

## Shared record of what the fake SDK was asked to do.
class Sdk:
	static var inits := 0
	static var configs: Array = []
	static var loads: Array = []   # {format, unit, request, cb}
	static var shown: Array = []
	static var auto_fill := false

	static func reset() -> void:
		inits = 0
		configs.clear()
		loads.clear()
		shown.clear()
		auto_fill = false

	## Answer load i with an ad.
	static func fill(i: int) -> FakeAd:
		var ad := FakeAd.new()
		ad.format = str(loads[i]["format"])
		var f: Callable = (loads[i]["cb"] as Object).get("on_ad_loaded")
		f.call(ad)
		return ad

	## Answer load i with an error.
	static func fail(i: int, code: int, message: String) -> void:
		var err := FakeLoadError.new()
		err.code = code
		err.message = message
		var f: Callable = (loads[i]["cb"] as Object).get("on_ad_failed_to_load")
		f.call(err)

	static func last_format() -> String:
		return str(loads.back()["format"]) if not loads.is_empty() else ""

class FakeMobileAds:
	static func initialize(_listener: Variant = null) -> void:
		Sdk.inits += 1
	static func set_request_configuration(rc: Object) -> void:
		Sdk.configs.append(rc)

class FakeRequestConfiguration:
	var max_ad_content_rating: String = ""
	var tag_for_child_directed_treatment: int = -1
	var tag_for_under_age_of_consent: int = -1
	var test_device_ids: Array[String] = []

class FakeAdRequest:
	var keywords: Array[String] = []
	var extras: Dictionary = {}

class FakeLoadCallback:
	var on_ad_loaded: Callable = func(_ad: Object) -> void: pass
	var on_ad_failed_to_load: Callable = func(_err: Object) -> void: pass

class FakeFullScreenContentCallback:
	var on_ad_clicked: Callable = func() -> void: pass
	var on_ad_dismissed_full_screen_content: Callable = func() -> void: pass
	var on_ad_failed_to_show_full_screen_content: Callable = func(_err: Variant) -> void: pass
	var on_ad_impression: Callable = func() -> void: pass
	var on_ad_showed_full_screen_content: Callable = func() -> void: pass

class FakeRewardListener:
	var on_user_earned_reward: Callable = func(_item: Variant) -> void: pass

class FakeLoadError:
	var code := 0
	var message := ""

class FakeLoader:
	var format := ""
	func load(unit: String, request: Object, cb: Object) -> void:
		Sdk.loads.append({"format": format, "unit": unit, "request": request, "cb": cb})
		if Sdk.auto_fill:
			var ad := FakeAd.new()
			ad.format = format
			var f: Callable = cb.get("on_ad_loaded")
			f.call_deferred(ad)

class FakeRewardedLoader extends FakeLoader:
	func _init() -> void:
		format = "rewarded"

class FakeInterstitialLoader extends FakeLoader:
	func _init() -> void:
		format = "interstitial"

class FakeAd:
	var format := ""
	var full_screen_content_callback: Object = null
	var listener: Object = null
	var shows := 0
	var destroyed := false
	func show(l: Object = null) -> void:
		shows += 1
		listener = l
		Sdk.shown.append(self)
	func destroy() -> void:
		destroyed = true
	func earn() -> void:
		var f: Callable = listener.get("on_user_earned_reward")
		f.call(null)
	func dismiss() -> void:
		var f: Callable = full_screen_content_callback.get("on_ad_dismissed_full_screen_content")
		f.call()
	func fail_show() -> void:
		var f: Callable = full_screen_content_callback.get("on_ad_failed_to_show_full_screen_content")
		f.call(null)

func _fake_api() -> Dictionary:
	return {
		"MobileAds": FakeMobileAds,
		"AdRequest": FakeAdRequest,
		"RequestConfiguration": FakeRequestConfiguration,
		"RewardedAdLoader": FakeRewardedLoader,
		"RewardedAdLoadCallback": FakeLoadCallback,
		"InterstitialAdLoader": FakeInterstitialLoader,
		"InterstitialAdLoadCallback": FakeLoadCallback,
		"FullScreenContentCallback": FakeFullScreenContentCallback,
		"OnUserEarnedRewardListener": FakeRewardListener,
	}

func _new_admob() -> RefCounted:
	var a: RefCounted = AdMob.new()
	a._set_api_for_test(_fake_api())
	return a

func run() -> void:
	if not OS.has_environment("GRAND_EXHIBIT_TEST_RUN"):
		printerr("REFUSED: requires GRAND_EXHIBIT_TEST_RUN isolation"); quit(2); return
	AdMob = load("res://scripts/monetization/admob_ads.gd")
	var gs: Node = root.get_node("GameState")
	root.get_node("SaveSystem").set_process(false)
	gs.reset_to_new_game()
	gs.ready_flag = true
	var ads: Node = root.get_node("AdService")

	# Without the plugin (this build): no ads, and the simulator stays in charge.
	var bare: RefCounted = AdMob.new()
	check(not bare.available() and not bare.start({}), "without the plugin the backend reports no ads")
	check(not ads.using_real_ads(), "the test build runs AdService without the SDK")

	# Start: the audience policy reaches the SDK.
	Sdk.reset()
	var admob: RefCounted = _new_admob()
	check(admob.available(), "the backend binds to the plugin's classes")
	var cfg: Dictionary = ads.backend_config()
	var units: Dictionary = cfg["units"]
	check(str(units.get("rewarded", "")).begins_with("ca-app-pub-")
		and str(units.get("interstitial", "")).begins_with("ca-app-pub-"),
		"store_iap.json gives this platform's rewarded and interstitial units")
	cfg["child_directed"] = true
	check(admob.start(cfg) and Sdk.inits == 1, "start initializes the Mobile Ads SDK")
	var rc: Object = Sdk.configs[0] if not Sdk.configs.is_empty() else null
	check(rc != null and str(rc.get("max_ad_content_rating")) == "G"
		and int(rc.get("tag_for_child_directed_treatment")) == 1,
		"the content rating and child-directed flag reach the request configuration")

	# Loading.
	var loaded: Array = []
	var failed: Array = []
	admob.loaded.connect(func(f: String) -> void: loaded.append(f))
	admob.load_failed.connect(func(f: String, r: String) -> void: failed.append([f, r]))
	admob.load_ad("rewarded")
	admob.load_ad("rewarded")
	check(Sdk.loads.size() == 1 and str(Sdk.loads[0]["unit"]) == str(units["rewarded"]),
		"one load per format, with the configured unit")
	var req: Object = Sdk.loads[0]["request"]
	check(str((req.get("extras") as Dictionary).get("npa", "")) == "1",
		"without consent the request is non-personalized (npa=1)")
	var ad1: FakeAd = Sdk.fill(0)
	check(loaded == ["rewarded"] and admob.is_loaded("rewarded"), "a filled load is reported")
	admob.load_ad("rewarded")
	check(Sdk.loads.size() == 1, "a loaded ad isn't loaded again")

	# Showing: earned, then dismissed.
	var closed: Array = []
	admob.rewarded_closed.connect(func(e: bool, r: String) -> void: closed.append([e, r]))
	admob.show_rewarded()
	check(ad1.shows == 1 and not admob.is_loaded("rewarded") and admob.is_showing(),
		"showing spends the loaded ad")
	admob.show_rewarded()
	check(closed == [[false, "busy"]], "a second show while one is up answers busy")
	closed.clear()
	ad1.earn()
	ad1.dismiss()
	check(closed == [[true, ""]], "earned then dismissed reports a reward")
	check(ad1.destroyed and Sdk.loads.size() == 2 and not admob.is_showing(),
		"the spent ad is destroyed and the next one starts loading")

	# Closed early, then a late reward.
	var ad2: FakeAd = Sdk.fill(1)
	closed.clear()
	admob.show_rewarded()
	ad2.dismiss()
	check(closed == [[false, "dismissed"]], "closing before the reward reports no reward")
	ad2.earn()
	check(admob.take_late_reward() and not admob.take_late_reward(),
		"a reward that lands after the close is kept, once")

	# Show failure.
	var ad3: FakeAd = Sdk.fill(2)
	closed.clear()
	admob.show_rewarded()
	ad3.fail_show()
	check(closed == [[false, "show_failed"]] and ad3.destroyed, "a failed show reports show_failed")

	# Load failures.
	Sdk.fail(3, 1 if OS.get_name() == "iOS" else 3, "No fill.")
	check(failed.size() == 1 and failed[0] == ["rewarded", "no_fill"], "no fill is reported as no_fill")
	admob.load_ad("rewarded")
	Sdk.fail(4, 0, "Internal error.")
	check(failed.size() == 2 and failed[1] == ["rewarded", "load_failed"], "other errors report load_failed")

	# Consent granted mid-session.
	admob.set_personalized(true)
	admob.load_ad("rewarded")
	var req2: Object = Sdk.loads[5]["request"]
	check(not (req2.get("extras") as Dictionary).has("npa"), "after consent the request is personalized")

	# Interstitials.
	var ic: Array = []
	admob.interstitial_closed.connect(func(s: bool, r: String) -> void: ic.append([s, r]))
	admob.show_interstitial()
	check(ic == [[false, "not_loaded"]] and Sdk.last_format() == "interstitial",
		"an unloaded interstitial answers not_loaded and starts loading one")
	var iad: FakeAd = Sdk.fill(Sdk.loads.size() - 1)
	ic.clear()
	admob.show_interstitial()
	iad.dismiss()
	check(ic == [[true, ""]] and iad.destroyed and Sdk.last_format() == "interstitial",
		"an interstitial shows, is destroyed on close, and the next one loads")
	admob = null
	bare = null

	# ---- Through AdService.
	Sdk.reset()
	Sdk.auto_fill = true
	var live: RefCounted = _new_admob()
	live.start(ads.backend_config())
	ads._use_backend_for_test(live)
	check(ads.using_real_ads(), "AdService takes the SDK when one is present")
	ads.request_load("free_gems")
	await process_frame
	await process_frame
	check(ads.is_ready("free_gems") and ads.is_ready("instant_cash"),
		"one loaded ad makes every rewarded placement ready")
	check(Sdk.loads.size() == 1, "and they share it instead of loading one each")

	var results: Array = []
	ads.ad_result.connect(func(p: String, ok: bool, c: Dictionary) -> void: results.append([p, ok, c]))
	var mute0: bool = AudioServer.is_bus_mute(0)
	ads.show_rewarded("free_gems", {"src": "test"})
	check(ads.state_of("free_gems") == ads.SHOWING and AudioServer.is_bus_mute(0),
		"the ad is up and the game is muted")
	check(ads.state_of("instant_cash") == ads.LOADING, "other placements wait for the next ad")
	ads.show_rewarded("instant_cash")
	check(results.size() == 1 and not bool(results[0][1])
		and str((results[0][2] as Dictionary).get("fail_reason", "")) == "busy",
		"a second rewarded while one is up is refused")
	results.clear()
	var s1: FakeAd = Sdk.shown.back()
	s1.earn()
	s1.dismiss()
	check(results.size() == 1 and str(results[0][0]) == "free_gems" and bool(results[0][1]),
		"earned and dismissed: ad_result succeeds")
	var ctx: Dictionary = results[0][2] if not results.is_empty() else {}
	var token: String = str(ctx.get("reward_token", ""))
	check(token != "" and str(ctx.get("src", "")) == "test", "the result carries a reward token and the caller's context")
	check(ads.consume_reward_token(token, "free_gems") and not ads.consume_reward_token(token, "free_gems"),
		"the token redeems exactly once")
	check(AudioServer.is_bus_mute(0) == mute0, "the sound comes back after the ad")

	# A late reward still pays.
	await process_frame
	await process_frame
	results.clear()
	ads.show_rewarded("income_x2")
	var s2: FakeAd = Sdk.shown.back()
	s2.dismiss()
	check(results.is_empty(), "a close without a reward waits briefly for a late one")
	s2.earn()
	await create_timer(ads.REWARD_GRACE_SECONDS + 0.2).timeout
	check(results.size() == 1 and bool(results[0][1]), "a late reward still pays")
	for r in results:
		ads.consume_reward_token(str((r[2] as Dictionary).get("reward_token", "")))

	# Closing early pays nothing.
	await process_frame
	await process_frame
	results.clear()
	ads.show_rewarded("instant_cash")
	var s3: FakeAd = Sdk.shown.back()
	s3.dismiss()
	await create_timer(ads.REWARD_GRACE_SECONDS + 0.2).timeout
	check(results.size() == 1 and not bool(results[0][1])
		and str((results[0][2] as Dictionary).get("fail_reason", "")) == "not_completed",
		"closing the ad early pays nothing")
	check(AudioServer.is_bus_mute(0) == mute0, "the sound comes back after an early close")

	# A load that never answers times out.
	ads._clear_backend_for_test()
	Sdk.reset()
	var stalled: RefCounted = _new_admob()
	stalled.start(ads.backend_config())
	ads._use_backend_for_test(stalled)
	ads.load_timeout_seconds = 0.3
	results.clear()
	ads.show_rewarded("free_gems")
	await create_timer(0.7).timeout
	check(results.size() == 1 and not bool(results[0][1])
		and str((results[0][2] as Dictionary).get("fail_reason", "")) == "no_fill",
		"a stalled load gives up with no_fill")
	ads.load_timeout_seconds = 8.0

	# Interstitials through AdService and the frequency policy.
	var Inter: GDScript = load("res://scripts/monetization/interstitials.gd")
	var dl: Node = root.get_node("DataLoader")
	var tuning: Dictionary = dl.core.get("monetization_tuning", {})
	var had_min: bool = tuning.has("interstitial_min_session_seconds")
	var old_min: Variant = tuning.get("interstitial_min_session_seconds", 0)
	tuning["interstitial_min_session_seconds"] = 0
	dl.core["monetization_tuning"] = tuning
	gs.rv_state.erase("interstitial")
	check(not ads.interstitial_available(), "no interstitial is loaded yet")
	check(not Inter.maybe_show("test") and Inter.shown_today() == 0,
		"with none loaded, the break is skipped without spending a daily slot")
	check(Sdk.last_format() == "interstitial", "and one starts loading for the next break")
	Sdk.fill(Sdk.loads.size() - 1)
	var ir: Array = []
	ads.interstitial_result.connect(func(p: String, s: bool) -> void: ir.append([p, s]))
	check(ads.interstitial_available() and Inter.maybe_show("test") and Inter.shown_today() == 1,
		"a loaded interstitial is shown at the break")
	check(AudioServer.is_bus_mute(0), "the game is muted under the interstitial")
	var si: FakeAd = Sdk.shown.back()
	si.dismiss()
	check(ir == [["interstitial_test", true]] and AudioServer.is_bus_mute(0) == mute0,
		"its close is reported and the sound returns")
	if had_min:
		tuning["interstitial_min_session_seconds"] = old_min
	else:
		tuning.erase("interstitial_min_session_seconds")

	ads._clear_backend_for_test()
	live = null
	stalled = null
	Sdk.reset()
	await create_timer(0.8).timeout
	print("RESULT: ", "OK" if failures == 0 else "FAILED (%d)" % failures)
	quit(1 if failures > 0 else 0)
