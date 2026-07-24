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
	# 90% width x 70% height of the 720x1280 portrait viewport: screens always get room
	# regardless of how their root Control is configured (integration fix — collapsed-card bug).
	card.custom_minimum_size = Vector2(648, 896)
	card.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	card.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	card.add_theme_stylebox_override("panel", UI.make_panel(UI.PANEL, 12, 0))
	center.add_child(card)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 12)
	card.add_child(vbox)

	var top_row := HBoxContainer.new()
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top_row.add_child(spacer)
	var x_btn := UI.make_button("X", UI.ACCENT)
	x_btn.custom_minimum_size = Vector2(52, 52)
	x_btn.pressed.connect(close_top)
	top_row.add_child(x_btn)
	vbox.add_child(top_row)

	var content: Node = packed.instantiate()
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(content)

	add_child(holder)
	_stack.append(holder)
	if content.has_method("setup"):
		content.setup(payload)

func _close_top() -> void:
	if _stack.is_empty():
		return
	var holder: Control = _stack.pop_back()
	holder.queue_free()
