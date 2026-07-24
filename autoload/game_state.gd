extends Node
## GameState — single mutable game state + currency helpers. See docs/SPEC.md §3.
## Pure data: no timers here (Economy ticks, SaveSystem persists).

var ready_flag: bool = false

var cash: BigNumber = BigNumber.zero()
var gems: int = 0
var insight: BigNumber = BigNumber.zero()
var reputation_xp: BigNumber = BigNumber.zero()
var current_venue: String = "whispering_pines"
var venues_unlocked: Array = ["whispering_pines"]
var venues_state: Dictionary = {}
var pending_cash: Dictionary = {}          # venue_id -> BigNumber
var managers_state: Dictionary = {}
var boosts: Dictionary = {"income_x2_until": 0}
var rv_state: Dictionary = {}
var daily_deals: Dictionary = {}
var expedition_state: Dictionary = {}
var event_state: Dictionary = {}
var first_launch_unix: int = 0
var last_seen_unix: int = 0
var offer_state: Dictionary = {}
var settings: Dictionary = {"music": true, "sfx": true}

func reset_to_new_game() -> void:
	cash = BigNumber.from_float(0.0)
	gems = 25  # genre-standard small starter grant; data-tunable
	insight = BigNumber.zero()
	reputation_xp = BigNumber.zero()
	venues_unlocked = [DataLoader.venue_order()[0] if DataLoader.venue_order().size() > 0 else "whispering_pines"]
	current_venue = venues_unlocked[0]
	venues_state = {}
	for vid in DataLoader.venue_order():
		venues_state[vid] = _fresh_venue_state(vid)
	pending_cash = {}
	managers_state = {}
	for mid in DataLoader.managers.keys():
		managers_state[mid] = {"cards": 0, "level": 1, "rank": 1, "assigned_to": ""}
	boosts = {"income_x2_until": 0}
	rv_state = {}
	daily_deals = {"refresh_at": 0, "force_used": 0, "day": "", "items": []}
	expedition_state = {
		"stage": 0,
		"invested": BigNumber.zero().to_save(),
		"insight_stored": BigNumber.zero().to_save(),
		"last_tick": 0,
		"boss_unlocked": false,
	}
	event_state = {}
	first_launch_unix = ClockGuard.now()
	last_seen_unix = first_launch_unix
	offer_state = {}
	settings = {"music": true, "sfx": true}

func _fresh_venue_state(venue_id: String) -> Dictionary:
	var depts: Dictionary = {}
	for dept_id in DataLoader.core.get("departments", {}).keys():
		var d: Dictionary = DataLoader.dept_def(dept_id)
		depts[dept_id] = {"staff": int(d.get("base_staff", 1)), "speed": 1, "value": 1}
	return {"depts": depts, "decor": {}, "milestones": [], "progress": 0.0, "active_quests": [],
		"served_total": BigNumber.zero().to_save(), "earned_total": BigNumber.zero().to_save()}

func venue_state(venue_id: String) -> Dictionary:
	if not venues_state.has(venue_id):
		venues_state[venue_id] = _fresh_venue_state(venue_id)
	return venues_state[venue_id]

func dept_level(venue_id: String, dept_id: String, track: String) -> int:
	return int(venue_state(venue_id).get("depts", {}).get(dept_id, {}).get(track, 1))

func set_dept_level(venue_id: String, dept_id: String, track: String, level: int) -> void:
	var vs: Dictionary = venue_state(venue_id)
	if vs.has("depts") and vs["depts"].has(dept_id):
		vs["depts"][dept_id][track] = level

func rep_level() -> int:
	var thresholds: Array = DataLoader.core.get("reputation", {}).get("thresholds_mantissa", [])
	var level: int = 1
	for i in range(thresholds.size()):
		if reputation_xp.gte(BigNumber.from_float(float(thresholds[i]))):
			level = i + 1
	return level

func rep_progress() -> float:
	var thresholds: Array = DataLoader.core.get("reputation", {}).get("thresholds_mantissa", [])
	var lvl: int = rep_level()
	if lvl >= thresholds.size():
		return 1.0
	var lo: float = float(thresholds[lvl - 1])
	var hi: float = float(thresholds[lvl])
	var xp: float = reputation_xp.to_float_approx()
	return clampf((xp - lo) / maxf(hi - lo, 1.0), 0.0, 1.0)

func feature_unlocked(feature: String) -> bool:
	var u: Dictionary = DataLoader.core.get("unlocks", {})
	match feature:
		"managers":
			return rep_level() >= int(u.get("managers_rep", 6))
		"expedition":
			return rep_level() >= int(u.get("expedition_rep", 7))
		"inspection":
			return day_index() >= int(u.get("inspection_day", 1))
		"decor":
			return rep_level() >= int(u.get("decor_rep", 2))
		"prestige":
			return venue_state(current_venue).get("milestones", []).size() >= 8
	return false

