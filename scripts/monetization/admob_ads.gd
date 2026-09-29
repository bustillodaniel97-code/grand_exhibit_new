extends RefCounted
## admob_ads.gd — Google AdMob transport behind AdService (Android and iOS).
##
## The ads twin of play_billing.gd / app_store.gd: AdService keeps the game-side
## rules (placements, the single-show gate, one-shot reward tokens, the
## simulator) and hands the SDK work to this file. It drives the Poing Studios
## godot-admob-plugin, which exposes GDScript classes (MobileAds, AdRequest,
## RewardedAdLoader, ...) over a native singleton ("PoingGodotAdMob").
##
## NO STATIC REFERENCES. Those classes exist only when the addon is installed,
## and naming one directly would stop the project compiling without it. Every
## class is looked up by its global class name at runtime (the addon's folder
## layout moved between releases: addons/admob/src/api in v3,
## addons/admob/gdscript/src/api later), built with new() and driven with
## call()/set(). A missing addon or native singleton degrades to "no ads".
##
## What the SDK forces, and where it's handled:
##
##  1. ONE AD PER FORMAT. Every rewarded placement shares one ad unit, so this
##     keeps at most one loaded rewarded ad and one interstitial. Showing one
##     spends it; the next load starts as soon as it closes.
##  2. REWARD AND DISMISS ARE SEPARATE CALLBACKS. The reward is recorded when
##     on_user_earned_reward fires, and the show is reported when the ad is
##     dismissed. Some networks deliver the reward just after the dismissal, so
##     a reward that lands after the close is kept for take_late_reward().
##  3. CONSENT AND AUDIENCE. The request configuration carries the content
##     rating and child-directed flag from data/store_iap.json "policy"; a
##     player who hasn't agreed to personalized ads gets npa=1 on every request.
##  4. NO CYCLES. SDK callbacks hold method callables (bound to this object by
##     id), never lambdas, so the loaded ad and its callbacks don't keep this
##     object alive.
##
## tests/monetization/test_admob.gd drives all of it against a fake plugin.

const SINGLETON_NAMES: Array[String] = ["PoingGodotAdMob"]
const CLASSES: Array[String] = [
	"MobileAds", "AdRequest", "RequestConfiguration",
	"RewardedAdLoader", "RewardedAdLoadCallback",
	"InterstitialAdLoader", "InterstitialAdLoadCallback",
	"FullScreenContentCallback", "OnUserEarnedRewardListener",
]
const FORMATS: Array[String] = ["rewarded", "interstitial"]
## A load that hasn't answered in this long is abandoned, so a later ask can
## start a fresh one instead of waiting on it forever.
const LOAD_STALE_MS := 30000
## LoadAdError "no fill" codes: Android ERROR_CODE_NO_FILL, iOS GADErrorNoFill.
const _NO_FILL_ANDROID := 3
const _NO_FILL_IOS := 1

signal loaded(format: String)
signal load_failed(format: String, reason: String)
signal rewarded_closed(earned: bool, reason: String)
signal interstitial_closed(shown: bool, reason: String)

var _api: Dictionary = {}          # class name -> Script
var _started := false
var _units: Dictionary = {}        # format -> ad unit id
var _personalized := false
var _ads: Dictionary = {}          # format -> loaded ad object
var _loading: Dictionary = {}      # format -> ticks (ms) when the load started
## Loaders stay referenced here until they answer; the SDK wrapper only
## keeps itself alive through its own reference() call.
var _loaders: Dictionary = {}      # format -> loader object
var _on_screen: Object = null      # the ad being shown
var _showing := ""                 # its format, or "" when nothing is up
var _earned := false
var _late_reward := false

# ------------------------------------------------------------------ binding

func available() -> bool:
	return not _resolve_api().is_empty()

## Test seam: class name -> fake script.
func _set_api_for_test(api: Dictionary) -> void:
	_api = api

func _resolve_api() -> Dictionary:
	if not _api.is_empty():
		return _api
	var has_native := false
	for name in SINGLETON_NAMES:
		if Engine.has_singleton(name):
			has_native = true
	if not has_native:
		return {}
	var paths: Dictionary = {}
	for entry in ProjectSettings.get_global_class_list():
		var d: Dictionary = entry
		paths[str(d.get("class", ""))] = str(d.get("path", ""))
	var api: Dictionary = {}
	for cls in CLASSES:
		if not paths.has(cls):
			return {}
		var script: GDScript = load(str(paths[cls])) as GDScript
		if script == null:
			return {}
		api[cls] = script
	_api = api
	return _api

func _new(cls: String) -> Object:
	var script: GDScript = _api.get(cls, null) as GDScript
	if script == null:
		return null
	return script.new()

## MobileAds is all static functions; GDScript.call() reaches them.
func _mobile_ads(method: String, args: Array = []) -> void:
	var script: GDScript = _api.get("MobileAds", null) as GDScript
	if script != null:
		script.callv(method, args)

# ---------------------------------------------------------------- lifecycle

