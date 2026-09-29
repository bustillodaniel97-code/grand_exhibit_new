extends Node
## AdService — mediation-shaped ad interface. Google AdMob (admob_ads.gd) runs
## behind these methods on a phone build that carries the plugin; nothing above
## this file knows which one answered.
##
## What "mediation-shaped" means, and why each piece exists:
##  · Per-placement load state. A mediation SDK holds at most one loaded ad per
##    placement and one on screen at a time. v1's `is_ready()` was `return true`,
##    so every caller's "ad unavailable" branch was dead code and the release path
##    was never exercised.
##  · A single `_showing` gate. Three same-frame taps used to show three ads and
##    pay three rewards; no SDK can display two ads at once, so that was N rewards
##    for at most one impression. A second show while one is up returns busy.
##  · Reward tokens. `ad_result` is a global signal: anything can emit it. The
##    reward context now carries a one-shot token minted at show time; the grant
##    layer calls `consume_reward_token()` and grants only if it is redeemed, so a
##    replayed or forged success signal pays nothing.
##  · Release-safe default. `debug_ads` is derived from the build, not hardcoded
##    true, so an APK exported by someone who never read the README still cannot
##    ship simulated ads that grant every reward for free.
##
## Which path answers a request:
##   backend set    -> the real SDK (admob_ads.gd), debug or release build.
##   debug_ads      -> the simulator below (editor, tests, desktop playtests).
##   neither        -> an honest no-fill; callers already handle "unavailable".
##
## With the SDK, every rewarded placement shares one loaded ad: a placement is
## READY when an ad could be shown for it right now, and showing one sends the
## others back to LOADING while the next ad loads.
##
## Simulation knobs (debug only, via the context Dictionary):
##   simulate_failure  -> the ad plays and then fails at reward time
##   simulate_no_fill  -> the load returns no fill

signal ad_result(placement_id: String, success: bool, context: Dictionary)
signal ad_load_changed(placement_id: String, state: int)
signal interstitial_result(placement_id: String, shown: bool)

enum { IDLE, LOADING, READY, SHOWING, FAILED }

const AdMobAds := preload("res://scripts/monetization/admob_ads.gd")
const STORE_DATA_PATH := "res://data/store_iap.json"

## Placements warmed at boot so `is_ready()` can be truthful without every caller
## having to remember to preload. Adding a placement here is the only wiring a new
## rewarded surface needs.
const KNOWN_PLACEMENTS: Array[String] = [
	"instant_cash", "free_gems", "income_x2",
	"welcome_back", "insight_rush", "free_lootbox",
]

## Simulated timings. Short enough that the whole request->fill->show->reward path
## fits comfortably inside a test's 0.5s window, long enough that the UI's pending
## state is actually observable.
const _SIM_LOAD_SECONDS := 0.06
const _SIM_SHOW_SECONDS := 0.25
## Some ad networks report the reward a moment after the ad closes. A rewarded
## ad dismissed without a reward waits this long for a late one before failing.
const REWARD_GRACE_SECONDS := 0.5

var debug_ads: bool = _default_debug_ads()
## How long a load may take before the placement is declared failed. Real
## mediation waterfalls can stall indefinitely on a bad network; without this the
## player watches a dead button.
var load_timeout_seconds: float = 8.0
## Optional server-side verification hook: `func(placement_id, token, context) -> bool`.
## Left unset, verification is local (token redemption only). A real deployment
## points this at an SSV callback check before any currency moves.
var reward_verifier: Callable = Callable()
## Production transport. Non-null on a phone build with the AdMob plugin; null
## in the editor, the test suite and desktop builds.
var backend: RefCounted = null

var _state: Dictionary = {}        # placement_id -> int (enum above)
var _load_seq: Dictionary = {}     # placement_id -> int, invalidates stale load timers
var _load_started: Dictionary = {} # placement_id -> ticks (ms) of an SDK load
var _showing: String = ""
var _show_ctx: Dictionary = {}     # context of the SDK ad on screen
var _pending_tokens: Dictionary = {}   # token -> placement_id
var _token_counter: int = 0
var _muted_for_ad := false
var _mute_was := false

