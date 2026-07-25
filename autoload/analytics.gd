extends Node
## Analytics — local event log (user://analytics.log) + stdout. Swap for a real SDK later.
##
## Three things the v1 logger could not do, all of which this one does:
##  1. Measure the ad business. A rewarded video is a funnel — requested, filled or
##     no-filled, started, completed, rewarded — and v1 logged one event, at reward
##     time, named "rv_impression". Fill rate, failure rate and per-placement drop-off
##     were all unmeasurable. Use ad_event()/rv_* below; every step has one name.
##  2. Bound its own disk use. v1 opened, seeked, wrote and closed the file on every
##     single event, forever. This one buffers and rotates at MAX_LOG_BYTES.
##  3. Respect consent. Nothing is written to disk until Consent has resolved, and a
##     denial drops events entirely rather than queueing them (see set_consent).
##
## Event-name contract (one name per funnel step — never log the same step twice
## under two names, which is what made the v1 IAP funnel report a phantom 50% drop):
##   session_start / retention_cohort
##   ad_requested / ad_filled / ad_no_fill / ad_timeout / ad_load_failed
##   rv_started / rv_completed / rv_rewarded / rv_failed / rv_blocked / rv_rejected
##   interstitial_shown / interstitial_suppressed
##   iap_funnel{step: initiate|complete|failed|limit_blocked|inflight_blocked|restore}
##   store_open / product_view / offer_shown / offer_bought / offer_dismissed
##   clock_anomaly / save_corrupt / save_migrated

const LOG_PATH := "user://analytics.log"
const LOG_PREV := "user://analytics.log.1"
## One rotation, 256 KB each: enough history to debug a session, small enough that
## a phone never carries more than half a megabyte of telemetry it may never upload.
const MAX_LOG_BYTES := 256 * 1024
const FLUSH_EVERY_EVENTS := 12
const FLUSH_EVERY_SECONDS := 5.0

## Consent gate. Unknown means "not asked yet": we still print to stdout for dev
## builds but nothing touches disk, because a persistent per-install behavioural
## log written before the player has been asked is exactly what a Play review
## flags. Consent.apply_to_analytics() flips this at boot.
var _consent_granted: bool = false
var _consent_resolved: bool = false

var _buffer: PackedStringArray = PackedStringArray()
var _since_flush: float = 0.0
var _bytes_written: int = 0

func _ready() -> void:
	_bytes_written = _current_log_size()

func _process(delta: float) -> void:
	if _buffer.is_empty():
		return
	_since_flush += delta
	if _since_flush >= FLUSH_EVERY_SECONDS:
		flush()

func _exit_tree() -> void:
	flush()

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_APPLICATION_PAUSED:
		flush()

# ------------------------------------------------------------------- consent

## Called by scripts/monetization/consent.gd once the privacy state is known.
func set_consent(granted: bool) -> void:
	_consent_resolved = true
	if _consent_granted == granted:
		return
	_consent_granted = granted
	if not granted:
		_buffer.clear()  # denial drops the backlog; it is not held for later upload

func consent_granted() -> bool:
	return _consent_granted

# --------------------------------------------------------------------- write

func log_event(name: String, params: Dictionary = {}) -> void:
	var entry := {
		"t": int(Time.get_unix_time_from_system()),
		"event": name,
		"params": params,
	}
	var line := JSON.stringify(entry)
	print("[ANALYTICS] ", line)
	if not _consent_granted:
		return
	_buffer.append(line)
	if _buffer.size() >= FLUSH_EVERY_EVENTS:
		flush()

func flush() -> void:
	if _buffer.is_empty():
		return
	var pending := _buffer
	_buffer = PackedStringArray()
	_since_flush = 0.0
	if not _consent_granted:
		return
	_rotate_if_needed()
	var f := FileAccess.open(LOG_PATH, FileAccess.READ_WRITE)
	if f == null:
		f = FileAccess.open(LOG_PATH, FileAccess.WRITE)
	if f == null:
		return
	f.seek_end()
	for line in pending:
		f.store_line(line)
		_bytes_written += line.length() + 1
	f.close()

func _current_log_size() -> int:
	if not FileAccess.file_exists(LOG_PATH):
		return 0
	var f := FileAccess.open(LOG_PATH, FileAccess.READ)
	if f == null:
		return 0
	var n: int = int(f.get_length())
	f.close()
	return n

func _rotate_if_needed() -> void:
	if _bytes_written < MAX_LOG_BYTES:
		return
	var dir := DirAccess.open("user://")
	if dir == null:
		return
	if dir.file_exists(LOG_PREV.get_file()):
		dir.remove(LOG_PREV.get_file())
	dir.rename(LOG_PATH.get_file(), LOG_PREV.get_file())
	_bytes_written = 0

# -------------------------------------------------------------------- events

func session_start() -> void:
	log_event("session_start")
	retention_check()

## Rewarded/interstitial lifecycle. `reason` carries no_fill / timeout / busy /
## playback_failed / verification_failed so failure can be attributed, not just counted.
func ad_event(name: String, placement_id: String, extra: Dictionary = {}) -> void:
	var params: Dictionary = {"placement": placement_id}
	params.merge(extra)
	log_event(name, params)

func rv_outcome(placement_id: String, success: bool, reason: String = "") -> void:
	if success:
		ad_event("rv_completed", placement_id)
	else:
		ad_event("rv_failed", placement_id, {"reason": reason})

## Kept from v1 so the manager / expedition / welcome-back screens (other tracks)
## keep compiling. It means "the reward landed", which is the last funnel step.
func rv_impression(placement_id: String) -> void:
	ad_event("rv_rewarded", placement_id)

func iap_funnel(step: String, product_id: String = "", extra: Dictionary = {}) -> void:
	var params: Dictionary = {"step": step, "product": product_id}
	params.merge(extra)
	log_event("iap_funnel", params)

func store_open(source: String = "nav") -> void:
	log_event("store_open", {"source": source})

func product_view(product_id: String, section: String) -> void:
	log_event("product_view", {"product": product_id, "section": section})

func retention_check() -> void:
	var first: int = GameState.first_launch_unix if GameState else 0
	if first <= 0:
		return
	var days: int = int((int(Time.get_unix_time_from_system()) - first) / 86400.0)
	for marker in [1, 3, 7]:
		if days == marker:
			log_event("retention_cohort", {"cohort": "D%d" % marker})
