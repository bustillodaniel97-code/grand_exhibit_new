extends SceneTree
## test_back_policy.gd — UI-02 central Back policy integration.
##
## One Back press dismisses exactly one layer regardless of notification
## propagation order: top popup -> department sheet -> stay in game (no quit).
## Before the shared last_back_close_frame guard, order reversal could dismiss
## both popup and sheet on a single press.

var failures := 0

func check(ok: bool, label: String) -> void:
	if ok:
		print("PASS ", label)
	else:
		failures += 1
		printerr("FAIL ", label)

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	if not OS.has_environment("GRAND_EXHIBIT_TEST_RUN"):
		printerr("REFUSED: requires GRAND_EXHIBIT_TEST_RUN isolation")
		quit(2)
		return
	var gs = root.get_node("GameState")
	gs.reset_to_new_game()
	gs.ready_flag = true
	root.get_node("SaveSystem").set_process(false)
	root.size = Vector2i(720, 1280)
	root.content_scale_size = Vector2i(720, 1280)
	var venue = load("res://scenes/venue/venue_view.tscn").instantiate()
	root.add_child(venue)
	await process_frame
	await process_frame
	var layer = load("res://scenes/ui/popup_layer.tscn").instantiate()
	root.add_child(layer)
	await process_frame
	var popup = load("res://scripts/ui/popup_manager.gd")
	# Open the department sheet first, then a popup over it.
	venue._open_sheet("ticket")
	await create_timer(0.3).timeout
	check(venue._sheet.visible, "department sheet opens")
	popup.open("res://scenes/store/store_screen.tscn", {})
	await create_timer(0.3).timeout
	check(popup.is_open(), "popup opens over the sheet")
	# First Back: popup closes, sheet stays (exactly one dismiss).
	root.propagate_notification(Node.NOTIFICATION_WM_GO_BACK_REQUEST)
	await process_frame
	await process_frame
	check(not popup.is_open(), "first Back dismisses the popup")
	check(venue._sheet.visible, "first Back leaves the sheet open (no double-dismiss)")
	# Second Back: sheet closes, game stays (no quit to test headless).
	root.propagate_notification(Node.NOTIFICATION_WM_GO_BACK_REQUEST)
	await process_frame
	await create_timer(0.3).timeout
	check(not venue._sheet.visible, "second Back closes the sheet")
	# Third Back with nothing open: stays in game, no popup, no error.
	root.propagate_notification(Node.NOTIFICATION_WM_GO_BACK_REQUEST)
	await process_frame
	check(not popup.is_open() and not venue._sheet.visible, "Back with nothing open stays in game")
	layer.queue_free()
	venue.queue_free()
	await process_frame
	print("BACK_POLICY_DONE failures=", failures)
	quit(0 if failures == 0 else 1)
