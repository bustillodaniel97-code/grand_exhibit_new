extends SceneTree
## Meta branch tests (SPEC §12): quests, milestone chain, prestige retention, decor.
## Run: godot --headless --path <repo> -s tests/meta/test_meta.gd ; exit 0 pass / 1 fail.
##
## GODOT 4.4 -s NOTE: the engine DOES instantiate project autoloads for -s scripts
## (main.cpp registers them as named globals + root children), but only AFTER this
## entry script compiles. So this file must never reference autoload identifiers
## (EventBus/GameState/...) or preload autoload-referencing scripts at parse time.
## All work happens in _initialize(): autoloads come from root.get_node() (they are
## already the 9 named root children — no manual bootstrap needed) and meta scripts
## are load()-ed at runtime, when they compile cleanly.

var failures: int = 0
var quest_events: Array = []
var milestone_events: Array = []
var prestige_available_events: Array = []
var prestige_performed_events: Array = []
var decor_events: Array = []

# Singleton/script handles (bound in _initialize).
var EB: Node     # EventBus
var DL: Node     # DataLoader
var GS: Node     # GameState
var ECON: Node   # Economy
var QS: GDScript   # scripts/meta/quest_system.gd
var MS: GDScript   # scripts/meta/milestone_system.gd
var PS: GDScript   # scripts/meta/prestige_system.gd
var DS: GDScript   # scripts/meta/decor_system.gd

func check(cond: bool, msg: String) -> void:
	if cond:
		print("PASS: ", msg)
	else:
		failures += 1
		printerr("FAIL: ", msg)

func _initialize() -> void:
	EB = root.get_node("EventBus")
	DL = root.get_node("DataLoader")
	GS = root.get_node("GameState")
	ECON = root.get_node("Economy")
	check(EB != null and DL != null and GS != null and ECON != null, "autoloads present as root children")
	check(root.get_node("ClockGuard") != null and root.get_node("Analytics") != null
		and root.get_node("AdService") != null and root.get_node("IAPService") != null
		and root.get_node("SaveSystem") != null, "all 9 autoloads registered")
	DL.reload_all()  # autoload _ready fires after _initialize in -s mode; ensure data loaded
	QS = load("res://scripts/meta/quest_system.gd")
	MS = load("res://scripts/meta/milestone_system.gd")
	PS = load("res://scripts/meta/prestige_system.gd")
	DS = load("res://scripts/meta/decor_system.gd")
	check(QS != null and QS.can_instantiate(), "quest_system.gd compiles")
	check(MS != null and MS.can_instantiate(), "milestone_system.gd compiles")
	check(PS != null and PS.can_instantiate(), "prestige_system.gd compiles")
	check(DS != null and DS.can_instantiate(), "decor_system.gd compiles")
	_connect_probes()
	_test_data_integrity()
	_test_decor()
	_test_quest_milestone_prestige()
	print("META TESTS DONE — failures: %d" % failures)
	quit(1 if failures > 0 else 0)

func _connect_probes() -> void:
	EB.quest_completed.connect(func(qid): quest_events.append(qid))
	EB.milestone_completed.connect(func(vid, mid): milestone_events.append([vid, mid]))
	EB.prestige_available.connect(func(vid): prestige_available_events.append(vid))
	EB.prestige_performed.connect(func(f, t): prestige_performed_events.append([f, t]))
	EB.decor_purchased.connect(func(vid, did): decor_events.append([vid, did]))

# ---------------------------------------------------------------- data sanity
func _test_data_integrity() -> void:
	check(DL.quests.size() >= 20, "quest pool has 20+ quests (%d)" % DL.quests.size())
	var types: Dictionary = {}
	for qid in DL.quests.keys():
		types[DL.quests[qid]["type"]] = true
	for t in ["upgrade_count", "earn_total", "serve_total", "buy_decor", "own_managers"]:
		check(types.has(t), "quest pool covers type %s" % t)
	var order: Array = DL.venue_order()
	check(order.size() == 6, "6 venues in order")
	for vid in order:
		var defs: Array = DL.milestones.get(vid, [])
		check(defs.size() == 8, "venue %s has 8 milestones" % vid)
		if defs.size() == 8:
			check("(PRESTIGE)" in str(defs[7].get("name", "")), "venue %s m8 is PRESTIGE-named" % vid)
			var growing: bool = true
			for i in range(1, 8):
				var mv: float = float(defs[i]["global_income_mult"])
				var pv: float = float(defs[i - 1]["global_income_mult"])
				if mv <= pv or mv < 1.05 or mv > 1.25:
					growing = false
			check(growing, "venue %s milestone mults grow within 1.05..1.25" % vid)
	check(DL.decor.size() >= 18, "18+ decor pieces (%d)" % DL.decor.size())
	check(DL.decor_sets.size() >= 2, "2 decor sets")
	for sid in DL.decor_sets.keys():
		check(DL.decor_sets[sid].get("pieces", []).size() == 6, "set %s has 6 pieces" % sid)
	var event_count: int = 0
	for did in DL.decor.keys():
		if bool(DL.decor[did].get("event_exclusive", false)):
			event_count += 1
	check(event_count >= 3, "3 event_exclusive pieces (%d)" % event_count)

