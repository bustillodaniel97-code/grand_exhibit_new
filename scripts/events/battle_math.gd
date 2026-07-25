extends RefCounted
## Static combat math for event battles (SPEC §6). No state; call via preload.
##
## BOSS HP IS A MULTIPLE OF WHAT THE TEAM CAN DEAL, not an absolute number.
## The previous model set HP from the player's ENTIRE OWNED ROSTER while damage
## came only from the three managers actually brought, so every manager collected
## — the event's own reward — made the event strictly harder: 14 Lv5 managers
## turned stage 1 from 120 HP into 959 with damage unchanged, and no level, rank
## or roster configuration could clear the Expedition boss. HP is now derived from
## `expected_damage()` for the SELECTED team, times a per-stage `pressure` from
## events.json, so difficulty is a dial in data and progression cannot invert.

## Damage one point of team power deals per move, measured by the solver harness
## in tests/events/test_battle_balance.gd over 300 seeded battles. The reference
## player takes the best audit-focus move 70% of the time and a random legal move
## otherwise — an attentive human, not a solver. Measured against that reference:
## perfect audit play is worth +14% on top, and ignoring the audit entirely costs
## -32%, so reading the board is the biggest lever the player has.
##
## Damage is linear in team power (charge accrual does not depend on how hard a
## manager hits) and linear in the move budget, and it does NOT depend on how many
## managers are brought: fewer managers put fewer colours on the board but hand
## each of them a larger share of every clear. That is why HP must key off the
## SELECTED team's power and nothing else.
const DAMAGE_PER_POWER_PER_MOVE := 0.655

## Team power that `pressure` is quoted against. A stage at pressure 1.0 is a
## coin flip for a team of exactly this power; stronger teams get a slowly
## widening edge via `hp_vs_power` below 1.0 (see stage_boss_hp).
const REFERENCE_POWER := 100.0

## Hard ceiling: no boss in this game may ever be quoted above this share of the
## fighting team's own damage budget, whatever the stage pressure, the power
## residual or the expedition cycle count says. This is the law that makes
## "unwinnable" structurally impossible rather than a tuning accident — the
## previous build shipped an Expedition boss at a damage/HP ratio of 0.098 that
## no level, rank or roster could clear.
const MAX_BUDGET_SHARE := 0.95

## attack = battle_power * (1 + 0.12*(level-1)) * rank_mults[rank-1]
static func manager_attack(def: Dictionary, state: Dictionary) -> float:
	var base: float = float(def.get("battle_power", 10.0))
	var level: int = maxi(int(state.get("level", 1)), 1)
	var rank: int = clampi(int(state.get("rank", 1)), 1, 4)
	var rank_mults: Array = def.get("rank_mults", [1.0, 1.5, 2.25, 3.5])
	var rm: float = float(rank_mults[mini(rank, rank_mults.size()) - 1])
	return base * (1.0 + 0.12 * float(level - 1)) * rm


## defs_states: Array of {"def": Dictionary, "state": Dictionary}.
static func team_power(defs_states: Array) -> float:
	var total := 0.0
	for ds in defs_states:
		total += manager_attack(
			ds.get("def", {}) if ds is Dictionary else {},
			ds.get("state", {}) if ds is Dictionary else {})
	return total


## Damage a team of `team_power` is expected to deal across `moves` moves.
## This is the unit every boss HP in the game is quoted in.
static func expected_damage(team_power_selected: float, moves: int) -> float:
	return maxf(team_power_selected, 0.0) * DAMAGE_PER_POWER_PER_MOVE \
		* float(maxi(moves, 0))


## Moves budget for a stage, defaulting to the event-wide fallback.
static func stage_moves(event_def: Dictionary, stage_index: int) -> int:
	var stages: Array = event_def.get("stages", [])
	if stage_index < 0 or stage_index >= stages.size():
		return 20
	return maxi(int((stages[stage_index] as Dictionary).get("moves", 20)), 1)


