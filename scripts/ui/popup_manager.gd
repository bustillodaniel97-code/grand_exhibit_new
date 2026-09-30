extends CanvasLayer
## PopupManager — dim overlay + centered card popups (SPEC §9).
## Instantiated once via scenes/ui/popup_layer.tscn (added by scenes/main.gd).
## Access from venue-ui branch files:
##   const Popup = preload("res://scripts/ui/popup_manager.gd")
##   Popup.open(path, payload) / Popup.close_top()
## All cross-branch screens are opened by path string only (SPEC §11 SCREEN REGISTRY).

const UI := preload("res://scripts/ui/ui_kit.gd")
const Chrome := preload("res://scripts/ui/museum_chrome.gd")

static var _instance: CanvasLayer = null
## Last frame a Back press closed a popup. Shared across layers: venue_view
## checks this so one Back press can never dismiss both the popup and the
## department sheet regardless of notification propagation order.
static var last_back_close_frame: int = -1

var _stack: Array[Control] = []
## Frame the last Android Back notification closed a popup. A Back press can
## surface as both NOTIFICATION_WM_GO_BACK_REQUEST and ui_cancel; without this
## guard one press would dismiss two stacked screens.
var _back_handled_frame: int = -1

func _ready() -> void:
	layer = 10
	_instance = self
	# Central mobile Back policy: Back dismisses UI, it never quits the app
	# from under a popup/sheet. Main-screen Back stays in the game (no-op)
	# rather than exiting unexpectedly; venue_view owns the sheet step.
	var tree := get_tree()
	if tree != null and tree.has_method("get"):
		tree.set("quit_on_go_back", false)
	get_viewport().size_changed.connect(_resize_cards)

func _exit_tree() -> void:
	if _instance == self:
		_instance = null

static func is_open() -> bool:
	return _instance != null and not _instance._stack.is_empty()

static func open(path: String, payload: Dictionary = {}) -> void:
	if _instance == null:
		push_warning("PopupManager.open called before popup_layer is in the tree")
		return
	_instance._open(path, payload)

static func close_top() -> void:
	if _instance != null:
		_instance._close_top()

func _open(path: String, payload: Dictionary) -> void:
	if not ResourceLoader.exists(path):
		EventBus.toast_requested.emit("Coming soon")
		return
	var packed: PackedScene = load(path)
	if packed == null:
		EventBus.toast_requested.emit("Coming soon")
		return

	var prior_focus := _focus_owner()
	var holder := Control.new()
	holder.set_anchors_preset(Control.PRESET_FULL_RECT)
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Parent the holder BEFORE building the card. The card's height depends on the
	# safe-area inset, and UI.safe_area_insets() takes a Control and early-outs to
	# all-zeros for anything not yet in the tree — so measuring off a detached node
	# silently disabled the inset entirely. (Passing `self` instead is not the fix:
	# PopupManager is a CanvasLayer, not a Control, and that type mismatch errors
	# out mid-open and leaves the popup half-built.)
	add_child(holder)

	var dim := ColorRect.new()
	dim.color = Color(0.06, 0.09, 0.11, 0.42)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP  # swallow taps on the dim
	holder.add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(center)

	var card := PanelContainer.new()
	# The card is measured from the live viewport rather than a fixed design size.
	# Re-running this calculation on resize keeps the sheet in the visible frame
	# for both tall and short portrait layouts.
	_apply_card_size(card, dim)
	card.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	card.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	# A soft sheet: the page colour, a wide radius and one deep, diffuse shadow.
	var frame := Chrome.panel(20, Chrome.BG)
	frame.set_content_margin_all(0)
	frame.set_border_width_all(0)
	frame.shadow_size = 28
	frame.shadow_color = Color(0.03, 0.06, 0.08, 0.22)
	frame.shadow_offset = Vector2(0, 10)
	card.add_theme_stylebox_override("panel", frame)
	card.clip_contents = true
	center.add_child(card)
	holder.set_meta("popup_card", card)
	if prior_focus != null:
		holder.set_meta("restore_focus", prior_focus)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 0)
	card.add_child(vbox)

	# This is a real museum-context header, not an empty band with a red X. It
	# remains outside content so existing screen headers never collide with it.
	var bar := PanelContainer.new()
	bar.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	var top_row := HBoxContainer.new()
	top_row.add_theme_constant_override("separation", 8)
	var pad := MarginContainer.new()
	pad.add_theme_constant_override("margin_left", 22)
	pad.add_theme_constant_override("margin_right", 12)
	pad.add_theme_constant_override("margin_top", 10)
	pad.add_theme_constant_override("margin_bottom", 0)
	pad.add_child(top_row)
	bar.add_child(pad)
	var heading := VBoxContainer.new()
	heading.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	heading.alignment = BoxContainer.ALIGNMENT_CENTER
	heading.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var context := UI.make_label(_museum_name(), 14, Chrome.DIM)
	# Wrapped, clipped labels can report a 1px minimum height in Godot 4.4.
	# Reserve a readable line; long museum names elide within the available width.
	context.custom_minimum_size.y = 20
	context.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	context.clip_text = true
	context.mouse_filter = Control.MOUSE_FILTER_IGNORE
	heading.add_child(context)
	top_row.add_child(heading)
	var x_btn := Button.new()
	x_btn.text = "Close" if _stack.is_empty() else "Back"
	x_btn.icon = UI.icon_texture("cross", 14)
	x_btn.expand_icon = false
	x_btn.custom_minimum_size = Vector2(88, UI.TOUCH_MIN - 4)
	x_btn.add_theme_font_override("font", UI.font())
	x_btn.add_theme_font_size_override("font_size", 15)
	x_btn.add_theme_constant_override("h_separation", 6)
	Chrome.button(x_btn, false, 16)
	x_btn.tooltip_text = "Close this screen"
	x_btn.pressed.connect(close_top)
	top_row.add_child(x_btn)
	vbox.add_child(bar)

	var body := MarginContainer.new()
	body.add_theme_constant_override("margin_left", 4)
	body.add_theme_constant_override("margin_right", 4)
	body.add_theme_constant_override("margin_top", 6)
	body.add_theme_constant_override("margin_bottom", 6)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(body)

	var content: Node = packed.instantiate()
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(content)

	_stack.append(holder)
	holder.set_meta("popup_close", x_btn)
	holder.set_meta("popup_context", context)
	if content.has_method("setup"):
		content.setup(payload)
	_play_open(card, dim)
	call_deferred("_focus_opened_popup", holder, x_btn)