## Release builds must never run the simulator. `is_debug_build()` is false in an
## exported release template; the `release` feature tag is belt-and-braces for a
## debug-template build exported with release features.
static func _default_debug_ads() -> bool:
	return OS.is_debug_build() and not OS.has_feature("release")

func _ready() -> void:
	_init_backend()
	for pid in KNOWN_PLACEMENTS:
		request_load(pid)

# ------------------------------------------------------------------- backend

## Bring up AdMob if the build carries the plugin. Starts non-personalized;
## consent.gd pushes the player's choice once the save is loaded.
func _init_backend() -> void:
	var b: RefCounted = AdMobAds.new()
	if not b.available():
		return
	_bind_backend(b)
	b.start(backend_config())

func _bind_backend(b: RefCounted) -> void:
	b.loaded.connect(_on_backend_loaded)
	b.load_failed.connect(_on_backend_load_failed)
	b.rewarded_closed.connect(_on_backend_rewarded_closed)
	b.interstitial_closed.connect(_on_backend_interstitial_closed)
	backend = b

## Test seam: install a backend directly. Nothing in the game calls this.
func _use_backend_for_test(b: RefCounted) -> void:
	_bind_backend(b)
	_reset_placements()

## Test seam: drop the bound backend and start the placements over.
func _clear_backend_for_test() -> void:
	if backend != null:
		backend.loaded.disconnect(_on_backend_loaded)
		backend.load_failed.disconnect(_on_backend_load_failed)
		backend.rewarded_closed.disconnect(_on_backend_rewarded_closed)
		backend.interstitial_closed.disconnect(_on_backend_interstitial_closed)
	backend = null
	_mute_for_ad(false)
	_reset_placements()

func _reset_placements() -> void:
	_showing = ""
	_show_ctx = {}
	for pid in _state.keys():
		_load_seq[pid] = int(_load_seq.get(pid, 0)) + 1  # strands any in-flight load
		_set_state(str(pid), IDLE)

func using_real_ads() -> bool:
	return backend != null

## Consent changed (consent.gd apply()): the next ad request follows it.
func set_personalized(on: bool) -> void:
	if backend != null:
		backend.set_personalized(on)

## SDK settings from data/store_iap.json: this platform's ad units and the
## audience policy.
func backend_config() -> Dictionary:
	var ads: Dictionary = {}
	var policy: Dictionary = {}
	if FileAccess.file_exists(STORE_DATA_PATH):
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(STORE_DATA_PATH))
		if parsed is Dictionary:
			ads = (parsed as Dictionary).get("ads", {})
			policy = (parsed as Dictionary).get("policy", {})
	var units: Dictionary = ads.get("ios_units" if OS.get_name() == "iOS" else "units", {})
	return {
		"units": units,
		"child_directed": bool(policy.get("child_directed", false)),
		"max_ad_content_rating": str(policy.get("ad_content_rating", "G")),
		"personalized": false,
		"test_device_ids": ads.get("test_device_ids", []),
	}

func _format_of(placement_id: String) -> String:
	return "interstitial" if placement_id.begins_with("interstitial") else "rewarded"

func _on_backend_loaded(format: String) -> void:
	for pid in _state.keys():
		if _format_of(str(pid)) == format and state_of(str(pid)) == LOADING:
			_load_started.erase(pid)
			_set_state(str(pid), READY)
			Analytics.ad_event("ad_filled", str(pid))

func _on_backend_load_failed(format: String, reason: String) -> void:
	for pid in _state.keys():
		if _format_of(str(pid)) == format and state_of(str(pid)) == LOADING:
			_load_started.erase(pid)
			_fail_load(str(pid), reason)