func day_index() -> int:
	if first_launch_unix <= 0:
		return 0
	return int((ClockGuard.now() - first_launch_unix) / 86400.0)

func add_cash(b: BigNumber) -> void:
	cash = cash.add(b)
	EventBus.cash_changed.emit(cash)

func spend_cash(b: BigNumber) -> bool:
	if cash.lt(b):
		return false
	cash = cash.sub(b)
	EventBus.cash_changed.emit(cash)
	return true

func add_gems(n: int) -> void:
	gems += n
	EventBus.gems_changed.emit(gems)

func spend_gems(n: int) -> bool:
	if gems < n:
		return false
	gems -= n
	EventBus.gems_changed.emit(gems)
	return true

func add_insight(b: BigNumber) -> void:
	insight = insight.add(b)
	EventBus.insight_changed.emit(insight)

func spend_insight(b: BigNumber) -> bool:
	if insight.lt(b):
		return false
	insight = insight.sub(b)
	EventBus.insight_changed.emit(insight)
	return true

func add_reputation(xp: BigNumber) -> void:
	var before: int = rep_level()
	reputation_xp = reputation_xp.add(xp)
	var after: int = rep_level()
	EventBus.reputation_changed.emit(after, reputation_xp)
	if after > before:
		var rewards: Dictionary = {}
		var cfg: Dictionary = DataLoader.core.get("reputation", {})
		var gems_per: int = int(cfg.get("level_rewards", {}).get("gems_every_level", 5))
		for lvl in range(before + 1, after + 1):
			add_gems(gems_per)
			rewards["gems"] = int(rewards.get("gems", 0)) + gems_per
			if lvl in cfg.get("level_rewards", {}).get("visitor_burst_levels", []):
				rewards["visitor_burst"] = int(cfg.get("level_rewards", {}).get("burst_visitors", 50))
		EventBus.reputation_level_up.emit(after, rewards)

func income_boost_active() -> float:
	if ClockGuard.now() < int(boosts.get("income_x2_until", 0)):
		return 2.0
	return 1.0

func to_save_dict() -> Dictionary:
	var pending_save: Dictionary = {}
	for vid in pending_cash.keys():
		pending_save[vid] = (pending_cash[vid] as BigNumber).to_save()
	return {
		"cash": cash.to_save(), "gems": gems, "insight": insight.to_save(),
		"reputation_xp": reputation_xp.to_save(), "current_venue": current_venue,
		"venues_unlocked": venues_unlocked, "venues_state": venues_state,
		"pending_cash": pending_save, "managers_state": managers_state,
		"boosts": boosts, "rv_state": rv_state, "daily_deals": daily_deals,
		"expedition_state": expedition_state, "event_state": event_state,
		"first_launch_unix": first_launch_unix, "last_seen_unix": last_seen_unix,
		"offer_state": offer_state, "settings": settings,
	}

func from_save_dict(d: Dictionary) -> void:
	reset_to_new_game()  # guarantees every field/default exists (migration tolerance)
	cash = BigNumber.from_save(d.get("cash", {}))
	gems = int(d.get("gems", gems))
	insight = BigNumber.from_save(d.get("insight", {}))
	reputation_xp = BigNumber.from_save(d.get("reputation_xp", {}))
	current_venue = str(d.get("current_venue", current_venue))
	venues_unlocked = d.get("venues_unlocked", venues_unlocked)
	var vs: Dictionary = d.get("venues_state", {})
	for vid in vs.keys():
		venues_state[vid] = vs[vid]  # overlay saved venues onto defaults
	pending_cash = {}
	for vid in d.get("pending_cash", {}).keys():
		pending_cash[vid] = BigNumber.from_save(d["pending_cash"][vid])
	var ms: Dictionary = d.get("managers_state", {})
	for mid in ms.keys():
		managers_state[mid] = ms[mid]
	boosts = d.get("boosts", boosts)
	rv_state = d.get("rv_state", rv_state)
	daily_deals = d.get("daily_deals", daily_deals)
	for k in d.get("expedition_state", {}).keys():
		expedition_state[k] = d["expedition_state"][k]
	event_state = d.get("event_state", event_state)
	first_launch_unix = int(d.get("first_launch_unix", first_launch_unix))
	last_seen_unix = int(d.get("last_seen_unix", last_seen_unix))
	offer_state = d.get("offer_state", offer_state)
	settings = d.get("settings", settings)
