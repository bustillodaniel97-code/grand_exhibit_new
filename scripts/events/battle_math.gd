extends RefCounted
## Static combat math for event battles (SPEC §6). No state; call via preload.

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


## boss_hp_i = base_hp * (i+1)^1.6 * max(1.0, (team_power_at_open/100)^hp_vs_power);
## the LAST stage is additionally multiplied by final_stage_power_need.
static func stage_boss_hp(event_def: Dictionary, stage_index: int, team_power_at_open: float) -> float:
	var scaling: Dictionary = event_def.get("scaling", {})
	var base_hp: float = float(scaling.get("base_hp", 500.0))
	var power_exp: float = float(scaling.get("hp_vs_power", 0.9))
	var stages: Array = event_def.get("stages", [])
	var tp: float = maxf(team_power_at_open, 0.0)
	var hp: float = base_hp * pow(float(stage_index + 1), 1.6) \
		* maxf(1.0, pow(tp / 100.0, power_exp))
	if stage_index == stages.size() - 1 and stages.size() > 0:
		hp *= float(scaling.get("final_stage_power_need", 1.5))
	return hp


## Expedition boss: config boss_hp scaled by team power and +25% per cleared cycle.
static func expedition_boss_hp(boss_def: Dictionary, team_power: float, cycle: int) -> float:
	var tp: float = maxf(team_power, 0.0)
	return float(boss_def.get("boss_hp", 1000.0)) \
		* maxf(1.0, pow(tp / 100.0, 0.9)) * pow(1.25, maxi(cycle, 0))


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
