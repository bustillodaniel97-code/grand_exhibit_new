extends SceneTree
## test_decor_ownership.gd — the decor ownership/placement contract.
##
## The defect this pins down: decor was owned only WHERE IT STOOD. A player who
## bought six pieces in Whispering Pines and moved to Tidewater met an empty
## floor and a shop asking full price again, and reported it as "my decor did
## not spawn". The rule now is the one the handoff recommends:
##
##   · buying is PER MUSEUM — a new building stocks its own shelves at its own
##     prices, which is what makes it a new setting rather than a reskin, and is
##     what Idle Bank Tycoon does when you open a new bank;
##   · within one museum, storage is free both ways, so a slot decision is never
##     a one-way trap;
##   · set bonuses stay cross-museum (SPEC §7), computed over the historical
##     collection rather than over one building.
##
## Run: godot --headless --path <repo> -s tests/meta/test_decor_ownership.gd


## Autoload aliases. Under -s the main script compiles before autoload names
## are bound, so DataLoader et al are unavailable as bare identifiers here.
var DL: Node

## load() at runtime, NOT preload(). Under -s the main script compiles before
## autoload names are reliably bound, and these helpers name
## GameState/DataLoader/Analytics at class scope. Preloading them compiles
## them too early: the calls then no-op against a dead GDScript, no check()
## ever runs, and the suite reports a FALSE GREEN.
var DecorSystem: GDScript

var failures := 0

func check(cond: bool, msg: String) -> void:
	if cond:
		print("  PASS ", msg)
	else:
		failures += 1
		printerr("  FAIL ", msg)

func _init() -> void:
	call_deferred("run")

const V1 := "whispering_pines"
const V2 := "copper_kettle"

func run() -> void:
	for pair in [["event_bus", "EventBus"], ["data_loader", "DataLoader"],
			["clock_guard", "ClockGuard"], ["analytics", "Analytics"],
			["ad_service", "AdService"], ["iap_service", "IAPService"],
			["game_state", "GameState"], ["save_system", "SaveSystem"],
			["economy", "Economy"]]:
		if root.has_node(pair[1]):
			continue
		var n: Node = (load("res://autoload/%s.gd" % pair[0]) as GDScript).new()
		n.name = pair[1]
		root.add_child(n)

	# Under -s the main script compiles before autoload names are bound; take
	# local aliases to the bootstrapped singletons instead.
	DecorSystem = load("res://scripts/meta/decor_system.gd") as GDScript
	var GS: Node = root.get_node("GameState")
	var SS: Node = root.get_node("SaveSystem")
	var EB: Node = root.get_node("EventBus")
	var EC: Node = root.get_node("Economy")
	DL = root.get_node("DataLoader")
	# Never let the autosave clock write while a test is doctoring state.
	SS.set_process(false)
	SS.autosave_interval_sec = 1 << 30

	GS.reset_to_new_game()
	GS.ready_flag = true

	_test_buy_unlocks_globally(GS, EB)
	_test_second_venue_charges_again(GS)
	_test_removal_frees_the_slot(GS)
	_test_slot_pressure(GS)
	_test_set_progress_survives_the_move(GS)
	_test_satisfaction_tracks_placement(GS, EC)
	_test_migration_derives_ownership(SS)
	_test_round_trip(GS, SS)

	print("---")
	print("decor ownership: %d failure(s)" % failures)
	quit(0 if failures == 0 else 1)

## Give the player enough money that affordability is never the thing under test.
func _fund(GS: Node) -> void:
	GS.cash = BigNumber.from_parts(9.0, 12)
	GS.gems = 100000

func _test_buy_unlocks_globally(GS: Node, EB: Node) -> void:
	print("-- buying unlocks the design account-wide --")
	# Deliberately NOT _fund(): a BigNumber keeps a mantissa and an exponent, so
	# subtracting a 5.0e2 bench from a 9.0e12 balance rounds straight back to
	# 9.0e12 and the charge becomes unobservable. Fund near the price instead.
	GS.cash = BigNumber.from_parts(1.0, 4)
	GS.gems = 100000
	var seen: Array = []
	var probe := func(vid: String, did: String) -> void: seen.append([vid, did])
	EB.decor_purchased.connect(probe)

	var before: BigNumber = GS.cash
	check(DecorSystem.buy_decor(V1, "oak_bench"), "first purchase succeeds")
	check(GS.cash.lt(before), "the first purchase charges the player")
	check(GS.owns_decor_design("oak_bench"), "the design is now owned globally")
	check(DecorSystem.owned(V1, "oak_bench"), "and it stands in the venue bought in")
	check(not DecorSystem.owned(V2, "oak_bench"),
		"but it does NOT stand in a venue it was never placed in")
	check(seen.size() == 1, "decor_purchased fired exactly once (%d)" % seen.size())
	check(seen.size() == 1 and str(seen[0][0]) == V1 and str(seen[0][1]) == "oak_bench",
		"decor_purchased carried the venue and the piece")
	EB.decor_purchased.disconnect(probe)

	check(not DecorSystem.buy_decor(V1, "oak_bench"),
		"buying the same piece into the same venue twice is refused")

