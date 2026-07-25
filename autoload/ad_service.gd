extends Node
## AdService — mediation-shaped ad interface. A real SDK (AdMob + a mediation
## adapter) drops in behind these methods; nothing above this file changes.
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
## Simulation knobs (debug only, via the context Dictionary):
##   simulate_failure  -> the ad plays and then fails at reward time
##   simulate_no_fill  -> the load returns no fill
## No network calls, no SDK dependency: this file is an interface plus a stub.

signal ad_result(placement_id: String, success: bool, context: Dictionary)
signal ad_load_changed(placement_id: String, state: int)
signal interstitial_result(placement_id: String, shown: bool)

enum { IDLE, LOADING, READY, SHOWING, FAILED }

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

var debug_ads: bool = _default_debug_ads()
## How long a load may take before the placement is declared failed. Real
## mediation waterfalls can stall indefinitely on a bad network; without this the
## player watches a dead button.
var load_timeout_seconds: float = 8.0
## Optional server-side verification hook: `func(placement_id, token, context) -> bool`.
## Left unset, verification is local (token redemption only). A real deployment
## points this at an SSV callback check before any currency moves.
var reward_verifier: Callable = Callable()

var _state: Dictionary = {}        # placement_id -> int (enum above)
var _load_seq: Dictionary = {}     # placement_id -> int, invalidates stale load timers
var _showing: String = ""
var _pending_tokens: Dictionary = {}   # token -> placement_id
var _token_counter: int = 0

## Release builds must never run the simulator. `is_debug_build()` is false in an
## exported release template; the `release` feature tag is belt-and-braces for a
## debug-template build exported with release features.
static func _default_debug_ads() -> bool:
	return OS.is_debug_build() and not OS.has_feature("release")

func _ready() -> void:
	for pid in KNOWN_PLACEMENTS:
		request_load(pid)

# ---------------------------------------------------------------- load state

func state_of(placement_id: String) -> int:
	return int(_state.get(placement_id, IDLE))

## True only when an ad can be shown right now. A false here is a real answer —
## callers should say so and offer the alternative, not spin.
func is_ready(placement_id: String) -> bool:
	if placement_id == "":
		return false
	var st: int = state_of(placement_id)
	if st == IDLE or st == FAILED:
		request_load(placement_id)  # self-healing: a failed placement retries on ask
	return st == READY

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

## Full-screen interstitial. Policy (frequency caps, ad-free entitlement, session
## boundaries) lives in scripts/monetization/interstitials.gd — this only shows one.
func show_interstitial(placement_id: String, context: Dictionary = {}) -> void:
	if _showing != "":
		interstitial_result.emit(placement_id, false)
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

func _sleep(seconds: float) -> void:
	var tree := get_tree()
	if tree == null:
		return
	await tree.create_timer(seconds).timeout
