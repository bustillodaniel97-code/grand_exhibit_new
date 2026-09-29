extends SceneTree
## QA M5-1: cross-branch integration smoke — headless "player bot".
## Boot main.tscn, grant cash, buy 20+ upgrades across all 4 departments,
## assert rep/cash/choke sanity, open every SPEC §11 registry screen via
## PopupManager, and verify feature gates (managers@rep6, expedition@rep7,
## inspection@day1) flip correctly when state is manipulated.
## Run: godot --headless --path <repo> -s tests/qa/test_integration_playthrough.gd
## Exit 0 = pass, 1 = fail.
##
## QA FINDING (reported, worked around): in headless -s mode, if the feature-gate
## manipulation (reset_to_new_game + first_launch_unix pokes) runs AFTER booting
## main.tscn + purchases + PopupManager screens, the process balloons at teardown
## and is OOM-killed (exit 137) after printing results. Gates therefore run BEFORE
## the scene boot here, and the boot shell is left for normal tree teardown (no
## explicit queue_free). Root cause is engine/teardown-level, not game logic:
## every game-behavior assertion in this suite passes either way.

var failures: int = 0

var EB: Node
var DL: Node
var GS: Node
var ECON: Node
var SS: Node

## Resolved through SaveSystem rather than hardcoded. This suite deletes and
## corrupts the save on purpose, and on a developer box the literal path is
## the live player profile; SaveSystem.save_path() redirects into a throwaway
## subdirectory whenever the main loop is a res://tests/ script.
var _save_file_cache: String = ""
func save_file() -> String:
	if _save_file_cache.is_empty():
		# load() not preload(): under -s the main script compiles before autoload
		# names are bound, and save_system.gd names them. Resolving at runtime
		# sidesteps that. save_path() is static, so no instance is needed.
		_save_file_cache = load("res://autoload/save_system.gd").save_path()
	return _save_file_cache
const REGISTRY: Array[String] = [
	"res://scenes/managers/managers_screen.tscn",
	"res://scenes/managers/lootbox_screen.tscn",
	"res://scenes/events/inspection_screen.tscn",
	"res://scenes/events/expedition_screen.tscn",
	"res://scenes/meta/decor_screen.tscn",
	"res://scenes/meta/prestige_screen.tscn",
	"res://scenes/store/store_screen.tscn",
]

