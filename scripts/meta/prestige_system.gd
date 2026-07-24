extends RefCounted
## PrestigeSystem — static venue-prestige logic (SPEC §6.1/§7). No class_name; preload.
## Requires all 8 milestones of the current venue + a next venue in venue_order().
## One-way move: the OLD venue keeps milestones/decor/lifetime totals as history,
## but its dept levels, quest progress and pending cash reset to fresh defaults
## (it is never revisited — documented decision, SPEC §7 "keep simple").
## CASH / GEMS / INSIGHT / MANAGERS / DECOR are NEVER touched here (SPEC §6.1).

const QuestSystem = preload("res://scripts/meta/quest_system.gd")
const MilestoneSystem = preload("res://scripts/meta/milestone_system.gd")

static func can_prestige() -> bool:
	return block_reason() == ""

static func block_reason() -> String:
	var vid: String = GameState.current_venue
	if not MilestoneSystem.all_complete(vid):
		return "Complete all 8 milestones"
	if next_venue_id() == "":
		return "Final venue reached"
	return ""

static func next_venue_id() -> String:
	var order: Array = DataLoader.venue_order()
	var idx: int = order.find(GameState.current_venue)
	if idx < 0 or idx + 1 >= order.size():
		return ""
	return str(order[idx + 1])

static func do_prestige() -> bool:
	if not can_prestige():
		return false
	var from_vid: String = GameState.current_venue
	var to_vid: String = next_venue_id()
	# 1) Reset old venue to fresh depts/progress; KEEP milestones + decor as history.
	var old_vs: Dictionary = GameState.venue_state(from_vid)
	old_vs["depts"] = _fresh_depts()
	old_vs["progress"] = 0.0
	old_vs["active_quests"] = []
	old_vs["quests_done"] = []
	# old_vs["milestones"], old_vs["decor"], earned/served totals: retained (history)
	# 2) Pending cash cleared on venue switch (SPEC §7).
	GameState.pending_cash.erase(from_vid)
	GameState.pending_cash.erase(to_vid)
	# 3) Unlock + switch venue.
	if to_vid not in GameState.venues_unlocked:
		GameState.venues_unlocked.append(to_vid)
	GameState.current_venue = to_vid
	GameState.venue_state(to_vid)  # ensure state exists
	QuestSystem.ensure_active_quests(to_vid)
	# 4) Announce. Currencies/managers/decor untouched (see header).
	EventBus.prestige_performed.emit(from_vid, to_vid)
	Analytics.log_event("prestige", {"from": from_vid, "to": to_vid,
		"milestones_kept": old_vs.get("milestones", []).size()})
	return true

## Mirrors GameState._fresh_venue_state dept defaults (core-owned; replicated here
## so meta never edits autoloads). staff = dept base_staff, speed/value = 1.
static func _fresh_depts() -> Dictionary:
	var depts: Dictionary = {}
	for dept_id in DataLoader.core.get("departments", {}).keys():
		var d: Dictionary = DataLoader.dept_def(str(dept_id))
		depts[dept_id] = {"staff": int(d.get("base_staff", 1)), "speed": 1, "value": 1}
	return depts
