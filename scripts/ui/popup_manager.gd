extends CanvasLayer
## PopupManager — dim overlay + centered card popups (SPEC §9).
## Instantiated once via scenes/ui/popup_layer.tscn (added by scenes/main.gd).
## Access from venue-ui branch files:
##   const Popup = preload("res://scripts/ui/popup_manager.gd")
##   Popup.open(path, payload) / Popup.close_top()
## All cross-branch screens are opened by path string only (SPEC §11 SCREEN REGISTRY).

const UI := preload("res://scripts/ui/ui_kit.gd")

static var _instance: CanvasLayer = null

var _stack: Array[Control] = []

func _ready() -> void:
	layer = 10
	_instance = self

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
	dim.color = Color(0, 0, 0, 0.55)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP  # swallow taps on the dim
	holder.add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(center)

	var card := PanelContainer.new()
	# Sized from the live viewport rather than a fixed 648x896. With stretch
	# aspect "expand" a tall phone reports a taller viewport, and a hardcoded
	# card left a growing dead gap under it. Screens still always get room —
	# that was the original point of the floor (collapsed-card integration fix).
	var vis: Vector2 = get_viewport().get_visible_rect().size
	var inset: Dictionary = UI.safe_area_insets(dim)
	card.custom_minimum_size = Vector2(
		minf(vis.x - 2.0 * UI.GUTTER, 700.0),
		clampf(vis.y - 220.0 - float(inset["top"]) - float(inset["bottom"]), 560.0, 1180.0))
	card.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	card.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	# The frame is the page. Screens paint their own PAGE fill on top of it, but
	# welcome-back does not, and the rounded corners the screens cannot reach are
	# this stylebox's — so a cream frame drew a light halo around every dark sheet.
	var frame := UI.make_dark_card(UI.PAGE, UI.RADIUS_CARD)
	frame.set_content_margin_all(0)
	frame.set_border_width_all(2)
	frame.border_color = Color(1, 1, 1, 0.14)
	frame.shadow_size = 12
	card.add_theme_stylebox_override("panel", frame)
	card.clip_contents = true
	center.add_child(card)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 0)
	card.add_child(vbox)

	# Title bar. The close button used to sit alone on an otherwise blank strip,
	# which read as a rendering fault on every one of the eight screens; giving
	# the strip its own tinted background and a rule underneath makes it a
	# deliberate bar. It stays a real layout row (not an overlay) so it can never
	# collide with the right-aligned header chips several screens already draw.
	var bar := PanelContainer.new()
	# A deep RAIL, not a lighter strip. The bar carries nothing but the close
	# button — the screens draw their own titles — so a strip lighter than the page
	# is 60px of empty saturated slab at the top of every popup. Sunk below the
	# page instead, it reads as the frame's edge and the divider does the work.
	bar.add_theme_stylebox_override("panel", UI.make_panel(UI.PAGE_DEEP, 0, 0))
	var top_row := HBoxContainer.new()
	top_row.add_theme_constant_override("separation", 8)
	var pad := MarginContainer.new()
	pad.add_theme_constant_override("margin_left", 10)
	pad.add_theme_constant_override("margin_right", 10)
	pad.add_theme_constant_override("margin_top", 4)
	pad.add_theme_constant_override("margin_bottom", 4)
	pad.add_child(top_row)
	bar.add_child(pad)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top_row.add_child(spacer)
	# Red, not orange. Orange is the primary-action colour everywhere else in the
	# app, and the one control that throws the screen away should not wear it.
	var x_btn := UI.make_button("X", UI.DANGER)
	x_btn.custom_minimum_size = Vector2(UI.TOUCH_MIN, UI.TOUCH_MIN)
	x_btn.pressed.connect(close_top)
	top_row.add_child(x_btn)
	vbox.add_child(bar)
	vbox.add_child(UI.make_divider(UI.HAIRLINE))

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
	if content.has_method("setup"):
		content.setup(payload)
	_play_open(card, dim)

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

func _close_top() -> void:
	if _stack.is_empty():
		return
	var holder: Control = _stack.pop_back()
	holder.queue_free()