func _test_second_venue_charges_again(GS: Node) -> void:
	print("-- a new museum stocks its own decor, at its own price --")
	GS.cash = BigNumber.from_parts(1.0, 4)
	GS.gems = 100000
	check(not DecorSystem.bought_here(V2, "oak_bench"),
		"the second museum has not bought this piece")
	check(DecorSystem.owned_previously(V2, "oak_bench"),
		"but the shop can tell the player they had it before")

	var before: BigNumber = GS.cash
	check(DecorSystem.buy_decor(V2, "oak_bench"),
		"the piece can be bought for the second museum")
	check(GS.cash.lt(before),
		"and it IS charged again — a new building is not a reskin of the last")
	check(DecorSystem.bought_here(V2, "oak_bench"), "now it is stocked here")
	check(DecorSystem.owned(V1, "oak_bench"),
		"buying it here did not disturb the first museum")

	# place_decor is the storage round trip, and is scoped to one building.
	check(not DecorSystem.place_decor(V2, "sphinx_statue"),
		"place_decor refuses a piece never bought in this museum")
	_fund(GS)
	check(DecorSystem.buy_decor(V1, "sphinx_statue"), "buy the sphinx in museum one")
	check(not DecorSystem.place_decor(V2, "sphinx_statue"),
		"and owning it THERE still does not stock it HERE")

func _test_removal_frees_the_slot(GS: Node) -> void:
	print("-- storage frees a slot without confiscating the design --")
	var used_before: int = DecorSystem.slots_used(V2)
	check(DecorSystem.remove_decor(V2, "oak_bench"), "the piece can be put in storage")
	check(DecorSystem.slots_used(V2) == used_before - 1,
		"a slot came back (%d -> %d)" % [used_before, DecorSystem.slots_used(V2)])
	check(not DecorSystem.owned(V2, "oak_bench"), "it no longer stands there")
	check(GS.owns_decor_design("oak_bench"),
		"but the design is STILL owned — storage is not a refund and not a loss")
	var cash_before: BigNumber = GS.cash
	check(DecorSystem.place_decor(V2, "oak_bench"),
		"and it can be stood back up in the SAME museum")
	check(GS.cash.to_float_approx() == cash_before.to_float_approx(),
		"for free — it was already paid for in this building")
	check(not DecorSystem.remove_decor(V2, "crystal_chandelier"),
		"removing something that is not placed is refused")

func _test_slot_pressure(GS: Node) -> void:
	print("-- slots, not money, are the constraint on placement --")
	_fund(GS)
	var total: int = DecorSystem.slots_total(V1)
	var buyable: Array = []
	for did in DL.decor.keys():
		if not bool(DL.decor[did].get("event_exclusive", false)):
			buyable.append(str(did))
	buyable.sort()
	check(buyable.size() > total,
		"the catalogue (%d) is bigger than one venue's slots (%d), so placement is a choice"
			% [buyable.size(), total])
	for did in buyable:
		DecorSystem.buy_decor(V1, did)
	check(DecorSystem.slots_used(V1) == total,
		"filling up stops exactly at the slot count (%d/%d)"
			% [DecorSystem.slots_used(V1), total])
	check(DecorSystem.first_free_slot(V1) < 0, "no free slot remains")
	var overflow: String = ""
	for did in buyable:
		if not DecorSystem.owned(V1, did):
			overflow = did
			break
	check(overflow != "", "at least one design could not fit")
	var cash_before: BigNumber = GS.cash
	check(not DecorSystem.buy_decor(V1, overflow), "a full venue refuses another piece")
	check(GS.cash.to_float_approx() == cash_before.to_float_approx(),
		"and a refused purchase takes no money")

func _test_set_progress_survives_the_move(GS: Node) -> void:
	print("-- set completion follows the collection, not the building --")
	_fund(GS)
	var pieces: Array = DL.decor_sets.get("heritage", {}).get("pieces", [])
	check(pieces.size() > 0, "the heritage set has pieces")
	for pid in pieces:
		GS.unlock_decor_design(str(pid))
	var sp: Dictionary = DecorSystem.set_progress("heritage")
	check(bool(sp["complete"]),
		"owning every design completes the set (%d/%d)" % [int(sp["have"]), int(sp["total"])])
	# Now take them all off the floor. The collection is unchanged, so the set is.
	for pid in pieces:
		DecorSystem.remove_decor(V1, str(pid))
		DecorSystem.remove_decor(V2, str(pid))
	var sp2: Dictionary = DecorSystem.set_progress("heritage")
	check(bool(sp2["complete"]),
		"and it stays complete with nothing placed — the bonus is for collecting")

