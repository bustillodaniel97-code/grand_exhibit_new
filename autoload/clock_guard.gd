extends Node
## ClockGuard — validated time for offline earnings. See docs/SPEC.md §3.

var _highest_seen_unix: int = 0

func now() -> int:
	return int(Time.get_unix_time_from_system())

## Clamp elapsed seconds into [0, cap_seconds]. Device-clock rollback -> 0 + anomaly.
func validate_elapsed(from_unix: int, to_unix: int, cap_seconds: int) -> int:
	if from_unix <= 0 or to_unix <= 0:
		return 0
	if to_unix < from_unix - 60:  # 60s tolerance for tz/ntp jitter
		EventBus.clock_anomaly.emit("rollback")
		Analytics.log_event("clock_anomaly", {"kind": "rollback", "from": from_unix, "to": to_unix})
		return 0
	var elapsed: int = to_unix - from_unix
	if elapsed < 0:
		return 0
	return mini(elapsed, cap_seconds)

func note_seen(unix_time: int) -> void:
	_highest_seen_unix = maxi(_highest_seen_unix, unix_time)
