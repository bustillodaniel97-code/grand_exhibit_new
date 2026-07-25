extends RefCounted
## mono_clock.gd — the clock every monetization cap reads. Wraps ClockGuard with
## a monotonic floor so "set the phone clock forward, harvest, set it back" costs
## more than it pays.
##
## Why not just use ClockGuard.now(): it returns the raw system clock. Every daily
## cap in this branch keys off a calendar-day string, so one forward clock set used
## to reset the free-gems cap, every limit_per_day, and the daily-deal shelf, and a
## set back restored the state to harvest again. ClockGuard only ever inspected the
## *backward* case, and only for offline earnings.
##
## The two guarantees this adds, both of which a client can actually keep:
##  1. Never goes backwards. A high-water mark rides in the save, so once the guarded
##     clock has seen a moment, no later reading is earlier than it. Winding the
##     device back does nothing except cost the player the wound-back interval.
##  2. Never jumps forward mid-session. Inside one run the clock advances by measured
##     process ticks (Time.get_ticks_msec, which the settings app cannot touch), so
##     changing the wall clock while the game is open moves nothing.
##
## What it deliberately does NOT claim: a forward set made while the game is closed
## is indistinguishable from real absence without a trusted time source. That case
## is accepted, logged as an anomaly and counted, and it costs the cheat a real day —
## because guarantee 1 makes it one-way.
##
## State lives in GameState.rv_state["_mono_clock"] = {high:int, anomalies:int}
## (rv_state is already persisted and already namespaced by this branch).

const STATE_KEY := "_mono_clock"
## NTP correction and timezone jitter are real and small. Deviations under this are
## absorbed silently; only a deliberate-looking shift is treated as an anomaly.
const JITTER_TOLERANCE := 90
const ANOMALY_THRESHOLD := 300
const ANOMALY_LOG_COOLDOWN_MS := 60000

static var _base_unix: int = 0
static var _base_ticks: int = 0
static var _last_flag_ms: int = -ANOMALY_LOG_COOLDOWN_MS

static func _st() -> Dictionary:
	var st: Variant = GameState.rv_state.get(STATE_KEY, null)
	if typeof(st) != TYPE_DICTIONARY:
		st = {"high": 0, "anomalies": 0}
		GameState.rv_state[STATE_KEY] = st
	return st

## Guarded unix seconds. Monotonic within a session and across saves.
static func now() -> int:
	var sys: int = ClockGuard.now()
	var st: Dictionary = _st()
	var high: int = int(st.get("high", 0))
	var ticks: int = Time.get_ticks_msec()
	# A fresh session (or a reset save) re-anchors: real absence between runs is
	# genuine elapsed time and must still count.
	if _base_unix <= 0 or _base_ticks > ticks:
		_base_unix = maxi(sys, high)
		_base_ticks = ticks
	var projected: int = _base_unix + int((ticks - _base_ticks) / 1000)
	if absi(sys - projected) > ANOMALY_THRESHOLD:
		_flag("forward_jump" if sys > projected else "rollback", sys, projected)
	var guarded: int = maxi(projected, high)
	st["high"] = guarded
	return guarded

## Calendar day of the guarded clock — the key every daily cap rolls over on.
static func today() -> String:
	return Time.get_date_string_from_unix_time(now())

## Seconds since a stored timestamp, never negative.
static func elapsed_since(unix_time: int) -> int:
	if unix_time <= 0:
		return 0
	return maxi(0, now() - unix_time)

static func anomaly_count() -> int:
	return int(_st().get("anomalies", 0))

## Test/dev hook: forget the session anchor so the next now() re-reads the system
## clock. Never called from game code.
static func reset_session_anchor() -> void:
	_base_unix = 0
	_base_ticks = 0

static func _flag(kind: String, sys: int, projected: int) -> void:
	var ms: int = Time.get_ticks_msec()
	if ms - _last_flag_ms < ANOMALY_LOG_COOLDOWN_MS:
		return
	_last_flag_ms = ms
	var st: Dictionary = _st()
	st["anomalies"] = int(st.get("anomalies", 0)) + 1
	EventBus.clock_anomaly.emit(kind)
	Analytics.log_event("clock_anomaly", {
		"kind": kind, "source": "mono_clock",
		"system": sys, "guarded": projected, "count": int(st["anomalies"]),
	})