## Escape / ui_cancel belongs to the uppermost modal only. The dim remains a
## shield rather than a blanket close target because several popup screens can
## represent a consequential choice.
## Android Back (NOTIFICATION_WM_GO_BACK_REQUEST) follows the same single-step
## policy: top popup -> department sheet (owned by venue_view) -> stay in game.
## quit_on_go_back is disabled in _ready so Back never quits from under UI.
func _notification(what: int) -> void:
	if what == Node.NOTIFICATION_WM_GO_BACK_REQUEST and not _stack.is_empty():
		_close_top()
		_back_handled_frame = Engine.get_process_frames()
		last_back_close_frame = _back_handled_frame

func _input(event: InputEvent) -> void:
	if _stack.is_empty() or (event is InputEventKey and event.echo):
		return
	if event.is_action_pressed("ui_cancel"):
		# A phone Back press may arrive as both the back notification and
		# ui_cancel; the notification already dismissed one screen this frame.
		if Engine.get_process_frames() == _back_handled_frame:
			return
		_close_top()
		get_viewport().set_input_as_handled()
		return
	var direction: int = 0
	if event.is_action_pressed("ui_focus_next"):
		direction = 1
	elif event.is_action_pressed("ui_focus_prev"):
		direction = -1
	elif event is InputEventKey and event.keycode == KEY_TAB:
		direction = -1 if event.shift_pressed else 1
	if direction != 0:
		_cycle_modal_focus(direction)
		get_viewport().set_input_as_handled()

func _apply_card_size(card: PanelContainer, anchor: Control) -> void:
	if card == null or anchor == null:
		return
	var vis: Vector2 = get_viewport().get_visible_rect().size
	var inset: Dictionary = UI.safe_area_insets(anchor)
	var available_width := maxf(0.0, vis.x - 2.0 * float(UI.GUTTER) \
		- float(inset["left"]) - float(inset["right"]))
	var available_height := maxf(0.0, vis.y - 2.0 * float(UI.GUTTER) \
		- float(inset["top"]) - float(inset["bottom"]))
	var min_height := minf(560.0, available_height)
	var max_height := minf(1180.0, available_height)
	card.custom_minimum_size = Vector2(
		minf(available_width, 700.0),
		clampf(available_height - 188.0, min_height, max_height))

