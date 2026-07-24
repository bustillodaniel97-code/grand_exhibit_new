extends SceneTree
## tests/managers/test_lootbox.gd — lootbox weights + seeded distribution (SPEC §4, §12).
## Run: godot --headless --path . -s tests/managers/test_lootbox.gd ; exit 0 = pass.

## Bootstrap note: see test_managers.gd — autoloads are live root children by the
## time run() executes; fetch via root.get_node(), then load() system scripts.
const LS_PATH := "res://scripts/managers/lootbox_system.gd"

var _failures := 0

func _init() -> void:
	call_deferred("run")

func check(cond: bool, msg: String) -> void:
	if cond:
		print("PASS  ", msg)
	else:
		_failures += 1
		printerr("FAIL  ", msg)

func run() -> void:
	var gs: Node = root.get_node("GameState")
	var dl: Node = root.get_node("DataLoader")
	var LootboxSystem: GDScript = load(LS_PATH)
	gs.reset_to_new_game()

	# --- published weights sum to exactly 1.0 for every tier ----------------------
	var box_ids: Array = dl.lootboxes.keys()
	check(box_ids.size() == 3, "3 seeded lootbox tiers")
	for box_id in box_ids:
		var sum: float = LootboxSystem.weights_sum(box_id)
		check(absf(sum - 1.0) < 0.000001, "%s rarity weights sum to 1.0 (got %f)" % [box_id, sum])
		check(LootboxSystem.rates_text(box_id) != "", "%s has published rates text" % box_id)

	# --- result shape + application to GameState ------------------------------------
	var rng := RandomNumberGenerator.new()
	rng.seed = 424242
	var opened_signal := {"fired": false}
	root.get_node("EventBus").lootbox_opened.connect(
		func(box_id: String, _res: Dictionary) -> void:
			opened_signal["fired"] = box_id == "specialist_case")
	var gems_before: int = gs.gems
	var res: Dictionary = LootboxSystem.open_box("specialist_case", rng)
	check(res.has("cards") and res.has("insight") and res.has("gems"), "open_box returns {cards, insight, gems}")
	var drawn := 0
	for entry in res["cards"]:
		drawn += int(entry["n"])
	check(drawn == 8, "specialist_case draws cards_total = 8")
	check(gs.insight.gte(BigNumber.from_float(25.0)), "insight bonus applied to GameState")
	check(gs.gems == gems_before + 5, "gems bonus applied to GameState")
	check(opened_signal["fired"], "lootbox_opened emitted")
	var cards_in_state := 0
	for mid in gs.managers_state.keys():
		cards_in_state += int(gs.managers_state[mid].get("cards", 0))
	check(cards_in_state == 8, "cards applied to GameState.managers_state")

	# --- seeded 20k opens of field_case ---------------------------------------------
	gs.reset_to_new_game()
	var big_rng := RandomNumberGenerator.new()
	big_rng.seed = 987654321
	var rarity_counts := {"common": 0, "rare": 0, "epic": 0, "legendary": 0}
	var opens := 20000
	for i in range(opens):
		var r: Dictionary = LootboxSystem.open_box("field_case", big_rng)
		for entry in r["cards"]:
			var rarity: String = str(dl.get_manager_def(str(entry["id"])).get("rarity", ""))
			rarity_counts[rarity] = int(rarity_counts.get(rarity, 0)) + int(entry["n"])
	var total := 0
	for k in rarity_counts.keys():
		total += int(rarity_counts[k])
	check(total == opens * 4, "20k opens produced 80k cards")
	var common_share: float = float(rarity_counts["common"]) / float(total)
	check(absf(common_share - 0.78) <= 0.03, "common share %.4f within 0.78 +/- 0.03" % common_share)
	check(int(rarity_counts["legendary"]) > 0, "legendary cards dropped (got %d)" % int(rarity_counts["legendary"]))
	var rare_share: float = float(rarity_counts["rare"]) / float(total)
	check(absf(rare_share - 0.18) <= 0.02, "rare share %.4f within 0.18 +/- 0.02" % rare_share)
	# state consistency after mass opens
	var state_cards := 0
	for mid in gs.managers_state.keys():
		state_cards += int(gs.managers_state[mid].get("cards", 0))
	check(state_cards == total, "all 80k cards landed in GameState")
	check(gs.insight.eq(BigNumber.from_float(5.0 * float(opens))), "insight = 5 x 20000 opens")
	check(gs.gems == 25, "field_case grants no gems")

	print("DONE failures=", _failures)
	quit(0 if _failures == 0 else 1)
