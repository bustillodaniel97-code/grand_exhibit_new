extends Node
## Analytics — local event log (user://analytics.log) + stdout. Swap for a real SDK later.

const LOG_PATH := "user://analytics.log"

func log_event(name: String, params: Dictionary = {}) -> void:
	var entry := {
		"t": int(Time.get_unix_time_from_system()),
		"event": name,
		"params": params,
	}
	print("[ANALYTICS] ", JSON.stringify(entry))
	var f := FileAccess.open(LOG_PATH, FileAccess.READ_WRITE)
	if f == null:
		f = FileAccess.open(LOG_PATH, FileAccess.WRITE)
	if f:
		f.seek_end()
		f.store_line(JSON.stringify(entry))
		f.close()

func session_start() -> void:
	log_event("session_start")
	retention_check()

func rv_impression(placement_id: String) -> void:
	log_event("rv_impression", {"placement": placement_id})

func iap_funnel(step: String, product_id: String = "") -> void:
	log_event("iap_funnel", {"step": step, "product": product_id})

func retention_check() -> void:
	var first: int = GameState.first_launch_unix if GameState else 0
	if first <= 0:
		return
	var days: int = int((int(Time.get_unix_time_from_system()) - first) / 86400.0)
	for marker in [1, 3, 7]:
		if days == marker:
			log_event("retention_cohort", {"cohort": "D%d" % marker})
