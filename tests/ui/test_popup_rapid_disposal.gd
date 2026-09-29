extends SceneTree
## test_popup_rapid_disposal.gd — UI-01 regression for rapid popup disposal.
##
## The audit probe opened/closed eight screen types three times before yielding
## and logged 21 `ERROR: Error calling deferred method ... _focus_opened_popup`
## engine errors while exiting 0. PopupManager deferred typed Control/Button
## args; freed objects failed argument conversion before the guard ran.
## This test replays that timing. Assertions alone pass on the old code — the
## regression is enforced by run_tests.sh failing on unexpected ERROR lines.
## With the Variant/validated fix it emits no engine errors.

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
	root.size = Vector2i(720, 1280)
	root.content_scale_size = Vector2i(720, 1280)
	var opener := Button.new()
	opener.text = "Opener"
	root.add_child(opener)
	opener.grab_focus()
	var layer := load("res://scenes/ui/popup_layer.tscn").instantiate() as CanvasLayer
	root.add_child(layer)
	var popup := load("res://scripts/ui/popup_manager.gd")
	var screens: Array[String] = [
		"store/store_screen",
		"managers/managers_screen",
		"managers/lootbox_screen",
		"meta/decor_screen",
		"meta/prestige_screen",
		"meta/statistics_screen",
		"events/expedition_screen",
		"events/inspection_screen",
	]
	# Abrupt disposal: open+close three times before yielding, per screen.
	# On the old typed-deferred implementation each stale focus callback
	# errors in the message queue; the fixed Variant guard no-ops instead.
	for screen in screens:
		for i in 3:
			popup.open("res://scenes/" + screen + ".tscn", {})
			popup.close_top()
		await create_timer(0.3).timeout
		check(not popup.is_open(), "rapid open/close leaves no popup for " + screen)

	# Same-frame open/close/reopen keeps a single live modal with focus.
	popup.open("res://scenes/store/store_screen.tscn", {})
	popup.close_top()
	popup.open("res://scenes/store/store_screen.tscn", {})
	await create_timer(0.3).timeout
	check(popup.is_open(), "same-frame reopen leaves one popup open")
	var holder: Control = layer.get_child(layer.get_child_count() - 1) as Control
	var close_btn: Button = holder.get_meta("popup_close", null) as Button
	check(close_btn != null and close_btn.has_focus(), "reopened popup focuses its Close affordance")
	popup.close_top()
	await process_frame

	# Nested closure restores the prior popup's focus, then the opener.
	popup.open("res://scenes/store/store_screen.tscn", {})
	await create_timer(0.28).timeout
	var first: Control = layer.get_child(layer.get_child_count() - 1) as Control
	var first_close: Button = first.get_meta("popup_close", null) as Button
	popup.open("res://scenes/meta/decor_screen.tscn", {})
	await create_timer(0.28).timeout
	check(layer.get_child_count() == 2, "nested popup stacks")
	popup.close_top()
	await create_timer(0.28).timeout
	check(popup.is_open() and layer.get_child_count() == 1, "closing nested leaves the first popup")
	check(first_close != null and first_close.has_focus(), "nested close restores prior popup focus")
	# Repeated input on an empty stack is a no-op, not an error.
	popup.close_top()
	await process_frame
	popup.close_top()
	await process_frame
	check(not popup.is_open(), "repeated close on empty stack stays closed")

	# Back notification dismisses exactly one screen per press.
	popup.open("res://scenes/store/store_screen.tscn", {})
	await create_timer(0.28).timeout
	popup.open("res://scenes/meta/decor_screen.tscn", {})
	await create_timer(0.28).timeout
	root.propagate_notification(Node.NOTIFICATION_WM_GO_BACK_REQUEST)
	await process_frame
	check(popup.is_open() and layer.get_child_count() == 1, "Back dismisses only the top popup")
	popup.close_top()
	await process_frame

	layer.queue_free()
	opener.queue_free()
	await process_frame
	print("POPUP_RAPID_DISPOSAL_DONE failures=", failures)
	quit(0 if failures == 0 else 1)