## Showing spends the one loaded ad of a format, so every other placement that
## was counting on it goes back to loading the next.
func _requeue_format(format: String, except_id: String) -> void:
	for pid in _state.keys():
		if str(pid) != except_id and _format_of(str(pid)) == format and state_of(str(pid)) == READY:
			_set_state(str(pid), IDLE)
			request_load(str(pid))

## Keep the game quiet under a full-screen ad (iOS doesn't pause the app).
func _mute_for_ad(on: bool) -> void:
	if on and not _muted_for_ad:
		_mute_was = AudioServer.is_bus_mute(0)
		AudioServer.set_bus_mute(0, true)
		_muted_for_ad = true
	elif not on and _muted_for_ad:
		AudioServer.set_bus_mute(0, _mute_was)
		_muted_for_ad = false

# ---------------------------------------------------------------- load state

func state_of(placement_id: String) -> int:
	return int(_state.get(placement_id, IDLE))

## True only when an ad can be shown right now. A false here is a real answer —
## callers should say so and offer the alternative, not spin.
func is_ready(placement_id: String) -> bool:
	if placement_id == "":
		return false
	var st: int = state_of(placement_id)
	if st == LOADING and _load_expired(placement_id):
		_load_started.erase(placement_id)
		_set_state(placement_id, FAILED)
		Analytics.ad_event("ad_timeout", placement_id)
		st = FAILED
	if st == IDLE or st == FAILED:
		request_load(placement_id)  # self-healing: a failed placement retries on ask
	return state_of(placement_id) == READY

func _load_expired(placement_id: String) -> bool:
	if not _load_started.has(placement_id):
		return false
	return Time.get_ticks_msec() - int(_load_started[placement_id]) > int(load_timeout_seconds * 1000.0)

## Warm a placement. Idempotent while loading or already loaded.
func request_load(placement_id: String, context: Dictionary = {}) -> void:
	if placement_id == "":
		return
	var st: int = state_of(placement_id)
	if st == LOADING or st == READY or st == SHOWING:
		return
	_set_state(placement_id, LOADING)
	Analytics.ad_event("ad_requested", placement_id)
	var seq: int = int(_load_seq.get(placement_id, 0)) + 1
	_load_seq[placement_id] = seq
	_run_load(placement_id, context, seq)

func _run_load(placement_id: String, context: Dictionary, seq: int) -> void:
	if backend != null:
		# The SDK answers through _on_backend_loaded / _on_backend_load_failed.
		var fmt: String = _format_of(placement_id)
		if backend.is_loaded(fmt):
			_set_state(placement_id, READY)
			Analytics.ad_event("ad_filled", placement_id)
			return
		_load_started[placement_id] = Time.get_ticks_msec()
		backend.load_ad(fmt)
		return
	if not debug_ads:
		# Release path with no SDK wired: report an honest no-fill rather than
		# pretending an ad exists. Callers already handle "unavailable".
		await _sleep(0.05)
		if _stale(placement_id, seq):
			return
		_fail_load(placement_id, "no_sdk")
		return
	if bool(context.get("simulate_no_fill", false)):
		await _sleep(_SIM_LOAD_SECONDS)
		if _stale(placement_id, seq):
			return
		_fail_load(placement_id, "no_fill")
		return
	await _sleep(_SIM_LOAD_SECONDS)
	if _stale(placement_id, seq):
		return
	_set_state(placement_id, READY)
	Analytics.ad_event("ad_filled", placement_id)

func _fail_load(placement_id: String, reason: String) -> void:
	_set_state(placement_id, FAILED)
	Analytics.ad_event("ad_no_fill" if reason != "load_failed" else "ad_load_failed",
		placement_id, {"reason": reason})

func _stale(placement_id: String, seq: int) -> bool:
	return int(_load_seq.get(placement_id, 0)) != seq

func _set_state(placement_id: String, st: int) -> void:
	if int(_state.get(placement_id, IDLE)) == st:
		return
	_state[placement_id] = st
	ad_load_changed.emit(placement_id, st)

# ------------------------------------------------------------------ rewarded