## config: {units: {rewarded, interstitial}, child_directed: bool,
##          max_ad_content_rating: String, personalized: bool,
##          test_device_ids: Array}
func start(config: Dictionary) -> bool:
	if _resolve_api().is_empty():
		return false
	var units: Dictionary = config.get("units", {})
	for fmt in FORMATS:
		_units[fmt] = str(units.get(fmt, ""))
	_personalized = bool(config.get("personalized", false))
	var rc: Object = _new("RequestConfiguration")
	if rc != null:
		rc.set("max_ad_content_rating", str(config.get("max_ad_content_rating", "G")))
		if bool(config.get("child_directed", false)):
			rc.set("tag_for_child_directed_treatment", 1)
			rc.set("tag_for_under_age_of_consent", 1)
		var ids: Array[String] = []
		for id in config.get("test_device_ids", []):
			ids.append(str(id))
		rc.set("test_device_ids", ids)
		_mobile_ads("set_request_configuration", [rc])
	_mobile_ads("initialize")
	_started = true
	Analytics.log_event("ads_sdk_started", {"network": "admob"})
	return true

func is_started() -> bool:
	return _started

## The player's consent can change mid-session (Privacy choices in the store);
## the next request picks it up.
func set_personalized(on: bool) -> void:
	_personalized = on

func _new_request() -> Object:
	var req: Object = _new("AdRequest")
	if req != null and not _personalized:
		var extras: Dictionary = {"npa": "1"}
		req.set("extras", extras)
	return req

# --------------------------------------------------------------------- load

func is_loaded(format: String) -> bool:
	return _ads.has(format)

func is_loading(format: String) -> bool:
	return _loading.has(format) and Time.get_ticks_msec() - int(_loading[format]) < LOAD_STALE_MS

## Start a load unless one is loaded or already on its way. Answers with
## loaded / load_failed.
func load_ad(format: String) -> void:
	if not _started or format not in FORMATS or is_loaded(format) or is_loading(format):
		return
	var unit: String = str(_units.get(format, ""))
	if unit == "":
		load_failed.emit(format, "no_unit")
		return
	var is_rv := format == "rewarded"
	var loader: Object = _new("RewardedAdLoader" if is_rv else "InterstitialAdLoader")
	var cb: Object = _new("RewardedAdLoadCallback" if is_rv else "InterstitialAdLoadCallback")
	if loader == null or cb == null:
		load_failed.emit(format, "no_sdk")
		return
	cb.set("on_ad_loaded", _on_loaded.bind(format))
	cb.set("on_ad_failed_to_load", _on_load_failed.bind(format))
	_loading[format] = Time.get_ticks_msec()
	_loaders[format] = loader
	loader.call("load", unit, _new_request(), cb)

func _on_loaded(ad: Object, format: String) -> void:
	_loading.erase(format)
	_loaders.erase(format)
	if ad == null:
		load_failed.emit(format, "load_failed")
		return
	_ads[format] = ad
	loaded.emit(format)

func _on_load_failed(err: Object, format: String) -> void:
	_loading.erase(format)
	_loaders.erase(format)
	load_failed.emit(format, _load_reason(err))

func _load_reason(err: Object) -> String:
	if err == null:
		return "load_failed"
	var code: int = int(err.get("code")) if err.get("code") != null else -1
	var no_fill: int = _NO_FILL_IOS if OS.get_name() == "iOS" else _NO_FILL_ANDROID
	if code == no_fill or str(err.get("message")).to_lower().contains("no fill"):
		return "no_fill"
	return "load_failed"

# --------------------------------------------------------------------- show

func is_showing() -> bool:
	return _showing != ""

## Show the loaded rewarded ad. Always answers with exactly one rewarded_closed.
func show_rewarded() -> void:
	if not _begin_show("rewarded"):
		rewarded_closed.emit(false, "busy" if is_showing() else "not_loaded")
		return
	var listener: Object = _new("OnUserEarnedRewardListener")
	if listener != null:
		listener.set("on_user_earned_reward", _on_earned)
	_on_screen.call("show", listener)

## Show the loaded interstitial. Always answers with exactly one interstitial_closed.
func show_interstitial() -> void:
	if not _begin_show("interstitial"):
		interstitial_closed.emit(false, "busy" if is_showing() else "not_loaded")
		load_ad("interstitial")
		return
	_on_screen.call("show")

func _begin_show(format: String) -> bool:
	if is_showing() or not is_loaded(format):
		return false
	_on_screen = _ads[format]
	_ads.erase(format)  # an ad shows once
	_showing = format
	_earned = false
	_late_reward = false
	var fsc: Object = _new("FullScreenContentCallback")
	if fsc != null:
		fsc.set("on_ad_dismissed_full_screen_content", _on_dismissed)
		fsc.set("on_ad_failed_to_show_full_screen_content", _on_show_failed)
		_on_screen.set("full_screen_content_callback", fsc)
	return true

func _on_earned(_item: Variant = null) -> void:
	if _showing == "rewarded":
		_earned = true
	else:
		_late_reward = true  # arrived after the dismissal

func _on_dismissed() -> void:
	var format := _showing
	if format == "":
		return
	var earned := _earned
	_end_show()
	if format == "rewarded":
		rewarded_closed.emit(earned, "" if earned else "dismissed")
	else:
		interstitial_closed.emit(true, "")

func _on_show_failed(_err: Variant = null) -> void:
	var format := _showing
	if format == "":
		return
	_end_show()
	if format == "rewarded":
		rewarded_closed.emit(false, "show_failed")
	else:
		interstitial_closed.emit(false, "show_failed")

func _end_show() -> void:
	var format := _showing
	var ad := _on_screen
	_showing = ""
	_on_screen = null
	if ad != null and ad.has_method("destroy"):
		ad.call("destroy")
	load_ad(format)  # keep the next one warm

## True once if a reward arrived after its ad was already dismissed.
func take_late_reward() -> bool:
	var got := _late_reward
	_late_reward = false
	return got
