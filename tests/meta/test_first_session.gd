extends SceneTree
## Deterministic first-session pacing simulation.
##
## Models an attentive, non-paying player who follows the three rolling mission
## cards, spends earned cash on their requested upgrades, and never uses ad or
## manual-collection shortcuts. This is intentionally conservative: real play
## receives tap bags, milestone rewards and optional boosts on top.

var failures := 0
var elapsed_s := 0
var QS: GDScript
var MS: GDScript
var PS: GDScript
var DS: GDScript
var DL: Node
var GS: Node
var ECON: Node

func check(ok: bool, message: String) -> void:
	if ok:
		print("PASS: ", message)
	else:
		failures += 1
		printerr("FAIL: ", message)

func _initialize() -> void:
	var save_system: Node = root.get_node("SaveSystem")
	save_system.set_process(false)
	save_system.autosave_interval_sec = 1 << 30
	DL = root.get_node("DataLoader")
	GS = root.get_node("GameState")
	ECON = root.get_node("Economy")
	DL.reload_all()
	GS.reset_to_new_game()
	GS.ready_flag = true
	QS = load("res://scripts/meta/quest_system.gd")
	MS = load("res://scripts/meta/milestone_system.gd")
	PS = load("res://scripts/meta/prestige_system.gd")
	DS = load("res://scripts/meta/decor_system.gd")
	var venue_id: String = GS.current_venue
	QS.ensure_active_quests(venue_id)

	var limit_s := 45 * 60
	while not PS.gate_met(venue_id) and elapsed_s < limit_s:
		# One-second fixed simulation. Using the real choke-point economy keeps
		# every cost, staff purchase and throughput dependency in the result.
		ECON._tick(1.0)
		elapsed_s += 1
		_follow_active_missions(venue_id)
		QS.evaluate(venue_id)
		_advance_core_build(venue_id)

	var milestones: int = GS.venue_state(venue_id).get("milestones", []).size()
	check(PS.gate_met(venue_id),
		"an attentive free player can finish venue one without boosts")
	check(elapsed_s >= 8 * 60,
		"venue one still has an introductory runway (%s)" % _clock(elapsed_s))
	check(elapsed_s <= limit_s,
		"venue one completes inside a 45-minute active-session ceiling (%s)" % _clock(elapsed_s))
	check(milestones == 4, "the simulation earns all four authored milestones")
	check(_highest_track(venue_id) <= 15,
		"completion never requires a department track above the venue cap")
	print("FIRST SESSION: %s, cash %s, milestones %d/4" % [
		_clock(elapsed_s), GS.cash.to_notation(), milestones])
	_simulate_campaign()
	quit(1 if failures > 0 else 0)

func _simulate_campaign() -> void:
	var order: Array = DL.venue_order()
	var completion_times := {GS.current_venue: elapsed_s}
	# Horizon, not target. It was seven days when the ladder was six venues and a
	# whole campaign fitted inside a week. The ladder is twelve venues now and the
	# late cost curve is tuned so each museum takes longer than the one before it
	# — roughly 20h rising to 50h, which is the band Idle Bank Tycoon's mid-game
	# banks sit in. A twelve-rung ladder at that cadence cannot finish in a week
	# BY DESIGN, so the horizon exists only to stop a deadlocked run spinning
	# forever; the real pacing assertions are the window checks below.
	var horizon := 14 * 24 * 60 * 60
	while GS.current_venue != str(order.back()) and elapsed_s < horizon:
		check(PS.graduate(), "completed venue graduates cleanly")
		var venue_id: String = GS.current_venue
		if venue_id == str(order.back()):
			break
		QS.ensure_active_quests(venue_id)
		while not PS.gate_met(venue_id) and elapsed_s < horizon:
			ECON._tick(5.0)
			elapsed_s += 5
			_follow_active_missions(venue_id)
			QS.evaluate(venue_id)
			_advance_core_build(venue_id)
		if PS.gate_met(venue_id):
			completion_times[venue_id] = elapsed_s
			print("CAMPAIGN: %s reached READY at %s" % [venue_id, _long_clock(elapsed_s)])
	var finale_arrival_s: int = elapsed_s
	# Continue building the destination through the remainder of week one. It has
	# no next-venue button, but its own milestone/operation curve must still move.
	var finale: String = GS.current_venue
	while not PS.gate_met(finale) and elapsed_s < horizon:
		ECON._tick(5.0)
		elapsed_s += 5
		_follow_active_missions(finale)
		QS.evaluate(finale)
		_advance_core_build(finale)
	check(GS.current_venue == str(order.back()),
		"a no-boost campaign reaches the final museum without deadlocking")
	# Five to ten days to open the final museum. Below five and the twelve-venue
	# ladder is not carrying its own weight; above ten and a committed free
	# player never sees the ending. IBT spends ~7 days reaching bank six of six
	# WITH heavy ad use, so this band is a comparable cadence over twice as many
	# rungs.
	check(finale_arrival_s >= 5 * 24 * 60 * 60 and finale_arrival_s <= 10 * 24 * 60 * 60,
		"the finale opens after a real campaign, not a weekend (%s)"
			% _long_clock(finale_arrival_s))
	check(PS.operations_progress(finale) > 0.25,
		"week-one play makes material progress inside the final museum")
	check(finale_arrival_s > 2 * 24 * 60 * 60,
		"a perfect no-boost player cannot consume the full venue ladder in a weekend")
	var reached_day_one := 0
	for seconds in completion_times.values():
		if int(seconds) <= 24 * 60 * 60:
			reached_day_one += 1
	# Scaled to the ladder, not fixed at four. The intent is "meaningful progress
	# without consuming the game": at least two museums on day one, and never
	# more than half the ladder. The old literal 4 was two thirds of a six-venue
	# ladder and became a third of a twelve-venue one, so it started failing on a
	# run that had actually got SLOWER in proportion.
	var day_one_cap: int = maxi(4, int(order.size() / 2))
	check(reached_day_one >= 2 and reached_day_one <= day_one_cap,
		"day one contains meaningful campaign progress (%d venues ready, cap %d)"
			% [reached_day_one, day_one_cap])
	check(completion_times.size() >= order.size() - 1,
		"every pre-finale venue reaches READY without a progression deadlock")