## Show a rewarded video. Always terminates in exactly one `ad_result` emission
## for this call, so a caller that armed a one-shot listener is never left hanging.
func show_rewarded(placement_id: String, context: Dictionary = {}) -> void:
	if _showing != "":
		# Claimed synchronously below, so this rejects same-frame repeat taps too.
		Analytics.ad_event("rv_blocked", placement_id, {"reason": "busy", "showing": _showing})
		var busy_ctx: Dictionary = context.duplicate()
		busy_ctx["fail_reason"] = "busy"
		ad_result.emit(placement_id, false, busy_ctx)
		return
	_showing = placement_id
	await _run_rewarded(placement_id, context)

func _run_rewarded(placement_id: String, context: Dictionary) -> void:
	Analytics.ad_event("rv_requested", placement_id)
	if backend != null:
		await _run_rewarded_sdk(placement_id, context)
		return
	if not debug_ads:
		await _sleep(0.05)
		_finish(placement_id, false, context, "no_fill")
		return
	if bool(context.get("simulate_no_fill", false)):
		await _sleep(_SIM_LOAD_SECONDS)
		_finish(placement_id, false, context, "no_fill")
		return
	if state_of(placement_id) != READY:
		var filled: bool = await _await_fill(placement_id, context)
		if not filled:
			_finish(placement_id, false, context, "no_fill")
			return
	_set_state(placement_id, SHOWING)
	Analytics.ad_event("rv_started", placement_id)
	await _sleep(_SIM_SHOW_SECONDS)
	if bool(context.get("simulate_failure", false)):
		_finish(placement_id, false, context, "playback_failed")
		return
	_reward(placement_id, context)

## The SDK path: wait for a fill, put the ad up, and let the close callback
## (_on_backend_rewarded_closed) finish the show.
func _run_rewarded_sdk(placement_id: String, context: Dictionary) -> void:
	if state_of(placement_id) == READY and not backend.is_loaded("rewarded"):
		_set_state(placement_id, IDLE)
	if state_of(placement_id) != READY:
		var filled: bool = await _await_fill(placement_id, context)
		if not filled:
			_finish(placement_id, false, context, "no_fill")
			return
	_set_state(placement_id, SHOWING)
	_show_ctx = context
	Analytics.ad_event("rv_started", placement_id)
	_mute_for_ad(true)
	backend.show_rewarded()
	_requeue_format("rewarded", placement_id)

func _on_backend_rewarded_closed(earned: bool, reason: String) -> void:
	var pid: String = _showing
	if pid == "" or _format_of(pid) != "rewarded":
		return
	var ctx: Dictionary = _show_ctx
	_show_ctx = {}
	if not earned and reason == "dismissed":
		await _sleep(REWARD_GRACE_SECONDS)
		earned = backend != null and bool(backend.take_late_reward())
	_mute_for_ad(false)
	if _showing != pid:
		return  # reset underneath us (test teardown)
	if not earned:
		_finish(pid, false, ctx, "not_completed" if reason == "dismissed" else reason)
		return
	_reward(pid, ctx)

## The ad completed: mint the one-shot token the grant layer must redeem.
func _reward(placement_id: String, context: Dictionary) -> void:
	var token: String = _mint_token(placement_id)
	if not _verify(placement_id, token, context):
		_pending_tokens.erase(token)
		_finish(placement_id, false, context, "verification_failed")
		return
	var ctx: Dictionary = context.duplicate()
	ctx["reward_token"] = token
	_finish(placement_id, true, ctx, "")

func _await_fill(placement_id: String, context: Dictionary) -> bool:
	request_load(placement_id, context)
	var deadline: int = Time.get_ticks_msec() + int(load_timeout_seconds * 1000.0)
	while state_of(placement_id) == LOADING:
		await _sleep(0.02)
		if Time.get_ticks_msec() > deadline:
			_load_started.erase(placement_id)
			_set_state(placement_id, FAILED)
			Analytics.ad_event("ad_timeout", placement_id)
			return false
	return state_of(placement_id) == READY

