extends RefCounted
## QuestSystem — static quest pool logic (SPEC §7). No class_name; preload this file.
## Keeps 3 active quests per venue in venue_state[vid].active_quests.
## Per-venue completion history lives in venue_state[vid].quests_done (added by us,
## tolerated by GameState save/load because it round-trips inside venues_state).
## POOL RECYCLING: when every pool quest is done in a venue, quests_done resets so
## the pool can be re-run (8 bars x ~11 quests > 31-quest pool; documented here).

const MilestoneSystem = preload("res://scripts/meta/milestone_system.gd")

const ACTIVE_SLOTS := 3
const DONE_KEY := "quests_done"

## Refill active_quests up to 3 from pool quests not yet done in this venue.
static func ensure_active_quests(venue_id: String) -> void:
	var vs: Dictionary = GameState.venue_state(venue_id)
	if MilestoneSystem.all_complete(venue_id):
		vs["active_quests"] = []
		vs["progress"] = 0.0
		return
	var active: Array = []
	for qid in vs.get("active_quests", []):
		if DataLoader.quests.has(str(qid)) and str(qid) not in active:
			active.append(str(qid))
	var done: Array = vs.get(DONE_KEY, [])
	while active.size() < ACTIVE_SLOTS:
		var next_id: String = _next_quest_id(done, active)
		if next_id == "":
			# Pool exhausted: recycle (see header note).
			done = []
			vs[DONE_KEY] = done
			next_id = _next_quest_id(done, active)
			if next_id == "":
				break  # empty pool; nothing to draw
		active.append(next_id)
	vs["active_quests"] = active

static func _next_quest_id(done: Array, active: Array) -> String:
	for qid in DataLoader.quests.keys():  # DataLoader preserves data file order (escalating)
		if str(qid) not in done and str(qid) not in active:
			return str(qid)
	return ""

## Current progress value for a quest def, read from GameState (BigNumber-safe).
static func current_value(venue_id: String, qdef: Dictionary) -> BigNumber:
	match str(qdef.get("type", "")):
		"upgrade_count":
			return BigNumber.from_float(float(GameState.dept_level(
				venue_id, str(qdef.get("dept", "")), str(qdef.get("track", "")))))
		"item_level":
			return BigNumber.from_float(float(GameState.item_level(
				venue_id, str(qdef.get("dept", "")), int(qdef.get("item", 0)))))
		"earn_total":
			return BigNumber.from_save(GameState.venue_state(venue_id).get("earned_total", {}))
		"serve_total":
			return BigNumber.from_save(GameState.venue_state(venue_id).get("served_total", {}))
		"buy_decor":
			return BigNumber.from_float(float(GameState.venue_state(venue_id).get("decor", {}).size()))
		"own_managers":
			var n: int = 0
			for mid in GameState.managers_state.keys():
				if int(GameState.managers_state[mid].get("cards", 0)) >= 1:
					n += 1
			return BigNumber.from_float(float(n))
	return BigNumber.zero()

static func target_value(qdef: Dictionary) -> BigNumber:
	return BigNumber.from_parts(float(qdef.get("target_m", 1.0)), int(qdef.get("target_e", 0)))

static func is_complete(venue_id: String, qdef: Dictionary) -> bool:
	return current_value(venue_id, qdef).gte(target_value(qdef))

## Check all active quests; complete those at target, fill the venue bar,
## fire milestones on bar-full, and draw replacements.
static func evaluate(venue_id: String) -> void:
	if MilestoneSystem.all_complete(venue_id):
		var complete_state: Dictionary = GameState.venue_state(venue_id)
		complete_state["active_quests"] = []
		complete_state["progress"] = 0.0
		return
	ensure_active_quests(venue_id)
	var vs: Dictionary = GameState.venue_state(venue_id)
	var completed_any: bool = false
	for qid in vs.get("active_quests", []).duplicate():
		var qdef: Dictionary = DataLoader.quests.get(str(qid), {})
		if qdef.is_empty() or not is_complete(venue_id, qdef):
			continue
		vs["active_quests"].erase(qid)
		var done: Array = vs.get(DONE_KEY, [])
		done.append(str(qid))
		vs[DONE_KEY] = done
		var venue: Dictionary = DataLoader.get_venue(venue_id)
		var pace: float = float(venue.get("quest_progress_mult", 1.0))
		vs["progress"] = float(vs.get("progress", 0.0)) \
			+ float(qdef.get("progress_reward", 0.1)) * pace
		completed_any = true
		EventBus.quest_completed.emit(str(qid))
	if completed_any:
		EventBus.venue_progress_changed.emit(venue_id, float(vs.get("progress", 0.0)))
		MilestoneSystem.try_complete_next(venue_id)  # consumes 1.0 of progress if bar full
		ensure_active_quests(venue_id)
