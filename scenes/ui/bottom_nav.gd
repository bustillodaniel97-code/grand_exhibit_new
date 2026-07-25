extends PanelContainer
## Bottom nav (SPEC §9): Museum / Managers / Expedition / Event / Store.
## Locked features show their requirement and toast when tapped.
## Screens open by path string via PopupManager (SPEC §11 — no cross-branch preloads).
##
## Root is a PanelContainer so the bar sizes to its buttons instead of a fixed
## 100px, and its bottom margin absorbs the gesture-pill safe-area inset.

const UI := preload("res://scripts/ui/ui_kit.gd")
const Popups := preload("res://scripts/ui/popup_manager.gd")

const PATH_MANAGERS := "res://scenes/managers/managers_screen.tscn"
const PATH_EXPEDITION := "res://scenes/events/expedition_screen.tscn"
const PATH_INSPECTION := "res://scenes/events/inspection_screen.tscn"
const PATH_STORE := "res://scenes/store/store_screen.tscn"

var _buttons := {}  # id -> Button
var _margin: MarginContainer
var _timer: Timer

func _ready() -> void:
	name = "BottomNav"
	UI.install_default_font()
	add_theme_stylebox_override("panel", UI.make_panel(UI.PANEL, 0, 0))

	_margin = MarginContainer.new()
	_margin.add_theme_constant_override("margin_left", 10)
	_margin.add_theme_constant_override("margin_right", 10)
	_margin.add_theme_constant_override("margin_top", 8)
	_margin.add_theme_constant_override("margin_bottom", 8)
	add_child(_margin)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	_margin.add_child(row)

	_add_nav_button(row, "museum", "Museum", "home")
	_add_nav_button(row, "managers", "Managers", "medal")
	_add_nav_button(row, "expedition", "Expedition", "arrow_right")
	_add_nav_button(row, "event", "Event", "exclamation")
	_add_nav_button(row, "store", "Store", "cart")

	EventBus.reputation_changed.connect(_on_unlock_signal)
	EventBus.unlock_changed.connect(_on_unlock_signal)

	_timer = Timer.new()
	_timer.wait_time = 1.0
	_timer.autostart = true
	_timer.timeout.connect(refresh_locks)
	add_child(_timer)

	get_viewport().size_changed.connect(_apply_safe_area)
	_apply_safe_area()
	refresh_locks()

## Keep the tab row above the gesture pill / home indicator.
func _apply_safe_area() -> void:
	if _margin == null:
		return
	var inset: Dictionary = UI.safe_area_insets(self)
	_margin.add_theme_constant_override("margin_bottom", 8 + int(inset["bottom"]))
	_margin.add_theme_constant_override("margin_left", 10 + int(inset["left"]))
	_margin.add_theme_constant_override("margin_right", 10 + int(inset["right"]))

func _add_nav_button(row: HBoxContainer, id: String, label_text: String, icon_name: String) -> void:
	var b := UI.make_button(label_text, UI.ACCENT)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.custom_minimum_size = Vector2(0, UI.TOUCH_MIN + 20)
	b.add_theme_font_size_override("font_size", UI.TYPE_LABEL)
	b.icon = UI.icon_texture(icon_name, 26)
	b.expand_icon = false
	b.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	b.vertical_icon_alignment = VERTICAL_ALIGNMENT_TOP
	b.set_meta("icon_name", icon_name)
	b.pressed.connect(_on_nav_pressed.bind(id))
	row.add_child(b)
	_buttons[id] = b

func _on_unlock_signal(_a: Variant = null, _b: Variant = null) -> void:
	refresh_locks()

func refresh_locks() -> void:
	_set_lock("managers", GameState.feature_unlocked("managers"), "Rep %d" % _unlock_req("managers_rep", 6))
	_set_lock("expedition", GameState.feature_unlocked("expedition"), "Rep %d" % _unlock_req("expedition_rep", 7))
	_set_lock("event", GameState.feature_unlocked("inspection"), "Day %d" % (_unlock_req("inspection_day", 1) + 1))

func _unlock_req(key: String, fallback: int) -> int:
	return int(DataLoader.core.get("unlocks", {}).get(key, fallback))

func _set_lock(id: String, unlocked: bool, req_text: String) -> void:
	var b: Button = _buttons.get(id)
	if b == null:
		return
	var base: String = id.capitalize()
	b.text = base
	if unlocked:
		b.icon = UI.icon_texture(str(b.get_meta("icon_name")), 26)
		b.tooltip_text = ""
		UI.retint_button(b, UI.ACCENT)
	else:
		# Locked reads as a deliberate state, not a render fault: restyle to a
		# muted slate tab with a lock glyph. The old code dimmed the whole button
		# with modulate, which greyed the nine-patch too and just looked broken.
		# The exact requirement lives on the tooltip and in the tap toast.
		b.icon = UI.icon_texture("lock", 24)
		b.tooltip_text = "Unlocks at %s" % req_text
		UI.retint_button(b, UI.INK.lerp(UI.SLATE, 0.35))
	b.modulate = Color(1, 1, 1, 1)
	b.add_theme_font_size_override("font_size", UI.TYPE_LABEL)
	b.add_theme_color_override("font_color",
		Color.WHITE if unlocked else Color(1, 1, 1, 0.72))

func _on_nav_pressed(id: String) -> void:
	match id:
		"museum":
			# Home: close any open popup, revealing the venue view.
			if Popups.is_open():
				Popups.close_top()
		"managers":
			if GameState.feature_unlocked("managers"):
				Popups.open(PATH_MANAGERS)
			else:
				EventBus.toast_requested.emit("Unlocks at Rep %d" % _unlock_req("managers_rep", 6))
		"expedition":
			if GameState.feature_unlocked("expedition"):
				Popups.open(PATH_EXPEDITION)
			else:
				EventBus.toast_requested.emit("Unlocks at Rep %d" % _unlock_req("expedition_rep", 7))
		"event":
			if GameState.feature_unlocked("inspection"):
				Popups.open(PATH_INSPECTION)
			else:
				EventBus.toast_requested.emit("Unlocks on Day %d" % (_unlock_req("inspection_day", 1) + 1))
		"store":
			Popups.open(PATH_STORE)
