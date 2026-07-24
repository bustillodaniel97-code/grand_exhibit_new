extends RefCounted
## LootboxSystem — weighted card draws from lootbox tiers (SPEC §4).
## RefCounted, static funcs, no class_name; call via preload (SPEC §1 merge contract).
## Drop rates are data-driven and displayed verbatim in the UI (store policy).

const ManagerSystem := preload("res://scripts/managers/manager_system.gd")
const RARITIES: Array[String] = ["common", "rare", "epic", "legendary"]

static func managers_of_rarity(rarity: String) -> Array[String]:
	var out: Array[String] = []
	for id in DataLoader.managers.keys():
		if str(DataLoader.managers[id].get("rarity", "")) == rarity:
			out.append(id)
	out.sort()
	return out

static func weights_sum(box_id: String) -> float:
	var w: Dictionary = DataLoader.get_lootbox(box_id).get("rarity_weights", {})
	var sum := 0.0
	for r in RARITIES:
		sum += float(w.get(r, 0.0))
	return sum

static func _roll_rarity(weights: Dictionary, roll: float) -> String:
	var acc := 0.0
	for r in RARITIES:
		acc += float(weights.get(r, 0.0))
		if roll < acc:
			return r
	return RARITIES[RARITIES.size() - 1]  # float dust lands on the rarest slot

## Draw cards_total cards: rarity per rarity_weights, then uniform within that rarity.
## Applies everything to GameState and emits lootbox_opened (+ manager_obtained via add_cards).
static func open_box(box_id: String, rng: RandomNumberGenerator) -> Dictionary:
	var def: Dictionary = DataLoader.get_lootbox(box_id)
	var results: Dictionary = {"cards": [], "insight": BigNumber.zero(), "gems": 0}
	if def.is_empty():
		return results
	if rng == null:
		rng = RandomNumberGenerator.new()
		rng.randomize()
	var weights: Dictionary = def.get("rarity_weights", {})
	var tally: Dictionary = {}
	for i in range(int(def.get("cards_total", 1))):
		var rarity: String = _roll_rarity(weights, rng.randf())
		var pool: Array[String] = managers_of_rarity(rarity)
		if pool.is_empty():
			continue
		var mid: String = pool[rng.randi_range(0, pool.size() - 1)]
		tally[mid] = int(tally.get(mid, 0)) + 1
	var ids: Array = tally.keys()
	ids.sort()
	for mid in ids:
		results["cards"].append({"id": mid, "n": int(tally[mid])})
	results["insight"] = BigNumber.from_float(float(def.get("insight_bonus_m", 0.0)))
	results["gems"] = int(def.get("gems_bonus", 0))
	for entry in results["cards"]:
		ManagerSystem.add_cards(str(entry["id"]), int(entry["n"]))
	if not (results["insight"] as BigNumber).is_zero():
		GameState.add_insight(results["insight"])
	if int(results["gems"]) > 0:
		GameState.add_gems(int(results["gems"]))
	EventBus.lootbox_opened.emit(box_id, results)
	return results

## Verbatim published rates for the disclosure UI (SPEC §4: displayed verbatim).
static func rates_text(box_id: String) -> String:
	var def: Dictionary = DataLoader.get_lootbox(box_id)
	if def.is_empty():
		return ""
	var w: Dictionary = def.get("rarity_weights", {})
	var parts: Array[String] = []
	for r in RARITIES:
		var pct: float = snappedf(float(w.get(r, 0.0)) * 100.0, 0.001)
		parts.append("%s %s%%" % [r.capitalize(), str(pct)])
	return "  ·  ".join(parts)
