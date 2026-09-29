extends SceneTree
## Isolated popup-shell QA: stack cancellation, focus restoration and portrait fit.

var failures := 0
var opener_activations := 0

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, label: String) -> void:
	if not ok:
		failures += 1
	print("PASS " if ok else "FAIL ", label)

func settle() -> void:
	await create_timer(0.28).timeout

func top_holder(layer: CanvasLayer) -> Control:
	return layer.get_child(layer.get_child_count() - 1) as Control

func card_fits(card: Control) -> bool:
	var rect := card.get_global_rect()
	var bounds := Rect2(Vector2.ZERO, Vector2(root.size))
	return bounds.encloses(rect.grow(1.0))

func cancel_top() -> void:
	var event := InputEventAction.new()
	event.action = "ui_cancel"
	event.pressed = true
	root.push_input(event, true)
	await process_frame

func escape_top() -> void:
	var event := InputEventKey.new()
	event.keycode = KEY_ESCAPE
	event.pressed = true
	root.push_input(event, true)
	await process_frame

func tab_top(reverse: bool = false) -> void:
	var event := InputEventKey.new()
	event.keycode = KEY_TAB
	event.shift_pressed = reverse
	event.pressed = true
	root.push_input(event, true)
	await process_frame

func activate_focused() -> void:
	var event := InputEventKey.new()
	event.keycode = KEY_ENTER
	event.pressed = true
	root.push_input(event, true)
	await process_frame

func focus_is_in(holder: Control) -> bool:
	var focused := root.gui_get_focus_owner()
	return focused != null and holder.is_ancestor_of(focused)

func _on_opener_pressed() -> void:
	opener_activations += 1

func run() -> void:
	if not OS.has_environment("GRAND_EXHIBIT_TEST_RUN"):
		quit(2)
		return
	root.size = Vector2i(720, 1280)
	root.content_scale_size = Vector2i(720, 1280)
	var opener := Button.new()
	opener.text = "Open menu"
	opener.pressed.connect(_on_opener_pressed)
	root.add_child(opener)
	opener.grab_focus()
	var layer := load("res://scenes/ui/popup_layer.tscn").instantiate() as CanvasLayer
	root.add_child(layer)
	var popup := load("res://scripts/ui/popup_manager.gd")

	popup.open("res://scenes/ui/welcome_back.tscn", {})
	await settle()
	var first := top_holder(layer)
	var first_close := first.get_meta("popup_close", null) as Button
	var first_card := first.get_meta("popup_card", null) as PanelContainer
	var context := first.get_meta("popup_context", null) as Label
	var expected_name: String = str(root.get_node("DataLoader").get_venue(
		root.get_node("GameState").current_venue).get("name", "Grand Exhibit"))
	check(first_close != null and first_close.has_focus(), "Opening focuses the visible Close affordance")
	check(context != null and context.text == expected_name, "Header names the current museum")
	check(context != null and context.size.y >= 20 and context.is_visible_in_tree(),
		"Museum name has a visible text line rather than a clipped 1px row")
	check(card_fits(first_card), "Card fits 720x1280 viewport")
	opener.grab_focus()
	await tab_top()
	check(first_close.has_focus(), "Tab recaptures focus from an underlying control")
	for _i in range(12):
		await tab_top()
		check(focus_is_in(first), "Tab focus remains inside the top modal")
	for _i in range(12):
		await tab_top(true)
		check(focus_is_in(first), "Shift-Tab focus remains inside the top modal")
	first_close.grab_focus()
	await activate_focused()
	check(opener_activations == 0 and focus_is_in(first), "Enter cannot activate an underlying control while modal")
	popup.close_top()
	await process_frame
	popup.open("res://scenes/ui/welcome_back.tscn", {})
	await settle()
	first = top_holder(layer)
	first_close = first.get_meta("popup_close", null) as Button
	first_card = first.get_meta("popup_card", null) as PanelContainer

	root.size = Vector2i(720, 1000)
	root.content_scale_size = Vector2i(720, 1000)
	await process_frame
	check(card_fits(first_card), "Resize keeps the existing card inside 720x1000")
	root.size = Vector2i(720, 500)
	root.content_scale_size = Vector2i(720, 500)
	await process_frame
	check(card_fits(first_card), "Very short viewport never forces a 560px card")
	root.size = Vector2i(720, 1000)
	root.content_scale_size = Vector2i(720, 1000)
	await process_frame

	popup.open("res://scenes/ui/welcome_back.tscn", {})
	await settle()
	var second := top_holder(layer)
	var second_close := second.get_meta("popup_close", null) as Button
	check(second_close != null and second_close.text == "Back", "Nested popup labels its top dismissal as Back")
	await escape_top()
	check(popup.is_open() and layer.get_child_count() == 1, "Escape dismisses only the top popup")
	check(first_close.has_focus(), "Closing nested popup restores prior popup focus")
	await cancel_top()
	check(not popup.is_open() and opener.has_focus(), "ui_cancel closes final popup and restores underlying focus")

	var temporary_opener:=Button.new();root.add_child(temporary_opener);temporary_opener.grab_focus()
	popup.open("res://scenes/ui/welcome_back.tscn", {})
	await settle()
	temporary_opener.queue_free();await process_frame
	popup.close_top();await process_frame
	check(not popup.is_open(), "Closing tolerates an opener replaced by a purchase refresh")
	layer.queue_free()
	opener.queue_free()
	await process_frame
	print("POPUP_SHELL_DONE failures=", failures)
	quit(0 if failures == 0 else 1)