func _finish(placement_id: String, success: bool, context: Dictionary, reason: String) -> void:
	if _showing == placement_id:
		_showing = ""
	_set_state(placement_id, IDLE if success else FAILED)
	var ctx: Dictionary = context.duplicate()
	if reason != "":
		ctx["fail_reason"] = reason
	Analytics.rv_outcome(placement_id, success, reason)
	ad_result.emit(placement_id, success, ctx)
	if success:
		request_load(placement_id)  # keep the next one warm

# ------------------------------------------------------------ reward tokens

func _mint_token(placement_id: String) -> String:
	_token_counter += 1
	var token: String = "%s:%d:%d" % [placement_id, Time.get_ticks_usec(), _token_counter]
	_pending_tokens[token] = placement_id
	return token

func _verify(placement_id: String, token: String, context: Dictionary) -> bool:
	if not reward_verifier.is_valid():
		return true  # local-only verification: redemption of the minted token
	return bool(reward_verifier.call(placement_id, token, context))

## Redeem a reward token exactly once. The grant layer must call this before
## moving any currency: an `ad_result` without a redeemable token is not a reward.
func consume_reward_token(token: String, placement_id: String = "") -> bool:
	if token == "" or not _pending_tokens.has(token):
		return false
	if placement_id != "" and str(_pending_tokens[token]) != placement_id:
		return false
	_pending_tokens.erase(token)
	return true

# -------------------------------------------------------------- interstitial

## Warm an interstitial so the next natural break has one ready. No-op without
## the SDK (the simulator fills on demand).
func prepare_interstitial() -> void:
	if backend != null:
		backend.load_ad("interstitial")

## False when the SDK has no interstitial loaded; the policy layer asks this
## before spending a daily slot.
func interstitial_available() -> bool:
	return backend == null or bool(backend.is_loaded("interstitial"))

## Full-screen interstitial. Policy (frequency caps, ad-free entitlement, session
## boundaries) lives in scripts/monetization/interstitials.gd — this only shows one.
func show_interstitial(placement_id: String, context: Dictionary = {}) -> void:
	if _showing != "":
		interstitial_result.emit(placement_id, false)
		return
	if backend != null:
		if not backend.is_loaded("interstitial"):
			backend.load_ad("interstitial")
			Analytics.ad_event("ad_no_fill", placement_id, {"format": "interstitial"})
			interstitial_result.emit(placement_id, false)
			return
		_showing = placement_id
		Analytics.ad_event("ad_requested", placement_id, {"format": "interstitial"})
		_mute_for_ad(true)
		backend.show_interstitial()
		return
	if not debug_ads:
		interstitial_result.emit(placement_id, false)
		return
	_showing = placement_id
	Analytics.ad_event("ad_requested", placement_id, {"format": "interstitial"})
	await _sleep(_SIM_LOAD_SECONDS)
	if bool(context.get("simulate_no_fill", false)):
		_showing = ""
		Analytics.ad_event("ad_no_fill", placement_id, {"format": "interstitial"})
		interstitial_result.emit(placement_id, false)
		return
	await _sleep(_SIM_SHOW_SECONDS)
	_showing = ""
	Analytics.ad_event("interstitial_shown", placement_id)
	interstitial_result.emit(placement_id, true)

func _on_backend_interstitial_closed(shown: bool, reason: String) -> void:
	var pid: String = _showing
	if pid == "" or _format_of(pid) != "interstitial":
		return
	_showing = ""
	_mute_for_ad(false)
	if shown:
		Analytics.ad_event("interstitial_shown", pid)
	else:
		Analytics.ad_event("ad_show_failed", pid, {"format": "interstitial", "reason": reason})
	interstitial_result.emit(pid, shown)

func _sleep(seconds: float) -> void:
	var tree := get_tree()
	if tree == null:
		return
	await tree.create_timer(seconds).timeout