func _resize_cards() -> void:
	for holder in _stack:
		if not is_instance_valid(holder):
			continue
		var card := holder.get_meta("popup_card", null) as PanelContainer
		var dim := holder.get_child(0, false) as Control if holder.get_child_count() > 0 else null
		_apply_card_size(card, dim)

func _focus_owner() -> Control:
	var focused := get_viewport().gui_get_focus_owner()
	return focused if focused != null and is_instance_valid(focused) and focused.is_inside_tree() else null

func _focus_opened_popup(holder: Variant, close_button: Variant) -> void:
	# Deferred with Variant (not typed Control/Button): when a popup is closed
	# in the same frame it opens, the queued args may be freed before this runs.
	# Typed parameters fail argument conversion in the message queue before any
	# guard here can execute (21 such ERRORs in the rapid-disposal probe), so
	# validate untyped and no-op on stale callbacks.
	if holder == null or close_button == null:
		return
	if not (holder is Control) or not (close_button is Button):
		return
	if not is_instance_valid(holder) or not is_instance_valid(close_button):
		return
	var holder_ctl := holder as Control
	var button := close_button as Button
	if not holder_ctl.is_inside_tree() or not button.is_inside_tree():
		return
	if _stack.is_empty() or _stack.back() != holder_ctl:
		return
	button.grab_focus()

func _museum_name() -> String:
	var venue: Dictionary = DataLoader.get_venue(GameState.current_venue)
	var venue_name: String = str(venue.get("name", "Grand Exhibit")).strip_edges()
	return venue_name if not venue_name.is_empty() else "Grand Exhibit"

func _cycle_modal_focus(direction: int) -> void:
	if _stack.is_empty():
		return
	var holder: Control = _stack.back()
	var targets: Array[Control] = []
	_collect_focus_targets(holder, targets)
	if targets.is_empty():
		return
	var focused: Control = _focus_owner()
	var index: int = targets.find(focused)
	if index < 0:
		index = -1 if direction > 0 else 0
	var next_index: int = posmod(index + direction, targets.size())
	targets[next_index].grab_focus()

func _collect_focus_targets(node: Node, targets: Array[Control]) -> void:
	for child in node.get_children():
		if child is Control:
			var control: Control = child as Control
			if control.is_visible_in_tree() and control.focus_mode != Control.FOCUS_NONE \
					and not (control is BaseButton and (control as BaseButton).disabled):
				targets.append(control)
		_collect_focus_targets(child, targets)

## Sheet rises and fades in. Cheap, and the absence of it is one of the loudest
## "unfinished" tells on a mobile game.
func _play_open(card: Control, dim: ColorRect) -> void:
	card.pivot_offset = card.custom_minimum_size * 0.5
	card.scale = Vector2(0.94, 0.94)
	card.modulate.a = 0.0
	dim.color.a = 0.0
	var tw := card.create_tween()
	tw.set_parallel(true)
	tw.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(card, "scale", Vector2.ONE, 0.18)
	tw.tween_property(card, "modulate:a", 1.0, 0.14)
	tw.tween_property(dim, "color:a", 0.55, 0.14)
	# Remembered so a popup closed while its open animation is still running
	# (venue switch inside the completion screen does exactly this) cannot keep
	# stepping against nodes that are leaving the tree - the engine reports
	# `can_process` on a detached node as an ERROR on device.
	card.set_meta("open_tween", tw)

func _close_top() -> void:
	if _stack.is_empty():
		return
	var holder: Control = _stack.pop_back()
	var card: Control = holder.get_meta("popup_card", null) as Control
	if card != null and card.has_meta("open_tween"):
		var tw: Variant = card.get_meta("open_tween")
		if tw is Tween and (tw as Tween).is_valid():
			(tw as Tween).kill()
	var prior_focus: Variant = holder.get_meta("restore_focus") if holder.has_meta("restore_focus") else null
	if not is_instance_valid(prior_focus):prior_focus = null
	holder.queue_free()
	call_deferred("_restore_focus", prior_focus)

func _restore_focus(prior_focus: Variant) -> void:
	if prior_focus != null and is_instance_valid(prior_focus) and prior_focus.is_inside_tree():
		prior_focus.grab_focus()
		return
	if _stack.is_empty():
		return
	var previous_holder: Control = _stack.back()
	var close_button: Button = previous_holder.get_meta("popup_close") as Button \
		if previous_holder.has_meta("popup_close") else null
	if close_button != null and is_instance_valid(close_button) and close_button.is_inside_tree():
		close_button.grab_focus()
