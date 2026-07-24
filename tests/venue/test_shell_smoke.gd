extends SceneTree
## Venue-UI shell smoke test (SPEC §12).
## Bootstraps the 9 autoloads as named root children (SPEC §3 order; reused if the
## project already registered them), then boots scenes/main.tscn and checks the
## shell + a purchase + manual collect.
## NOTE: SceneTree scripts cannot reference autoload identifiers directly (compile
## error), so singletons are fetched via root.get_node and used dynamically.
## Run: godot --headless --path <repo> -s tests/venue/test_shell_smoke.gd  (exit 0 pass)

var _frames: int = 0
var _done: bool = false
var _fail: int = 0

func check(cond: bool, msg: String) -> void:
	if cond:
		print("PASS: ", msg)
	else:
		_fail += 1
		printerr("FAIL: ", msg)

func _initialize() -> void:
	var autoloads := [
		["EventBus", "res://autoload/event_bus.gd"],
		["DataLoader", "res://autoload/data_loader.gd"],
		["ClockGuard", "res://autoload/clock_guard.gd"],
		["Analytics", "res://autoload/analytics.gd"],
		["AdService", "res://autoload/ad_service.gd"],
		["IAPService", "res://autoload/iap_service.gd"],
		["GameState", "res://autoload/game_state.gd"],
		["SaveSystem", "res://autoload/save_system.gd"],
		["Economy", "res://autoload/economy.gd"],
	]
	for pair in autoloads:
		if root.has_node(pair[0]):
			continue  # already registered as a real autoload
		var n: Node = (load(pair[1]) as GDScript).new()
		n.name = pair[0]
		root.add_child(n)

	var gs: Node = root.get_node("GameState")
	root.get_node("DataLoader").reload_all()
	gs.reset_to_new_game()
	gs.ready_flag = true

	var main: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(main)

func _process(_delta: float) -> bool:
	if _done:
		return true
	_frames += 1
	if _frames < 3:
		return false
	_done = true
	_run_checks()
	quit(0 if _fail == 0 else 1)
	return true

func _run_checks() -> void:
	var gs: Node = root.get_node("GameState")
	var economy: Node = root.get_node("Economy")

	var main := root.get_node_or_null("Main")
	check(main != null, "main scene instanced as 'Main'")
	if main == null:
		return
	check(main.find_child("HUD", true, false) != null, "HUD node exists")
	check(main.find_child("VenueView", true, false) != null, "VenueView node exists")
	check(main.find_child("BottomNav", true, false) != null, "BottomNav node exists")
	check(main.find_child("PopupLayer", true, false) != null, "PopupLayer node exists")

	gs.add_cash(BigNumber.from_float(100000.0))
	var bought: bool = economy.purchase_upgrade("whispering_pines", "ticket", "speed")
	check(bought, "purchase_upgrade(whispering_pines, ticket, speed) succeeds with cash")
	check(int(gs.dept_level("whispering_pines", "ticket", "speed")) == 2,
		"ticket speed level is 2 after purchase")

	var got: Variant = economy.manual_collect("whispering_pines")
	check(got is BigNumber and got.cmp(BigNumber.zero()) >= 0, "manual_collect returns >= 0")
