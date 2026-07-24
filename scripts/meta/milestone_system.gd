extends RefCounted
## MilestoneSystem — static venue milestone chain logic (SPEC §7). No class_name; preload.
## Bar full (progress >= 1.0) -> consume 1.0, complete next milestone in
## DataLoader.milestones[venue_id] order, grant gems + box card draws.
## All 8 done -> EventBus.prestige_available.
##
## BOX CARD DRAW HELPER (_draw_box_cards): milestone rewards name a lootbox id
## (data key reward.box). We draw N = floor(box.cards_total / 2) cards, one rarity
## roll per card against box.rarity_weights, then a uniform random manager of that
## rarity from DataLoader.managers. Cards are credited straight into
## GameState.managers_state[mid].cards. Kept local (not the managers-branch lootbox
## opener) so meta never preloads another branch's scripts (SPEC §1).

const BAR_FULL := 1.0
const BAR_EPSILON := 0.000001  # float-sum tolerance for 0.07-style rewards

static func try_complete_next(venue_id: String) -> void:
	var vs: Dictionary = GameState.venue_state(venue_id)
	var progress: float = float(vs.get("progress", 0.0))
	if progress + BAR_EPSILON < BAR_FULL:
		return
	var defs: Array = DataLoader.milestones.get(venue_id, [])
	var done: Array = vs.get("milestones", [])
	if done.size() >= defs.size():
		return  # chain exhausted; prestige handles the rest
	vs["progress"] = maxf(progress - BAR_FULL, 0.0)
	var ms: Dictionary = defs[done.size()]
	done.append(str(ms.get("id", "")))
	vs["milestones"] = done
	_grant_reward(ms)
	EventBus.milestone_completed.emit(venue_id, str(ms.get("id", "")))
	EventBus.venue_progress_changed.emit(venue_id, float(vs.get("progress", 0.0)))
	if done.size() >= defs.size():
		EventBus.prestige_available.emit(venue_id)

static func _grant_reward(ms: Dictionary) -> void:
	var reward: Dictionary = ms.get("reward", {})
	var gems: int = int(reward.get("gems", 0))
	if gems > 0:
		GameState.add_gems(gems)
	var box_id: String = str(reward.get("box", ""))
	if box_id != "" and DataLoader.lootboxes.has(box_id):
		var gained: Dictionary = _draw_box_cards(box_id)
		for mid in gained.keys():
			var st: Dictionary = GameState.managers_state.get(mid, {"cards": 0, "level": 1, "rank": 1, "assigned_to": ""})
			st["cards"] = int(st.get("cards", 0)) + int(gained[mid])
			GameState.managers_state[mid] = st
			EventBus.manager_obtained.emit(str(mid), int(gained[mid]))

## Draw floor(cards_total/2) cards from a lootbox def. Returns {manager_id: count}.
static func _draw_box_cards(box_id: String) -> Dictionary:
	var box: Dictionary = DataLoader.get_lootbox(box_id)
	var n: int = maxi(int(box.get("cards_total", 2)) / 2, 1)
	var weights: Dictionary = box.get("rarity_weights", {"common": 1.0})
	var gained: Dictionary = {}
	for i in range(n):
		var rarity: String = _roll_rarity(weights)
		var mid: String = _random_manager_of_rarity(rarity)
		if mid != "":
			gained[mid] = int(gained.get(mid, 0)) + 1
	return gained

static func _roll_rarity(weights: Dictionary) -> String:
	var total: float = 0.0
	for r in weights.keys():
		total += float(weights[r])
	if total <= 0.0:
		return "common"
	var roll: float = randf() * total
	for r in weights.keys():
		roll -= float(weights[r])
		if roll <= 0.0:
			return str(r)
	return str(weights.keys()[0])

static func _random_manager_of_rarity(rarity: String) -> String:
	var pool: Array = []
	for mid in DataLoader.managers.keys():
		if str(DataLoader.managers[mid].get("rarity", "")) == rarity:
			pool.append(str(mid))
	if pool.is_empty():  # rarity missing from roster: fall back to any manager
		pool = DataLoader.managers.keys()
	if pool.is_empty():
		return ""
	return str(pool[randi() % pool.size()])

static func next_milestone(venue_id: String) -> Dictionary:
	var defs: Array = DataLoader.milestones.get(venue_id, [])
	var done: Array = GameState.venue_state(venue_id).get("milestones", [])
	if done.size() < defs.size():
		return defs[done.size()]
	return {}

static func all_complete(venue_id: String) -> bool:
	var defs: Array = DataLoader.milestones.get(venue_id, [])
	return defs.size() > 0 and GameState.venue_state(venue_id).get("milestones", []).size() >= defs.size()
