extends RefCounted
## interstitials.gd — frequency policy for full-screen ads. AdService shows them;
## this decides whether one may be shown at all.
##
## The rules, and why each is here rather than left to the ad SDK:
##  · Never during the first session minute, and never before the player has seen
##    the game work. An interstitial in front of a first run is the single fastest
##    way to a one-star review.
##  · A hard gap between ads and a daily count, both persisted, so the cap survives
##    a force-quit. Both key off the guarded clock, so winding the phone forward
##    does not buy extra impressions.
##  · Suppressed outright by the ad-free entitlement. An ad-free purchase that still
##    shows interstitials is a refund and a policy complaint.
##  · Never over a rewarded video: AdService's single-show gate would reject it, but
##    asking first keeps the log honest about *why* nothing was shown.
##
## Defaults live here rather than in data/balance_core.json because that file
## belongs to another track; every value still reads through monetization_tuning
## first, so moving them into data later needs no code change.
##
## State: GameState.rv_state["interstitial"] = {count:int, day:"YYYY-MM-DD", last:int}

const MonoClock := preload("res://scripts/monetization/mono_clock.gd")
const Entitlements := preload("res://scripts/monetization/entitlements.gd")

const STATE_KEY := "interstitial"
const DEFAULT_PER_DAY := 6
const DEFAULT_MIN_GAP_SECONDS := 240
const DEFAULT_MIN_SESSION_SECONDS := 90

static var _session_start_ms: int = -1

static func _tuning() -> Dictionary:
	return DataLoader.core.get("monetization_tuning", {})

static func _per_day() -> int:
	return int(_tuning().get("interstitial_per_day", DEFAULT_PER_DAY))

static func _min_gap() -> int:
	return int(_tuning().get("interstitial_min_gap_seconds", DEFAULT_MIN_GAP_SECONDS))

static func _min_session() -> int:
	return int(_tuning().get("interstitial_min_session_seconds", DEFAULT_MIN_SESSION_SECONDS))

static func _st() -> Dictionary:
	var today: String = MonoClock.today()
	var st: Variant = GameState.rv_state.get(STATE_KEY, null)
	if typeof(st) != TYPE_DICTIONARY or str((st as Dictionary).get("day", "")) != today:
		st = {"count": 0, "day": today, "last": 0}
		GameState.rv_state[STATE_KEY] = st
	return st

static func shown_today() -> int:
	return int(_st().get("count", 0))

static func remaining_today() -> int:
	return maxi(0, _per_day() - shown_today())

## Why an interstitial cannot be shown right now, or "" when it can.
static func blocked_reason() -> String:
	if Entitlements.no_ads():
		return "ad_free"
	if _session_seconds() < _min_session():
		return "session_too_young"
	if remaining_today() <= 0:
		return "daily_cap"
	var since: int = MonoClock.elapsed_since(int(_st().get("last", 0)))
	if int(_st().get("last", 0)) > 0 and since < _min_gap():
		return "min_gap"
	return ""

static func can_show() -> bool:
	return blocked_reason() == ""

## Ask for an interstitial at a natural break (`trigger` names the break, e.g.
## "venue_switch"). Returns true only when one was actually requested.
static func maybe_show(trigger: String) -> bool:
	var reason: String = blocked_reason()
	if reason == "" and not AdService.interstitial_available():
		# The SDK has none loaded: don't spend today's slot on a blank break.
		AdService.prepare_interstitial()
		reason = "not_loaded"
	if reason != "":
		Analytics.log_event("interstitial_suppressed", {"trigger": trigger, "reason": reason})
		return false
	var st: Dictionary = _st()
	# Count and stamp before the show, not after: the ad is on screen for seconds
	# and a second trigger inside that window must not slip past the gap check.
	st["count"] = int(st.get("count", 0)) + 1
	st["last"] = MonoClock.now()
	AdService.show_interstitial("interstitial_" + trigger, {})
	return true

## Session clock, measured in process ticks so it cannot be shortened by the
## device clock. Called once at boot from the shell.
static func note_session_start() -> void:
	_session_start_ms = Time.get_ticks_msec()
	if not Entitlements.no_ads():
		AdService.prepare_interstitial()

static func _session_seconds() -> int:
	if _session_start_ms < 0:
		note_session_start()
	return int((Time.get_ticks_msec() - _session_start_ms) / 1000)
