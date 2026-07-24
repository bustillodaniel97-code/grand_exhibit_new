extends Control
## Bottom nav (SPEC §9): Museum / Managers / Expedition / Event / Store.
## Locked features show their requirement and toast when tapped.
## Screens open by path string via PopupManager (SPEC §11 — no cross-branch preloads).

const UI := preload("res://scripts/ui/ui_kit.gd")
const Popups := preload("res://scripts/ui/popup_manager.gd")

const PATH_MANAGERS := "res://scenes/managers/managers_screen.tscn"
const PATH_EXPEDITION := "res://scenes/events/expedition_screen.tscn"
const PATH_INSPECTION := "res://scenes/events/inspection_screen.tscn"
const PATH_STORE := "res://scenes/store/store_screen.tscn"

var _buttons := {}  # id -> Button
var _timer: Timer

func _ready() -> void:
	name = "BottomNav"
	custom_minimum_size = Vector2(0, 100)

	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	panel.add_theme_stylebox_override("panel", UI.make_panel(UI.PANEL, 0, 0))
	add_child(panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 10)
	margin.add_theme_constant_override("margin_right", 10)
	margin.add_theme_constant_override("margin_top", 8)
	margin.add_theme_constant_override("margin_bottom", 8)
	panel.add_child(margin)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	margin.add_child(row)

	_add_nav_button(row, "museum", "Museum")
	_add_nav_button(row, "managers", "Managers")
	_add_nav_button(row, "expedition", "Expedition")
	_add_nav_button(row, "event", "Event")
	_add_nav_button(row, "store", "Store")

	EventBus.reputation_changed.connect(_on_unlock_signal)
	EventBus.unlock_changed.connect(_on_unlock_signal)

	_timer = Timer.new()
	_timer.wait_time = 1.0
	_timer.autostart = true
	_timer.timeout.connect(refresh_locks)
	add_child(_timer)

	refresh_locks()

func _add_nav_button(row: HBoxContainer, id: String, label_text: String) -> void:
	var b := UI.make_button(label_text, UI.ACCENT)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.size_flags_vertical = Control.SIZE_EXPAND_FILL
	b.add_theme_font_size_override("font_size", 19)
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
	if unlocked:
		b.text = base
		b.modulate = Color(1, 1, 1, 1)
	else:
		b.text = "%s\n%s" % [base, req_text]
		b.modulate = Color(0.6, 0.6, 0.6, 1)

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