## hp = expected_damage(selected team, stage moves) * stage.pressure
##      * (team_power / REFERENCE_POWER)^(hp_vs_power - 1)
##
## The exponent is applied as a RESIDUAL: at hp_vs_power = 1.0 difficulty is flat
## at every team power, and at 0.85 a team twice as strong faces a boss only
## 2^0.85 times as tough, so growth is rewarded without ever making an under-
## powered team's fight unwinnable. `team_power_selected` is the power of the
## managers actually being sent in — never the owned roster.
static func stage_boss_hp(event_def: Dictionary, stage_index: int,
		team_power_selected: float) -> float:
	var scaling: Dictionary = event_def.get("scaling", {})
	var stages: Array = event_def.get("stages", [])
	var stage: Dictionary = {}
	if stage_index >= 0 and stage_index < stages.size():
		stage = stages[stage_index]
	var pressure: float = float(stage.get("pressure",
		float(scaling.get("base_pressure", 0.75))))
	return _boss_hp(team_power_selected, stage_moves(event_def, stage_index),
		pressure, float(scaling.get("hp_vs_power", 0.85)),
		float(scaling.get("min_hp", 30.0)))


## Expedition boss: same budget model, escalating per cleared cycle.
## The escalation is CAPPED. Uncapped compounding always wins in the end — at the
## old +25%/cycle even a fully maxed Lv50 rank-4 team dropped to a 35% clear by
## cycle 4 — which turns an evergreen mode into a countdown to a wall.
static func expedition_boss_hp(boss_def: Dictionary, team_power_selected: float,
		cycle: int) -> float:
	var growth: float = maxf(float(boss_def.get("cycle_hp_growth", 1.15)), 1.0)
	var cap: float = maxf(float(boss_def.get("cycle_hp_cap", 4.0)), 1.0)
	var escalation: float = minf(pow(growth, float(maxi(cycle, 0))), cap)
	var moves: int = maxi(int(boss_def.get("moves", 24)), 1)
	var hp: float = _boss_hp(team_power_selected, moves,
		float(boss_def.get("pressure", 1.0)),
		float(boss_def.get("hp_vs_power", 0.85)),
		float(boss_def.get("min_hp", 30.0))) * escalation
	# MAX_BUDGET_SHARE applies AFTER the escalation too: the Guardian gets harder
	# every cycle until it is a hard fight and then holds there. It never becomes
	# a fight the player cannot win by playing well.
	return minf(hp, maxf(expected_damage(team_power_selected, moves) * MAX_BUDGET_SHARE,
		float(boss_def.get("min_hp", 30.0))))


static func _boss_hp(team_power_selected: float, moves: int, pressure: float,
		hp_vs_power: float, min_hp: float) -> float:
	var tp: float = maxf(team_power_selected, 0.0)
	var residual := 1.0
	if tp > 0.0:
		residual = pow(tp / REFERENCE_POWER, hp_vs_power - 1.0)
	var budget: float = expected_damage(tp, moves)
	return maxf(minf(budget * pressure * residual, budget * MAX_BUDGET_SHARE), min_hp)


## Draws cards_total cards from a lootbox definition: roll rarity by weights,
## then a uniform manager of that rarity from the managers dict (id -> def).
## Falls back to the full roster for rarities with no published manager yet.
## Returns {manager_id: cards}. Deterministic given a seeded rng.
static func draw_cards(box_def: Dictionary, managers: Dictionary, rng: RandomNumberGenerator) -> Dictionary:
	var weights: Dictionary = box_def.get("rarity_weights", {"common": 1.0})
	var total_cards: int = int(box_def.get("cards_total", 1))
	var by_rarity := {}
	for mid in managers.keys():
		var r: String = str(managers[mid].get("rarity", "common"))
		if not by_rarity.has(r):
			by_rarity[r] = []
		by_rarity[r].append(str(mid))
	var out := {}
	for i in total_cards:
		var rarity: String = _roll_rarity(weights, rng)
		var pool: Array = by_rarity.get(rarity, []).duplicate()
		if pool.is_empty():
			for r in by_rarity.keys():
				pool.append_array(by_rarity[r])
		if pool.is_empty():
			continue
		var mid: String = pool[rng.randi_range(0, pool.size() - 1)]
		out[mid] = int(out.get(mid, 0)) + 1
	return out


static func _roll_rarity(weights: Dictionary, rng: RandomNumberGenerator) -> String:
	var sum := 0.0
	for k in weights.keys():
		sum += float(weights[k])
	if sum <= 0.0:
		return "common"
	var roll: float = rng.randf() * sum
	var last := "common"
	for k in weights.keys():
		last = str(k)
		roll -= float(weights[k])
		if roll <= 0.0:
			return str(k)
	return last
