extends RefCounted
## ManagerSystem — static API for the manager collection layer (SPEC §4-5).
## RefCounted, static funcs, no class_name; call via preload (SPEC §1 merge contract).
## Cards are both the collection unlock and the duplicate currency: owned = cards >= 1,
## and any duplicate spend (rank-up, exchange) must leave an owned manager with >= 1 card.

const DEPTS: Array[String] = ["promotions", "ticket", "archive", "gallery"]
const ManagerCurve := preload("res://scripts/managers/manager_curve.gd")
const MAX_RANK: int = ManagerCurve.MAX_RANK
const DATA_PATH := "res://data/managers.json"

static var _exchange_ratio_cache: int = -1

## "exchange_ratio" lives at the root of managers.json (DataLoader only indexes the array).
static func exchange_ratio() -> int:
	if _exchange_ratio_cache > 0:
		return _exchange_ratio_cache
	var ratio := 5
	if FileAccess.file_exists(DATA_PATH):
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(DATA_PATH))
		if typeof(parsed) == TYPE_DICTIONARY:
			ratio = int(parsed.get("exchange_ratio", 5))
	_exchange_ratio_cache = maxi(ratio, 1)
	return _exchange_ratio_cache

static func manager_def(id: String) -> Dictionary:
	return DataLoader.get_manager_def(id)

static func state(id: String) -> Dictionary:
	if not GameState.managers_state.has(id):
		GameState.managers_state[id] = {"cards": 0, "level": 1, "rank": 1, "assigned_to": ""}
	return GameState.managers_state[id]

static func cards(id: String) -> int:
	return int(state(id).get("cards", 0))

static func level(id: String) -> int:
	return maxi(int(state(id).get("level", 1)), 1)

static func rank(id: String) -> int:
	return clampi(int(state(id).get("rank", 1)), 1, MAX_RANK)

static func assigned_to(id: String) -> String:
	return str(state(id).get("assigned_to", ""))

static func owned(id: String) -> bool:
	return cards(id) >= 1

## Grant n cards (collection unlock + duplicates). Emits manager_obtained.
static func add_cards(id: String, n: int) -> void:
	if n <= 0 or manager_def(id).is_empty():
		return
	var st: Dictionary = state(id)
	st["cards"] = int(st.get("cards", 0)) + n
	EventBus.manager_obtained.emit(id, n)

## Insight cost to go from current level to level+1: base * growth^(level-1) (SPEC §5).
static func level_up_cost(id: String) -> BigNumber:
	var def: Dictionary = manager_def(id)
	var base: float = float(def.get("insight_cost_base", 10.0))
	var growth: float = float(def.get("insight_cost_growth", 1.12))
	return BigNumber.from_float(base * pow(growth, float(level(id) - 1)))

static func level_cap(id: String) -> int:
	return ManagerCurve.level_cap(rank(id))

static func can_level_up(id: String) -> bool:
	if not owned(id):
		return false
	if level(id) >= level_cap(id):
		return false
	return GameState.insight.gte(level_up_cost(id))

static func level_up(id: String) -> bool:
	var def: Dictionary = manager_def(id)
	if def.is_empty() or not owned(id):
		return false
	var lvl: int = level(id)
	if lvl >= level_cap(id):
		return false
	if not GameState.spend_insight(level_up_cost(id)):
		return false
	state(id)["level"] = lvl + 1
	EventBus.manager_leveled.emit(id, lvl + 1)
	return true

## Duplicate cards required for the next rank (dup_costs[rank-1]); 0 when max rank.
static func rank_up_cost(id: String) -> int:
	var r: int = rank(id)
	if r >= MAX_RANK:
		return 0
	return ManagerCurve.rank_cost(r)

static func can_rank_up(id: String) -> bool:
	if not owned(id):
		return false
	var cost: int = rank_up_cost(id)
	if cost <= 0:
		return false
	return cards(id) - cost >= 1  # keep-1 rule

static func rank_up(id: String) -> bool:
	if not can_rank_up(id):
		return false
	var st: Dictionary = state(id)
	var r: int = rank(id)
	st["cards"] = int(st.get("cards", 0)) - rank_up_cost(id)
	st["rank"] = r + 1
	EventBus.manager_ranked_up.emit(id, r + 1)
	return true

