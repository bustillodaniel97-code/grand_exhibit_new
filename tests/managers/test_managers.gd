extends SceneTree
## tests/managers/test_managers.gd — manager system rules (SPEC §5, §12).
## Run: godot --headless --path . -s tests/managers/test_managers.gd ; exit 0 = pass.

## NOTE on bootstrap: under `-s` this entry script compiles BEFORE autoload globals
## resolve, so it must not reference them by name. By the time run() executes the
## autoloads are live root children — fetch them via root.get_node() and only then
## load() scripts that reference autoload names (a const preload would compile too
## early and fail). Do NOT add duplicate nodes: that shadows the real singletons.
const MS_PATH := "res://scripts/managers/manager_system.gd"

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
	var eb: Node = root.get_node("EventBus")
	var eco: Node = root.get_node("Economy")
	var ManagerSystem: GDScript = load(MS_PATH)
	gs.reset_to_new_game()

	# --- roster sanity ---------------------------------------------------------
	check(root.get_node("DataLoader").managers.size() == 14, "roster has 14 managers")
	var by_rarity := {"common": 0, "rare": 0, "epic": 0, "legendary": 0}
	for mid in root.get_node("DataLoader").managers.keys():
		by_rarity[root.get_node("DataLoader").managers[mid]["rarity"]] += 1
	check(by_rarity["common"] == 4 and by_rarity["rare"] == 4
		and by_rarity["epic"] == 4 and by_rarity["legendary"] == 2, "rarity split 4/4/4/2")
	check(ManagerSystem.exchange_ratio() == 5, "exchange_ratio = 5 from data")

	# --- level-up cost curve + cap ----------------------------------------------
	ManagerSystem.add_cards("docent_poppy", 1)  # common: base 10, growth 1.12, cap 50
	check(ManagerSystem.owned("docent_poppy"), "owned = cards >= 1")
	check(not ManagerSystem.owned("barker_theo"), "unowned at 0 cards")
	gs.add_insight(BigNumber.from_float(100000.0))
	var c1: float = ManagerSystem.level_up_cost("docent_poppy").to_float_approx()
	check(absf(c1 - 10.0) < 0.001, "level 1->2 cost = base 10")
	var leveled_signal := {"fired": false, "level": 0}
	eb.manager_leveled.connect(func(_id: String, lvl: int) -> void:
		leveled_signal["fired"] = true
		leveled_signal["level"] = lvl)
	check(ManagerSystem.level_up("docent_poppy"), "level_up succeeds")
	check(ManagerSystem.level("docent_poppy") == 2, "level incremented to 2")
	check(leveled_signal["fired"] and leveled_signal["level"] == 2, "manager_leveled emitted")
	var c2: float = ManagerSystem.level_up_cost("docent_poppy").to_float_approx()
	check(absf(c2 - 11.2) < 0.001, "level 2->3 cost = 10 * 1.12")
	check(ManagerSystem.level_up("docent_poppy"), "second level_up succeeds")
	ManagerSystem.state("docent_poppy")["level"] = 50  # cap
	check(not ManagerSystem.can_level_up("docent_poppy"), "capped at level_cap 50")
	check(not ManagerSystem.level_up("docent_poppy"), "level_up refused at cap")
	ManagerSystem.state("docent_poppy")["level"] = 2
	gs.insight = BigNumber.zero()
	check(not ManagerSystem.level_up("docent_poppy"), "level_up refused when insight short")
	gs.add_insight(BigNumber.from_float(100000.0))

	# --- rank-up duplicate spend + keep-1 ---------------------------------------
	ManagerSystem.add_cards("paleontologist_rex", 3)  # rare, dup_costs [2,4,8]
	var ranked_signal := {"fired": false, "rank": 0}
	eb.manager_ranked_up.connect(func(_id: String, r: int) -> void:
		ranked_signal["fired"] = true
		ranked_signal["rank"] = r)
	check(ManagerSystem.rank_up("paleontologist_rex"), "rank_up to 2 with 3 cards (cost 2, keep 1)")
	check(ManagerSystem.cards("paleontologist_rex") == 1, "cards 3 -> 1 after rank-up")
	check(ManagerSystem.rank("paleontologist_rex") == 2, "rank is 2")
	check(ranked_signal["fired"] and ranked_signal["rank"] == 2, "manager_ranked_up emitted")
	check(not ManagerSystem.rank_up("paleontologist_rex"), "rank-up refused: 1 card < cost 4 + keep 1")
	ManagerSystem.add_cards("paleontologist_rex", 4)  # now 5 cards
	check(ManagerSystem.rank_up("paleontologist_rex"), "rank_up to 3 (cost 4, keeps 1)")
	check(ManagerSystem.cards("paleontologist_rex") == 1 and ManagerSystem.rank("paleontologist_rex") == 3,
		"cards 5 -> 1, rank 3")
	ManagerSystem.state("paleontologist_rex")["rank"] = 4
	check(ManagerSystem.rank_up_cost("paleontologist_rex") == 0, "rank 4 is max")
	check(not ManagerSystem.rank_up("paleontologist_rex"), "rank_up refused at max rank")

	# --- assign: specialty rule + one-per-dept -----------------------------------
	check(not ManagerSystem.assign("docent_poppy", "gallery"), "assign wrong specialty refused")
	check(not ManagerSystem.assign("barker_theo", "promotions"), "assign unowned refused")
	check(ManagerSystem.assign("docent_poppy", "ticket"), "assign to specialty dept works")
	check(ManagerSystem.assigned_to("docent_poppy") == "ticket", "assigned_to stored in state")
	ManagerSystem.add_cards("usher_bram", 1)  # also ticket specialty
	check(not ManagerSystem.assign("usher_bram", "ticket"), "one manager per dept enforced")
	check(ManagerSystem.unassign("docent_poppy"), "unassign works")
	check(ManagerSystem.assign("usher_bram", "ticket"), "dept free after unassign")

	# --- economy multiplier hook --------------------------------------------------
	var before: float = eco.manager_multiplier_for("gallery")
	ManagerSystem.add_cards("night_curator", 1)  # legendary, gallery, base_mult 0.10
	check(ManagerSystem.assign("night_curator", "gallery"), "assign legendary to gallery")
	var after: float = eco.manager_multiplier_for("gallery")
	check(after > before, "Economy.manager_multiplier_for(gallery) increases after assign (%f -> %f)" % [before, after])
	check(absf(after - 1.10) < 0.0001, "gallery mult = 1 + 0.10 * lvl1 * rank1")
	ManagerSystem.state("night_curator")["level"] = 10
	check(absf(eco.manager_multiplier_for("gallery") - 2.0) < 0.0001, "gallery mult scales with level")

	# --- exchange 5:1 same-rarity + keep-1 ----------------------------------------
	ManagerSystem.add_cards("barker_theo", 6)  # common promotions
	var ex_signal := {"fired": false}
	eb.manager_exchanged.connect(func(_f: String, _t: String, spent: int, gained: int) -> void:
		ex_signal["fired"] = spent == 5 and gained == 1)
	check(ManagerSystem.exchange("barker_theo", "archivist_mabel"), "exchange 5:1 same rarity")
	check(ManagerSystem.cards("barker_theo") == 1, "from keeps exactly 1 card")
	check(ManagerSystem.cards("archivist_mabel") == 1, "to gains 1 card")
	check(ex_signal["fired"], "manager_exchanged emitted (5 spent, 1 gained)")
	check(not ManagerSystem.exchange("barker_theo", "storyteller_june"), "keep-1 rule blocks 1-card trade")
	check(not ManagerSystem.exchange("barker_theo", "paleontologist_rex"), "cross-rarity exchange refused")
	check(not ManagerSystem.exchange("barker_theo", "barker_theo"), "self-exchange refused")

	# --- battle attack formula (SPEC §6) -------------------------------------------
	var nc_def: Dictionary = ManagerSystem.manager_def("night_curator")
	var atk1: float = ManagerSystem.battle_attack(nc_def, {"level": 1, "rank": 1})
	check(absf(atk1 - 150.0) < 0.001, "battle_attack lvl1 rank1 = 150")
	var atk2: float = ManagerSystem.battle_attack(nc_def, {"level": 11, "rank": 3})
	check(absf(atk2 - 150.0 * 2.2 * 2.25) < 0.01, "battle_attack lvl11 rank3 = 742.5")

	print("DONE failures=", _failures)
	quit(0 if _failures == 0 else 1)
