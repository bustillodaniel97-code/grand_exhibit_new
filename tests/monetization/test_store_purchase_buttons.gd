extends SceneTree
## Focused interaction regression for one product rendered in hero and shelf cards.
## No purchase backend is called; accepted/rejected actions are deterministic fakes.

var failures := 0
var EventBus: Node
var DataLoader: Node
var GameState: Node
var _accepted_calls := 0
var _rejected_calls := 0
var _toasts: Array[String] = []

func check(ok: bool, message: String) -> void:
	if ok:
		print("  PASS ", message)
	else:
		failures += 1
		printerr("  FAIL ", message)

func _init() -> void:
	call_deferred("run")

func run() -> void:
	_boot()
	GameState.reset_to_new_game()
	GameState.ready_flag = true
	EventBus.toast_requested.connect(func(message: String) -> void: _toasts.append(message))
	var screen: Control = load("res://scenes/store/store_screen.tscn").instantiate()
	root.add_child(screen)
	await process_frame

	# Use isolated controls so catalogue/offer selection cannot alter which product
	# happens to be duplicated by today's data. The lower shelf control is tapped.
	var hero: Button = screen._buy_button("gems_pouch", "$0.99", Color.WHITE, 64)
	var shelf: Button = screen._buy_button("gems_pouch", "$0.99", Color.WHITE, 56)
	screen._on_buy_pressed("gems_pouch", _accept, shelf)
	check(_accepted_calls == 1, "lower duplicate invokes the purchase action exactly once")
	check(hero.disabled and shelf.disabled, "hero and lower duplicate both block rapid repeat")
	check(hero.text == "Purchasing…" and shelf.text == "Purchasing…",
		"hero and lower duplicate show the same pending state")
	screen._on_buy_pressed("gems_pouch", _accept, hero)
	check(_accepted_calls == 1, "pending product rejects a second control before backend call")
	check(_toasts.size() > 0 and _toasts.back() == "Purchase already in progress",
		"repeat tap receives explicit feedback")

	# A delayed backend failure is represented by the existing toast signal after
	# no catalogue request remains in flight.
	EventBus.toast_requested.emit("Purchase failed")
	check(not hero.disabled and not shelf.disabled, "failure restores every duplicate")
	check(hero.text == "$0.99" and shelf.text == "$0.99", "failure restores each price")

	# Immediate rejection already owns its feedback and must never enter pending.
	_toasts.clear()
	screen._on_buy_pressed("gems_pouch", _reject, shelf)
	check(_rejected_calls == 1 and not shelf.disabled and not hero.disabled,
		"immediate rejection leaves both controls available")
	check(_toasts == ["Unavailable"], "immediate rejection feedback is preserved")

	# Completion rebuilds the real Store and clears transient button identities.
	screen._on_buy_pressed("gems_pouch", _accept, shelf)
	screen._on_iap_completed("gems_pouch")
	await process_frame
	check(not screen._pending_products.has("gems_pouch"), "completion clears pending state")
	var rebuilt: Array = screen._buttons_for("gems_pouch")
	var recovered := not rebuilt.is_empty()
	for button: Button in rebuilt:
		recovered = recovered and not button.disabled and button.text != "Purchasing…"
	check(recovered, "completion rebuild leaves visible product controls recovered")

	# The fake controls were never parented; release them explicitly.
	hero.free()
	shelf.free()
	var sound := root.get_node_or_null("UiKitSfx") as AudioStreamPlayer
	if sound != null:
		sound.stop()
		sound.stream = null
		# Let the audio server release the Ogg playback before headless shutdown.
		await create_timer(.25).timeout
	screen.queue_free()
	await process_frame
	await process_frame
	print("---")
	print("STORE PURCHASE BUTTON TESTS PASSED" if failures == 0 else
		"STORE PURCHASE BUTTON TESTS FAILED: %d" % failures)
	quit(0 if failures == 0 else 1)

func _accept() -> bool:
	_accepted_calls += 1
	return true

func _reject() -> bool:
	_rejected_calls += 1
	EventBus.toast_requested.emit("Unavailable")
	return false

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
	DataLoader = root.get_node("DataLoader")
	GameState = root.get_node("GameState")
	root.get_node("Economy").set_process(false)
	root.get_node("SaveSystem").set_process(false)