## Assignment posts open with Reputation. This mirrors the reference loop where
## manager slots are a progression reward rather than a forever-one-per-room rule.
static func assignment_slots(_dept_id: String) -> int:
	var thresholds: Array = DataLoader.core.get("manager_assignment_slots", [6, 9, 12])
	var slots: int = 0
	for rep in thresholds:
		if GameState.rep_level() >= int(rep):
			slots += 1
	return maxi(slots, 1)

static func assigned_ids(dept_id: String) -> Array[String]:
	var out: Array[String] = []
	for mid in GameState.managers_state.keys():
		if str(GameState.managers_state[mid].get("assigned_to", "")) == dept_id:
			out.append(str(mid))
	# Stable ordering keeps multi-post rooms, replacement copy, and floor auras
	# attached to the same managers across save loads.
	out.sort()
	return out

static func assign(id: String, dept_id: String) -> bool:
	var def: Dictionary = manager_def(id)
	if def.is_empty() or not owned(id):
		return false
	if dept_id not in DEPTS:
		return false
	if str(def.get("specialty", "")) != dept_id:
		return false
	var st: Dictionary = state(id)
	if str(st.get("assigned_to", "")) == dept_id:
		return true
	if assigned_ids(dept_id).size() >= assignment_slots(dept_id):
		return false
	st["assigned_to"] = dept_id
	EventBus.manager_assigned.emit(id, dept_id)
	return true

static func unassign(id: String) -> bool:
	var st: Dictionary = state(id)
	if str(st.get("assigned_to", "")) == "":
		return false
	st["assigned_to"] = ""
	EventBus.manager_assigned.emit(id, "")
	return true

## Swap one occupied post without exposing an intermediate empty team to Economy,
## floor auras, or UI listeners. Every invariant is checked before either state is
## touched; stale modal choices therefore leave the current team intact.
static func replace_assignment(outgoing_id: String, incoming_id: String,
		dept_id: String) -> bool:
	if outgoing_id == incoming_id or dept_id not in DEPTS:
		return false
	var outgoing_def: Dictionary = manager_def(outgoing_id)
	var incoming_def: Dictionary = manager_def(incoming_id)
	if outgoing_def.is_empty() or incoming_def.is_empty():
		return false
	if not owned(outgoing_id) or not owned(incoming_id):
		return false
	if str(outgoing_def.get("specialty", "")) != dept_id \
			or str(incoming_def.get("specialty", "")) != dept_id:
		return false
	var outgoing_state: Dictionary = state(outgoing_id)
	var incoming_state: Dictionary = state(incoming_id)
	if str(outgoing_state.get("assigned_to", "")) != dept_id \
			or str(incoming_state.get("assigned_to", "")) != "":
		return false
	var holders := assigned_ids(dept_id)
	if outgoing_id not in holders or holders.size() < assignment_slots(dept_id):
		return false
	# Commit the complete team before notifying either listener.
	outgoing_state["assigned_to"] = ""
	incoming_state["assigned_to"] = dept_id
	EventBus.manager_assigned.emit(outgoing_id, "")
	EventBus.manager_assigned.emit(incoming_id, dept_id)
	return true

## exchange_ratio cards of from_id -> 1 card of to_id. Same rarity required.
## Keep-1 rule: from_id must keep >= 1 card after the trade.
static func can_exchange(from_id: String, to_id: String) -> bool:
	if from_id == to_id:
		return false
	var fd: Dictionary = manager_def(from_id)
	var td: Dictionary = manager_def(to_id)
	if fd.is_empty() or td.is_empty():
		return false
	if str(fd.get("rarity", "")) != str(td.get("rarity", "")):
		return false
	return cards(from_id) - exchange_ratio() >= 1

static func exchange(from_id: String, to_id: String) -> bool:
	if not can_exchange(from_id, to_id):
		return false
	var ratio: int = exchange_ratio()
	var st: Dictionary = state(from_id)
	st["cards"] = int(st.get("cards", 0)) - ratio
	add_cards(to_id, 1)
	EventBus.manager_exchanged.emit(from_id, to_id, ratio, 1)
	return true

## Economic stat shown as Productivity and consumed by Economy.
static func productivity_multiplier(def: Dictionary, st: Dictionary) -> float:
	return ManagerCurve.productivity(def, st)

## Audit stat used by both manager-facing UI and match-3 team strength.
static func audit_efficiency(def: Dictionary, st: Dictionary) -> float:
	return ManagerCurve.audit_efficiency(def, st)

## Compatibility name used by the battle layer.
static func battle_attack(def: Dictionary, st: Dictionary) -> float:
	return audit_efficiency(def, st)