func _test_satisfaction_tracks_placement(GS: Node, EC: Node) -> void:
	print("-- rating counts what is STANDING here, not what is owned --")
	for did in DL.decor.keys():
		DecorSystem.remove_decor(V2, str(did))
	check(DecorSystem.slots_used(V2) == 0, "second venue cleared for the measurement")
	var points_before: float = DecorSystem.venue_decor_points(V2)
	var seats_before: int = DecorSystem.venue_rest_seats(V2)
	var stars_before: float = float(EC.venue_satisfaction(V2)["stars"])
	check(points_before == 0.0, "an empty venue scores no decor points")

	# A bench is the seats case; a chandelier is the spectacle case. Both must be
	# BOUGHT here — a global unlock confers nothing in this building any more.
	_fund(GS)
	check(DecorSystem.buy_decor(V2, "visitor_benches"), "buy a bench run here")
	check(DecorSystem.buy_decor(V2, "crystal_chandelier"), "buy a chandelier here")

	check(DecorSystem.venue_decor_points(V2) > points_before,
		"decor points rose (%.1f -> %.1f)" % [points_before, DecorSystem.venue_decor_points(V2)])
	check(DecorSystem.venue_rest_seats(V2) > seats_before,
		"rest seats rose (%d -> %d)" % [seats_before, DecorSystem.venue_rest_seats(V2)])
	check(float(EC.venue_satisfaction(V2)["stars"]) >= stars_before,
		"and the venue rating did not go backwards")

	# The first venue is still full; its rating must be untouched by V2's edits.
	check(DecorSystem.venue_decor_points(V1) > 0.0,
		"the other venue's own decor score is independent")

func _test_migration_derives_ownership(SS: Node) -> void:
	print("-- a v4 save keeps every design it paid for --")
	var v4 := {
		"venues_state": {
			V1: {"decor": {"0": "oak_bench", "1": "heritage_arch", "2": "lily_pond"}},
			V2: {"decor": {"0": "marble_bust"}},
			"grand_river": {"decor": {}},
		},
	}
	var out: Dictionary = SS.migrate(v4.duplicate(true), 4)
	var owned: Array = out.get("decor_owned", [])
	for did in ["oak_bench", "heritage_arch", "lily_pond", "marble_bust"]:
		check(did in owned, "v4 -> v5 recovered '%s' from where it stood" % did)
	check(owned.size() == 4,
		"and granted nothing extra (%d designs)" % owned.size())
	check((out["venues_state"][V1] as Dictionary)["decor"].size() == 3,
		"placements are left exactly where the player put them")

	# Idempotence: migrating an already-v5 payload must not double up or wipe.
	var again: Dictionary = SS.migrate(out.duplicate(true), 4)
	check((again.get("decor_owned", []) as Array).size() == 4,
		"re-running the migration is a no-op")

	var empty: Dictionary = SS.migrate({"venues_state": {}}, 4)
	check((empty.get("decor_owned", []) as Array).is_empty(),
		"a save that never bought decor migrates to an empty collection")

	print("-- v5 -> v6: what was standing was obviously bought there --")
	var v5 := {
		"decor_owned": ["oak_bench", "marble_bust", "lily_pond"],
		"venues_state": {
			V1: {"decor": {"0": "oak_bench", "1": "lily_pond"}},
			V2: {"decor": {"0": "marble_bust"}},
		},
	}
	var out6: Dictionary = SS.migrate(v5.duplicate(true), 5)
	var b1: Array = (out6["venues_state"][V1] as Dictionary).get("decor_bought", [])
	var b2: Array = (out6["venues_state"][V2] as Dictionary).get("decor_bought", [])
	check("oak_bench" in b1 and "lily_pond" in b1,
		"museum one is credited with what stands in it (%s)" % str(b1))
	check("marble_bust" in b2 and "oak_bench" not in b2,
		"museum two is credited only with ITS own piece (%s)" % str(b2))
	check((out6.get("decor_owned", []) as Array).size() == 3,
		"and the cross-museum record is untouched, so set bonuses survive")
	check(str(SS.SAVE_VERSION) == "6", "SAVE_VERSION advanced to 6")

func _test_round_trip(GS: Node, SS: Node) -> void:
	print("-- the collection survives save/load --")
	var owned_before: Array = (GS.decor_owned as Array).duplicate()
	var placed_before: Dictionary = (GS.venue_state(V2).get("decor", {}) as Dictionary).duplicate()
	check(owned_before.size() > 0, "there is a collection to persist")

	var snap: Dictionary = GS.to_save_dict()
	check(snap.has("decor_owned"), "to_save_dict writes the collection")
	# Round-trip through JSON exactly as SaveSystem does, so this also catches a
	# type that survives in memory but not on disk.
	var wire: Dictionary = JSON.parse_string(JSON.stringify(snap))
	GS.from_save_dict(wire)
	check((GS.decor_owned as Array).size() == owned_before.size(),
		"the collection came back whole (%d)" % (GS.decor_owned as Array).size())
	for did in owned_before:
		check(GS.owns_decor_design(str(did)), "'%s' is still owned after load" % str(did))
	check((GS.venue_state(V2).get("decor", {}) as Dictionary).size() == placed_before.size(),
		"and the second venue's arrangement came back too")

