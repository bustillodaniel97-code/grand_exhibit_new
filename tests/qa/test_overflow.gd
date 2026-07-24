extends SceneTree
## QA M5-4: overflow safety at aa+ magnitudes (SPEC §0 notation, §3 BigNumber).
## - add_cash(1e30) -> spend at venue-6 (aurora_world, cost_exp 15) succeeds
## - cash.to_notation() matches ^\d+(\.\d+)?a[a-z]$ at those magnitudes
## - purchasing in a 1e45 economy never NaNs: BigNumber invariant m in [1,10)
##   holds for cash, costs, and venue_rates outputs after every op
## Run: godot --headless --path <repo> -s tests/qa/test_overflow.gd

var failures: int = 0

const V6 := "aurora_world"

func check(cond: bool, msg: String) -> void:
	if cond:
		print("  PASS ", msg)
	else:
		failures += 1
		printerr("  FAIL ", msg)

func invariant_ok(b: BigNumber) -> bool:
	if b.is_zero():
		return true
	return b.m >= 1.0 and b.m < 10.0 and not is_nan(b.m) and not is_inf(b.m)

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var DL: Node = root.get_node("DataLoader")
	var GS: Node = root.get_node("GameState")
	var ECON: Node = root.get_node("Economy")
	DL.reload_all()
	GS.reset_to_new_game()
	GS.ready_flag = false

	var re := RegEx.new()
	re.compile("^\\d+(\\.\\d+)?a[a-z]$")

	print("-- 1e30 cash vs venue-6 (cost_exp 15) --")
	GS.add_cash(BigNumber.from_parts(1.0, 30))  # ~1e30 (aa+ range)
	check(GS.cash.e == 30, "cash exponent is 30 (got %d)" % GS.cash.e)
	check(re.search(GS.cash.to_notation()) != null,
		"notation matches ^\\d+(\\.\\d+)?a[a-z]$ at 1e30 (got %s)" % GS.cash.to_notation())
	var cash_before: BigNumber = GS.cash.copy()
	var ok_promo: bool = ECON.purchase_upgrade(V6, "promotions", "speed")
	check(ok_promo, "venue-6 purchase succeeds with 1e30 cash")
	check(GS.cash.lt(cash_before), "venue-6 purchase actually charged")
	check(GS.cash.e >= 29, "cash still ~1e30 after venue-6 purchase (e=%d)" % GS.cash.e)
	check(invariant_ok(GS.cash), "cash invariant m in [1,10) after venue-6 spend")
	check(re.search(GS.cash.to_notation()) != null,
		"notation still a-suffixed after venue-6 spend (got %s)" % GS.cash.to_notation())

	print("-- 1e45 economy: sustained purchasing, no NaN anywhere --")
	GS.add_cash(BigNumber.from_parts(1.0, 45))
	check(GS.cash.e >= 44, "cash at ~1e45 (e=%d)" % GS.cash.e)
	var bought: int = 0
	var invariant_held: bool = true
	var combos: Array = []
	for dept in ["promotions", "ticket", "archive", "gallery"]:
		for track in ["staff", "speed", "value"]:
			combos.append([dept, track])
	var rounds: int = 0
	while bought < 60 and rounds < 40:
		rounds += 1
		for c in combos:
			# Check the cost BigNumber BEFORE buying: never NaN, always normalized.
			var lvl: int = GS.dept_level(V6, c[0], c[1])
			var cost: BigNumber = DL.upgrade_cost(c[0], c[1], lvl,
				float(DL.get_venue(V6).get("cost_mult", 1.0)), int(DL.get_venue(V6).get("cost_exp", 0)))
			if not invariant_ok(cost):
				invariant_held = false
				printerr("  BAD COST at %s/%s lvl %d: m=%s e=%d" % [c[0], c[1], lvl, str(cost.m), cost.e])
			if ECON.purchase_upgrade(V6, c[0], c[1]):
				bought += 1
				if not invariant_ok(GS.cash):
					invariant_held = false
					printerr("  BAD CASH after buy #%d: m=%s e=%d" % [bought, str(GS.cash.m), GS.cash.e])
	check(bought >= 60, "bought 60 upgrades at venue 6 in 1e45 economy (%d)" % bought)
	check(invariant_held, "BigNumber invariant m in [1,10) held through 60 purchases (no NaN)")

	print("-- venue_rates sanity at maxed venue-6 --")
	for dept in ["promotions", "ticket", "archive", "gallery"]:
		GS.set_dept_level(V6, dept, "speed", 50)
		GS.set_dept_level(V6, dept, "value", 50)
	var rates: Dictionary = ECON.venue_rates(V6)
	check(invariant_ok(rates["value_per_visitor"]), "value_per_visitor normalized at level 50")
	check(invariant_ok(rates["pending_per_s"]), "pending_per_s normalized at level 50")
	check(invariant_ok(rates["banked_per_s"]), "banked_per_s normalized at level 50")
	check(not is_nan(rates["arrival_per_s"]) and not is_nan(rates["serve_per_s"])
		and not is_nan(rates["transport_per_s"]), "float rates not NaN at level 50")
	check(str(rates["choke_id"]) in ["promotions", "ticket", "archive"], "choke_id sane at level 50")
	check(re.search((rates["banked_per_s"] as BigNumber).to_notation()) != null
		or (rates["banked_per_s"] as BigNumber).e < 15,
		"banked_per_s notation printable (got %s)" % (rates["banked_per_s"] as BigNumber).to_notation())

	print("-- notation spot checks across aa..az band --")
	for pair in [[1.0, 15, "aa"], [1.0, 18, "ab"], [4.5, 21, "ac"], [9.99, 90, "bt"]]:
		var b := BigNumber.from_parts(pair[0], pair[1])
		var n: String = b.to_notation()
		check(re.search(n) != null, "notation %s matches aa-band regex (1e%d)"
			% [n, pair[1]])

	print("---")
	if failures == 0:
		print("ALL QA OVERFLOW TESTS PASSED")
	else:
		printerr("QA OVERFLOW TESTS FAILED: %d" % failures)
	quit(0 if failures == 0 else 1)
