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
## Venues the player has graduated out of. The museum ladder is ONE-WAY and this
## is the durable record of it. Stored rather than derived from venue order,
## because order lives in venues.json: reordering or inserting a venue there
## would otherwise silently re-open a building the player already left behind.
var venues_closed: Array = []
var venues_state: Dictionary = {}
## Every decor design the player has EVER bought, in any museum.
##
## This is a historical record, not an entitlement. Buying is per venue —
## venue_state[vid].decor_bought — because a new museum is a new setting and
## stocks its own decor from scratch, the way Idle Bank Tycoon rebuilds a new
## bank from nothing. What this list is for:
##
##   · cross-venue SET bonuses, which SPEC §7 defines over the collection rather
##     than over one building;
##   · telling the player "you had this in the Aquarium" so a re-purchase reads
##     as restocking a new hall, not as being charged twice for the same thing.
var decor_owned: Array = []
var pending_cash: Dictionary = {}          # venue_id -> BigNumber
var managers_state: Dictionary = {}
var boosts: Dictionary = {"income_x2_until": 0}
var rv_state: Dictionary = {}
var daily_deals: Dictionary = {}
var expedition_state: Dictionary = {}
## Dig Site mini game (scripts/digsite/dig_system.gd): energy, sites, collection.
var dig_state: Dictionary = {}
## Achievements (autoload/platform_services.gd): unlocked ids + event counters.
var achievements_state: Dictionary = {}
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
	venues_closed = []
	venues_state = {}
	for vid in DataLoader.venue_order():
		venues_state[vid] = _fresh_venue_state(vid)
	decor_owned = []
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
	dig_state = {}
	achievements_state = {}
	first_launch_unix = ClockGuard.now()
	last_seen_unix = first_launch_unix
	offer_state = {}
	settings = {"music": true, "sfx": true}

func _fresh_venue_state(venue_id: String) -> Dictionary:
	var depts: Dictionary = {}
	for dept_id in DataLoader.core.get("departments", {}).keys():
		var d: Dictionary = DataLoader.dept_def(dept_id)
		var items: Array = []
		for _i in int(d.get("base_staff", 1)):
			items.append({"lv": 1, "pending": BigNumber.zero().to_save()})
		# "staff" stays as a mirror of items.size(): plenty of code and tests read
		# the raw dict, and a stale count is worse than a redundant one.
		depts[dept_id] = {"staff": items.size(), "items": items, "speed": 1, "value": 1}
	# decor_bought: designs PAID FOR in this museum. Separate from `decor`
	# (what is currently standing) so a piece put in storage can be stood back up
	# for free here, while the next museum still stocks its own shelves from
	# scratch. Idle Bank Tycoon does the same — a new bank is rebuilt from
	# nothing — and it is what makes each venue feel like a new setting rather
	# than a reskin of the last one.
	return {"depts": depts, "decor": {}, "decor_bought": [], "milestones": [], "progress": 0.0, "active_quests": [],
		"served_total": BigNumber.zero().to_save(), "earned_total": BigNumber.zero().to_save()}

func venue_state(venue_id: String) -> Dictionary:
	if not venues_state.has(venue_id):
		venues_state[venue_id] = _fresh_venue_state(venue_id)
	return venues_state[venue_id]

## Shut a venue for good. Its state is left exactly as the player built it — a
## closed museum is a record, not a resource, and nothing reads a closed venue's
## rates. PrestigeSystem is the only caller.
func close_venue(venue_id: String) -> void:
	if venue_id != "" and venue_id not in venues_closed:
		venues_closed.append(venue_id)

func venue_is_closed(venue_id: String) -> bool:
	return venue_id in venues_closed

## The upgrade atom is the ITEM — an individual counter, cart or desk with its
## own level and its own accumulating cash. Departments are containers of items.
## "staff" survives as a derived track: reading it counts items, writing it
## resizes the container. That keeps every caller and test that thinks in
## staff-counts working while the game moves to per-object progression.
func dept_items(venue_id: String, dept_id: String) -> Array:
	var d: Dictionary = venue_state(venue_id).get("depts", {}).get(dept_id, {})
	if not d.has("items"):
		# Legacy in-memory state (old save loaded directly in a test): synthesize
		# the container from the staff count once.
		var items: Array = []
		for _i in int(d.get("staff", 1)):
			items.append({"lv": 1, "pending": BigNumber.zero().to_save()})
		d["items"] = items
	# The raw "staff" key was the old API's storage, and plenty of tests and old
	# code still write it directly. Honour it: if the mirror disagrees with the
	# container, the mirror wins and the container is resized to match,
	# preserving the levels of items that remain. Internal paths always keep the
	# two in sync, so this only fires on legacy writes.
	var want: int = int(d.get("staff", (d["items"] as Array).size()))
	var have: Array = d["items"]
	while have.size() < want:
		have.append({"lv": 1, "pending": BigNumber.zero().to_save()})
	while have.size() > want:
		have.pop_back()
	return have

func item_level(venue_id: String, dept_id: String, index: int) -> int:
	var items: Array = dept_items(venue_id, dept_id)
	if index < 0 or index >= items.size():
		return 0
	return int(items[index].get("lv", 1))