func _follow_active_missions(venue_id: String) -> void:
	var active: Array = GS.venue_state(venue_id).get("active_quests", []).duplicate()
	for qid in active:
		var quest: Dictionary = DL.quests.get(str(qid), {})
		var guard := 0
		while not QS.is_complete(venue_id, quest) and guard < 30:
			guard += 1
			var bought := false
			match str(quest.get("type", "")):
				"upgrade_count":
					bought = ECON.purchase_upgrade(venue_id,
						str(quest.get("dept", "")), str(quest.get("track", "")))
				"item_level":
					var dept: String = str(quest.get("dept", ""))
					var index: int = int(quest.get("item", 0))
					# A mission may arrive before its station exists. Open the
					# required station first, exactly as a player would.
					while GS.dept_items(venue_id, dept).size() <= index:
						if not ECON.purchase_upgrade(venue_id, dept, "staff"):
							return
					bought = ECON.purchase_item_upgrade(venue_id, dept, index)
				"buy_decor":
					bought = _buy_cash_decor(venue_id)
				_:
					return # earnings/serving missions advance through Economy
			if not bought:
				break

func _highest_track(venue_id: String) -> int:
	var highest := 1
	for dept in ["promotions", "ticket", "archive", "gallery"]:
		for track in ["speed", "value"]:
			highest = maxi(highest, GS.dept_level(venue_id, dept, track))
	return highest

func _advance_core_build(venue_id: String) -> void:
	if PS.operations_met(venue_id) and not PS.decor_met(venue_id):
		_buy_cash_decor(venue_id)
		return
	# Spend remaining cash on the cheapest unfinished flow track. This mirrors
	# the Statistics sheet's recommendation once mission bars are complete.
	var cap: int = int(DL.get_venue(venue_id).get("track_level_cap", 100))
	var best: Array = []
	var best_cost: BigNumber
	for spec in PS.core_tracks():
		var dept: String = str(spec[0])
		var track: String = str(spec[1])
		if GS.dept_level(venue_id, dept, track) >= cap:
			continue
		var cost: BigNumber = DL.upgrade_cost(dept, track,
			GS.dept_level(venue_id, dept, track),
			float(DL.get_venue(venue_id).get("cost_mult", 1.0)),
			int(DL.get_venue(venue_id).get("cost_exp", 0)))
		if best.is_empty() or cost.lt(best_cost):
			best = [dept, track]
			best_cost = cost
	if not best.is_empty():
		ECON.purchase_upgrade(venue_id, str(best[0]), str(best[1]))

func _clock(seconds: int) -> String:
	return "%02d:%02d" % [seconds / 60, seconds % 60]

func _long_clock(seconds: int) -> String:
	return "%dd %02d:%02d" % [
		seconds / 86400, (seconds % 86400) / 3600, (seconds % 3600) / 60]

func _buy_cash_decor(venue_id: String) -> bool:
	var choices: Array = DL.decor.keys()
	choices.sort_custom(func(a: String, b: String) -> bool:
		var da: Dictionary = DL.get_decor(a)
		var db: Dictionary = DL.get_decor(b)
		return int(da.get("cost_cash_e", 99)) < int(db.get("cost_cash_e", 99)))
	for decor_id in choices:
		var definition: Dictionary = DL.get_decor(str(decor_id))
		if bool(definition.get("event_exclusive", false)):
			continue
		if int(definition.get("cost_gems", 0)) > 0:
			continue
		if DS.buy_decor(venue_id, str(decor_id)):
			return true
	return false