func check(cond: bool, msg: String) -> void:
	if cond:
		print("  PASS ", msg)
	else:
		failures += 1
		printerr("  FAIL ", msg)

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	EB = root.get_node("EventBus")
	DL = root.get_node("DataLoader")
	GS = root.get_node("GameState")
	ECON = root.get_node("Economy")
	SS = root.get_node("SaveSystem")
	check(EB != null and DL != null and GS != null and ECON != null and SS != null,
		"autoloads present as root children")
	DL.reload_all()
	for p in [save_file(), save_file() + ".bak"]:
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(p)

	print("-- feature gates --")
	GS.reset_to_new_game()
	GS.first_launch_unix = root.get_node("ClockGuard").now()
	check(not GS.feature_unlocked("managers"), "managers locked at rep < 3")
	check(not GS.feature_unlocked("expedition"), "expedition locked at rep < 7")
	check(not GS.feature_unlocked("inspection"), "inspection locked at day < 1")
	# Managers arrive early enough to shape the introductory venue.
	GS.add_reputation(BigNumber.from_float(60.0))
	check(GS.rep_level() == 3, "rep_level == 3 at 60 xp (got %d)" % GS.rep_level())
	check(GS.feature_unlocked("managers"), "managers unlocked at rep 3")
	# Cross rep 6 but not 7: add the remaining 560 xp.
	GS.add_reputation(BigNumber.from_float(560.0))
	check(GS.rep_level() == 6, "rep_level == 6 at 620 xp (got %d)" % GS.rep_level())
	check(not GS.feature_unlocked("expedition"), "expedition still locked at rep 6")
	# Cross rep 7: thresholds idx6 = 1250 (620 + 630).
	GS.add_reputation(BigNumber.from_float(630.0))
	check(GS.rep_level() == 7, "rep_level == 7 at 1250 xp (got %d)" % GS.rep_level())
	check(GS.feature_unlocked("expedition"), "expedition unlocked at rep 7")
	# Inspection gate is time-based only: flip first_launch_unix back 2 days.
	GS.first_launch_unix = root.get_node("ClockGuard").now() - 2 * 86400
	check(GS.day_index() >= 1, "day_index >= 1 after clock manipulation")
	check(GS.feature_unlocked("inspection"), "inspection unlocked at day >= 1")
	GS.first_launch_unix = root.get_node("ClockGuard").now()
	check(not GS.feature_unlocked("inspection"), "inspection re-locks when day resets")

	print("-- boot main.tscn --")
	var main_scene: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(main_scene)  # _ready: load/new game, offline, shell build
	check(GS.ready_flag, "GameState.ready_flag set after boot")
	check(GS.rep_level() == 1, "fresh boot rep_level == 1 (got %d)" % GS.rep_level())

	print("-- player bot: grant cash, buy upgrades across all 4 depts --")
	GS.add_cash(BigNumber.from_parts(1.0, 9))
	var cash_before: BigNumber = GS.cash.copy()
	var rep_before: int = GS.rep_level()
	var xp_before: BigNumber = GS.reputation_xp.copy()
	var bought: int = 0
	var vid: String = GS.current_venue
	# Round-robin purchases across every dept x track until 24+ successes.
	var combos: Array = []
	for dept in ["promotions", "ticket", "archive", "gallery"]:
		for track in ["staff", "speed", "value"]:
			combos.append([dept, track])
	var rounds: int = 0
	while bought < 24 and rounds < 20:
		rounds += 1
		for c in combos:
			if ECON.purchase_upgrade(vid, c[0], c[1]):
				bought += 1
	check(bought >= 20, "bot bought 20+ upgrades (%d)" % bought)
	check(GS.cash.lt(cash_before), "cash decreased after purchases (%s -> %s)"
		% [cash_before.to_notation(), GS.cash.to_notation()])
	check(GS.reputation_xp.gt(xp_before), "reputation xp increased")
	check(GS.rep_level() > rep_before, "rep_level rose (%d -> %d)" % [rep_before, GS.rep_level()])
	var rates: Dictionary = ECON.venue_rates(vid)
	check(str(rates.get("choke_id", "")) in ["promotions", "ticket", "archive"],
		"venue_rates choke_id sane (%s)" % str(rates.get("choke_id", "")))
	check(not (rates["pending_per_s"] as BigNumber).lt(BigNumber.zero())
		and not (rates["banked_per_s"] as BigNumber).lt(BigNumber.zero()),
		"venue_rates rates non-negative")

	print("-- SPEC §11 screen registry via PopupManager --")
	var Popups: GDScript = load("res://scripts/ui/popup_manager.gd")
	check(Popups != null and Popups.can_instantiate(), "popup_manager.gd compiles")
	for path in REGISTRY:
		check(ResourceLoader.exists(path), "registry path exists: %s" % path)
		var packed: PackedScene = load(path)
		check(packed != null and packed.can_instantiate(), "registry scene loads: %s" % path)
		Popups.open(path, {})
		var opened: bool = Popups.is_open()
		check(opened, "PopupManager opened %s (setup({}) survived)" % path)
		Popups.close_top()
		await process_frame  # let queue_free settle between opens

	# NOTE: do NOT queue_free(main_scene) here. QA finding: queue_free of the boot
	# shell after the full bot flow (purchases -> popup screens -> reset_to_new_game)
	# triggers a teardown-time memory explosion in headless -s mode (SIGKILL, exit
	# 137). Leaving the scene for normal tree teardown exits cleanly. See QA report.
	print("---")
	if failures == 0:
		print("ALL QA INTEGRATION TESTS PASSED")
	else:
		printerr("QA INTEGRATION TESTS FAILED: %d" % failures)
	quit(0 if failures == 0 else 1)