# ---------------------------------------------------------------- decor
func _test_decor() -> void:
	GS.reset_to_new_game()
	var vid: String = GS.current_venue
	check(DS.slots_total(vid) == 6, "venue 1 has 6 decor slots")
	GS.add_cash(BigNumber.from_parts(1.0, 7))
	var cash_before: BigNumber = GS.cash.copy()
	check(DS.buy_decor(vid, "oak_bench"), "buy oak_bench with cash")
	check(cash_before.sub(GS.cash).eq(BigNumber.from_float(500.0)), "oak_bench cost 500 cash")
	check(str(GS.venue_state(vid)["decor"].get("0", "")) == "oak_bench", "oak_bench placed in slot 0")
	check(DS.owned(vid, "oak_bench"), "owned() finds oak_bench")
	check(not DS.buy_decor(vid, "oak_bench"), "cannot buy duplicate in same venue")
	# Remaining heritage cash pieces.
	for did in ["heritage_arch", "velvet_rope", "crest_banner", "heritage_topiary"]:
		check(DS.buy_decor(vid, did), "buy %s" % did)
	# Gems piece: unaffordable at 25 starter gems, affordable after grant.
	check(not DS.buy_decor(vid, "brass_fountain"), "brass_fountain unaffordable at 25 gems")
	GS.add_gems(200)
	var gems_before: int = GS.gems
	check(DS.buy_decor(vid, "brass_fountain"), "buy brass_fountain with gems")
	check(GS.gems == gems_before - 120, "brass_fountain cost 120 gems")
	# Set complete -> Economy.decor_set_multiplier() == 1.15.
	var sp: Dictionary = DS.set_progress("heritage")
	check(int(sp["have"]) == 6 and int(sp["total"]) == 6 and bool(sp["complete"]), "heritage set 6/6 complete")
	check(absf(ECON.decor_set_multiplier() - 1.15) < 0.0001,
		"decor_set_multiplier == 1.15 (got %f)" % ECON.decor_set_multiplier())
	# Slots now full.
	check(DS.first_free_slot(vid) == -1, "all 6 slots full")
	check(not DS.buy_decor(vid, "marble_bust"), "buy blocked when slots full")
	# Event exclusives: not buyable, grantable without cost (venue 2 has free slots).
	check(not DS.buy_decor("copper_kettle", "pharaoh_mask"), "event_exclusive not buyable")
	var cash_pre: BigNumber = GS.cash.copy()
	var gems_pre: int = GS.gems
	check(DS.grant_event_decor("ancient_obelisk", "copper_kettle"), "grant_event_decor bypasses cost")
	check(GS.cash.eq(cash_pre) and GS.gems == gems_pre, "event grant spent nothing")
	check(str(GS.venue_state("copper_kettle")["decor"].get("0", "")) == "ancient_obelisk",
		"obelisk placed v2 slot 0")
	var spa: Dictionary = DS.set_progress("antiquity")
	check(int(spa["have"]) == 1 and int(spa["total"]) == 6, "antiquity set progress 1/6 cross-venue")
	check(decor_events.size() >= 7, "decor_purchased signals emitted (%d)" % decor_events.size())