func set_item_level(venue_id: String, dept_id: String, index: int, level: int) -> void:
	var items: Array = dept_items(venue_id, dept_id)
	if index >= 0 and index < items.size():
		items[index]["lv"] = maxi(level, 1)

func add_dept_item(venue_id: String, dept_id: String) -> void:
	var d: Dictionary = venue_state(venue_id)["depts"][dept_id]
	dept_items(venue_id, dept_id).append({"lv": 1, "pending": BigNumber.zero().to_save()})
	d["staff"] = d["items"].size()

func dept_level(venue_id: String, dept_id: String, track: String) -> int:
	if track == "staff":
		return dept_items(venue_id, dept_id).size()
	return int(venue_state(venue_id).get("depts", {}).get(dept_id, {}).get(track, 1))

func set_dept_level(venue_id: String, dept_id: String, track: String, level: int) -> void:
	var vs: Dictionary = venue_state(venue_id)
	if not (vs.has("depts") and vs["depts"].has(dept_id)):
		return
	if track == "staff":
		# Resize the item container, preserving the levels of items that remain —
		# shrinking a department must not launder its per-object progress.
		var items: Array = dept_items(venue_id, dept_id)
		while items.size() < level:
			items.append({"lv": 1, "pending": BigNumber.zero().to_save()})
		while items.size() > level:
			items.pop_back()
		vs["depts"][dept_id]["staff"] = items.size()
		return
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
		"dig":
			return rep_level() >= int(u.get("dig_rep", 2))
		"inspection":
			return day_index() >= int(u.get("inspection_day", 1))
		"decor":
			return rep_level() >= int(u.get("decor_rep", 2))
		# The milestone chain is the one gate on opening the next museum. Kept in
		# sync with PrestigeSystem.milestones_required by reading the same key;
		# an autoload must not preload a meta script (SPEC §1 branch isolation).
		"prestige", "graduation":
			var need: int = int(DataLoader.core.get("venue_progression", {})
				.get("milestones_required", 8))
			var authored: int = (DataLoader.milestones.get(current_venue, []) as Array).size()
			if authored > 0:
				need = mini(need, authored)
			return venue_state(current_venue).get("milestones", []).size() >= need
	return false

func day_index() -> int:
	if first_launch_unix <= 0:
		return 0
	return maxi(0, int((ClockGuard.now() - first_launch_unix) / 86400.0))

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
		"venues_unlocked": venues_unlocked, "venues_closed": venues_closed,
		"venues_state": venues_state, "decor_owned": decor_owned,
		"pending_cash": pending_save, "managers_state": managers_state,
		"boosts": boosts, "rv_state": rv_state, "daily_deals": daily_deals,
		"expedition_state": expedition_state, "event_state": event_state,
		"dig_state": dig_state, "achievements_state": achievements_state,
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
	# A pre-v3 save has no venues_closed; SaveSystem.migrate derives one. Falling
	# back to [] here as well keeps a hand-edited or partial dict loadable.
	venues_closed = d.get("venues_closed", [])
	var vs: Dictionary = d.get("venues_state", {})
	for vid in vs.keys():
		if typeof(vs[vid]) != TYPE_DICTIONARY:
			continue
		# Overlay saved venue onto fresh defaults so partial/migrated saves
		# still have every key (SPEC §10: from_save_dict accepts partial dicts).
		var merged: Dictionary = _fresh_venue_state(vid)
		var saved: Dictionary = vs[vid]
		for k in saved.keys():
			merged[k] = saved[k]
		if saved.has("depts") and typeof(saved["depts"]) == TYPE_DICTIONARY:
			for dept_id in merged["depts"].keys():
				var saved_dept: Dictionary = saved["depts"].get(dept_id, {})
				for tk in saved_dept.keys():
					merged["depts"][dept_id][tk] = saved_dept[tk]
		venues_state[vid] = merged
	# A pre-v5 save records ownership only by placement. SaveSystem.migrate
	# derives the design list; deriving here too keeps a hand-edited or partial
	# dict loadable without silently confiscating the player's collection.
	decor_owned = (d.get("decor_owned", []) as Array).duplicate()
	if decor_owned.is_empty():
		decor_owned = _derive_decor_owned()
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
	dig_state = (d.get("dig_state", {}) as Dictionary).duplicate(true)
	achievements_state = (d.get("achievements_state", {}) as Dictionary).duplicate(true)
	first_launch_unix = int(d.get("first_launch_unix", first_launch_unix))
	last_seen_unix = int(d.get("last_seen_unix", last_seen_unix))
	offer_state = d.get("offer_state", offer_state)
	settings = d.get("settings", settings)

## Every design standing on any floor was, by definition, paid for. Used to
## reconstruct decor_owned for saves written before ownership went global.
func _derive_decor_owned() -> Array:
	var out: Array = []
	for vid in venues_state.keys():
		if typeof(venues_state[vid]) != TYPE_DICTIONARY:
			continue
		for did in (venues_state[vid] as Dictionary).get("decor", {}).values():
			if str(did) != "" and str(did) not in out:
				out.append(str(did))
	return out

## True when the player has unlocked this design anywhere, ever.
func owns_decor_design(decor_id: String) -> bool:
	return decor_id in decor_owned

func unlock_decor_design(decor_id: String) -> void:
	if decor_id != "" and decor_id not in decor_owned:
		decor_owned.append(decor_id)
