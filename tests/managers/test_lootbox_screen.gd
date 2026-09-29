extends SceneTree
## Recruitment-case UI regression: timer refreshes state without replacing controls.

var failures := 0
var EventBus: Node
var GameState: Node
var ClockGuard: Node
var _toasts: Array[String] = []

func check(ok: bool, message: String) -> void:
	if ok:
		print("PASS  ", message)
	else:
		failures += 1
		printerr("FAIL  ", message)

func _init() -> void:
	call_deferred("run")

func run() -> void:
	_boot()
	GameState.reset_to_new_game()
	GameState.ready_flag = true
	EventBus.toast_requested.connect(func(message: String) -> void: _toasts.append(message))
	var screen: Control = load("res://scenes/managers/lootbox_screen.tscn").instantiate()
	root.add_child(screen)
	await process_frame

	check(screen._tier_controls.size() == 3, "three stable recruitment tier cards exist")
	var field: Dictionary = screen._tier_controls["field_case"]
	var specialist: Dictionary = screen._tier_controls["specialist_case"]
	var field_card: Control = field["card"]
	var field_open: Button = field["open"]
	var paid_open: Button = specialist["open"]
	var odds: Label = specialist["odds"]
	paid_open.grab_focus()
	await process_frame
	var focused_before: Control = root.gui_get_focus_owner()
	var card_id := field_card.get_instance_id()
	var button_id := paid_open.get_instance_id()

	# Timer-equivalent refresh changes text only, even across a charge countdown.
	GameState.rv_state["free_lootbox"] = {
		"count": 0, "day": Time.get_date_string_from_system(),
		"ready_at": ClockGuard.now() + 3600}
	GameState.gems = 0
	screen._refresh_status()
	await process_frame
	check((screen._tier_controls["field_case"] as Dictionary)["card"].get_instance_id() == card_id,
		"timer refresh keeps tier card identity")
	check((screen._tier_controls["specialist_case"] as Dictionary)["open"].get_instance_id() == button_id,
		"timer refresh keeps purchase-control identity")
	check(root.gui_get_focus_owner() == focused_before,
		"timer refresh preserves keyboard/controller focus")
	check(not field_open.disabled and field_open.text.contains("Recharging"),
		"empty free case remains tappable and states recharge")
	check(not paid_open.disabled and paid_open.text.contains("Need"),
		"unaffordable gem case remains tappable and states its price")
	check(odds.text.begins_with("Published odds:") and odds.text.length() > 20,
		"published odds are visible on each tier card")

	_toasts.clear()
	field_open.pressed.emit()
	check(_toasts == ["No free cases left — recharging"],
		"blocked free-case tap explains recharge")
	_toasts.clear()
	paid_open.pressed.emit()
	check(_toasts == ["Not enough gems"], "blocked gem-case tap explains affordability")

	screen.queue_free()
	await process_frame
	# Let the last button click finish playing: a playback still mixing at
	# quit is reported as a leaked click.ogg under a loaded machine.
	await create_timer(0.8).timeout
	print("DONE failures=", failures)
	quit(0 if failures == 0 else 1)

func _boot() -> void:
	for pair in [["event_bus", "EventBus"], ["data_loader", "DataLoader"],
			["clock_guard", "ClockGuard"], ["analytics", "Analytics"],
			["ad_service", "AdService"], ["iap_service", "IAPService"],
			["game_state", "GameState"], ["save_system", "SaveSystem"],
			["economy", "Economy"]]:
		if not root.has_node(pair[1]):
			var node: Node = load("res://autoload/%s.gd" % pair[0]).new()
			node.name = pair[1]
			root.add_child(node)
	EventBus = root.get_node("EventBus")
	GameState = root.get_node("GameState")
	ClockGuard = root.get_node("ClockGuard")
	root.get_node("Economy").set_process(false)
	root.get_node("SaveSystem").set_process(false)