# -------------------------------------------------- quests -> milestones -> prestige
func _test_quest_milestone_prestige() -> void:
	GS.reset_to_new_game()
	var vid: String = GS.current_venue
	QS.ensure_active_quests(vid)
	var vs: Dictionary = GS.venue_state(vid)
	check(vs["active_quests"].size() == 3, "3 active quests after ensure")
	check(str(vs["active_quests"][0]) == "q_prom_speed_3", "first quest is q_prom_speed_3")
	# Simulated stats: upgrade_count completion.
	GS.set_dept_level(vid, "promotions", "speed", 3)
	QS.evaluate(vid)
	check("q_prom_speed_3" in quest_events, "q_prom_speed_3 completed via simulated stat")
	check(absf(float(vs["progress"]) - 0.08) < 0.001, "progress += 0.08 (got %f)" % float(vs["progress"]))
	check(vs["active_quests"].size() == 3, "replacement quest drawn")
	check("q_prom_speed_3" not in vs["active_quests"], "completed quest removed from active")
	check("q_gallery_value_3" in vs["active_quests"], "next pool quest drew in (q_gallery_value_3)")
	# Drive the whole venue chain: force-complete actives until all 8 milestones done.
	var gems_before_chain: int = GS.gems
	var cards_before_chain: int = _total_cards()
	var guard: int = 0
	while GS.venue_state(vid).get("milestones", []).size() < 8 and guard < 400:
		_force_complete_active(vid)
		QS.evaluate(vid)
		guard += 1
	var done_ms: Array = GS.venue_state(vid).get("milestones", [])
	check(done_ms.size() == 8, "all 8 milestones completed (in %d batches)" % guard)
	check("wp_m1" in done_ms and "wp_m8" in done_ms, "milestone ids wp_m1..wp_m8 recorded")
	check(milestone_events.size() == 8, "8 milestone_completed signals")
	check(GS.gems == gems_before_chain + 360, "milestone gems granted (10+20+...+80 = 360)")
	check(_total_cards() > cards_before_chain, "milestone box cards granted")
	check(vid in prestige_available_events, "prestige_available emitted after 8th")
	check(PS.can_prestige(), "can_prestige() true")
	check(GS.feature_unlocked("prestige"), "feature_unlocked('prestige') true")
	# Retention snapshot + prestige.
	GS.add_cash(BigNumber.from_parts(7.0, 5))
	GS.add_gems(77)
	GS.add_insight(BigNumber.from_float(4242.0))
	GS.pending_cash[vid] = BigNumber.from_float(999.0)
	GS.venue_state(vid)["decor"]["0"] = "oak_bench"
	var cash_pre: BigNumber = GS.cash.copy()
	var gems_pre: int = GS.gems
	var insight_pre: BigNumber = GS.insight.copy()
	var cards_pre: int = _total_cards()
	check(PS.do_prestige(), "do_prestige() succeeded")
	check(GS.current_venue == "copper_kettle", "current venue advanced to copper_kettle")
	check("copper_kettle" in GS.venues_unlocked and vid in GS.venues_unlocked, "both venues unlocked")
	check(prestige_performed_events.size() == 1, "prestige_performed emitted")
	# Retained (SPEC §6.1):
	check(GS.cash.eq(cash_pre), "CASH retained across prestige")
	check(GS.gems == gems_pre, "GEMS retained across prestige")
	check(GS.insight.eq(insight_pre), "INSIGHT retained across prestige")
	check(_total_cards() == cards_pre, "MANAGERS retained across prestige")
	check(str(GS.venue_state(vid)["decor"].get("0", "")) == "oak_bench", "DECOR retained across prestige")
	# Reset:
	var old_vs: Dictionary = GS.venue_state(vid)
	check(GS.dept_level(vid, "promotions", "speed") == 1, "old venue dept levels reset")
	check(int(old_vs["depts"]["promotions"]["staff"]) == 1, "old venue staff reset to base")
	check(float(old_vs["progress"]) == 0.0, "old venue progress reset to 0")
	check(old_vs["active_quests"].is_empty(), "old venue active_quests cleared")
	check(old_vs["milestones"].size() == 8, "old venue milestones KEPT as history")
	check(not GS.pending_cash.has(vid), "pending cash cleared on switch")
	# New venue ready:
	check(GS.venue_state("copper_kettle")["active_quests"].size() == 3, "new venue has 3 active quests")
	check(not PS.can_prestige(), "can_prestige false in new venue")
	check(PS.block_reason() != "", "block_reason explains why")

func _total_cards() -> int:
	var n: int = 0
	for mid in GS.managers_state.keys():
		n += int(GS.managers_state[mid].get("cards", 0))
	return n

## Set GameState so every currently-active quest in the venue is satisfied.
func _force_complete_active(vid: String) -> void:
	var vs: Dictionary = GS.venue_state(vid)
	for qid in vs.get("active_quests", []):
		var qdef: Dictionary = DL.quests.get(str(qid), {})
		var target := BigNumber.from_parts(float(qdef.get("target_m", 1.0)), int(qdef.get("target_e", 0)))
		match str(qdef.get("type", "")):
			"upgrade_count":
				GS.set_dept_level(vid, str(qdef.get("dept", "")), str(qdef.get("track", "")),
					int(target.to_float_approx()))
			"earn_total":
				vs["earned_total"] = target.to_save()
			"serve_total":
				vs["served_total"] = target.to_save()
			"buy_decor":
				var placed: Dictionary = vs.get("decor", {})
				var need: int = int(target.to_float_approx())
				var filler: Array = ["oak_bench", "heritage_arch", "velvet_rope",
					"crest_banner", "heritage_topiary", "mosaic_floor"]
				var i: int = 0
				while placed.size() < need and i < 64:
					placed[str(1000 + i)] = filler[i % filler.size()]  # fake slots, real ids
					i += 1
				vs["decor"] = placed
			"own_managers":
				var need: int = int(target.to_float_approx())
				var count: int = 0
				for mid in DL.managers.keys():
					var st: Dictionary = GS.managers_state.get(mid,
						{"cards": 0, "level": 1, "rank": 1, "assigned_to": ""})
					if int(st.get("cards", 0)) >= 1:
						count += 1
					elif count < need:
						st["cards"] = 1
						GS.managers_state[mid] = st
						count += 1
