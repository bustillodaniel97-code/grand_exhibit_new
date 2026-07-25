extends PanelContainer
## Bottom nav (SPEC §9): Museum / Managers / Expedition / Event / Store.
## Locked features show their requirement and toast when tapped.
## Screens open by path string via PopupManager (SPEC §11 — no cross-branch preloads).
##
## Root is a PanelContainer so the bar sizes to its buttons instead of a fixed
## 100px, and its bottom margin absorbs the gesture-pill safe-area inset.
##
## The root stylebox is EMPTY: the bar used to be an opaque cream slab, a second
## light band that with the HUD claimed a fifth of the portrait canvas. The
## buttons are already extruded candy caps with their own surface and shadow, so
## they read fine floating straight on the shell.
##
## Colour now carries state instead of decorating: exactly one tab is ACCENT (the
## screen you are on), the rest are a live indigo, and locked ones stay the muted
## slate with a lock glyph. Five identical orange tabs told the player nothing.

const UI := preload("res://scripts/ui/ui_kit.gd")
const Popups := preload("res://scripts/ui/popup_manager.gd")

const PATH_MANAGERS := "res://scenes/managers/managers_screen.tscn"
const PATH_EXPEDITION := "res://scenes/events/expedition_screen.tscn"
const PATH_INSPECTION := "res://scenes/events/inspection_screen.tscn"
const PATH_STORE := "res://scenes/store/store_screen.tscn"

## Unlocked-but-not-current tab. Deep enough to sit on the shell without shouting
## over the one tab that is actually current.
const TAB_IDLE := Color("#54408F")

var _buttons := {}       # id -> Button
var _style_keys := {}    # id -> String, so the 1s refresh only restyles on change
var _opened_tab: String = "museum"   # tab that owns the popup currently on screen
var _active_tab: String = "museum"   # what the bar is currently showing as current
var _was_open: bool = false          # popup-stack edge detector, see _process
var _margin: MarginContainer
var _timer: Timer

func _ready() -> void:
	name = "BottomNav"
	UI.install_default_font()
	add_theme_stylebox_override("panel", StyleBoxEmpty.new())

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

## A popup can also be dismissed by its own ✕ or by the dim, and one can be
## opened by something that is not a tab at all (Decor, Prestige, an objective
## chip) — the nav hears about none of it, so polling the stack is what keeps
## "current" honest. A popup that appeared without a tab press belongs to no tab,
## which is why the rising edge hands ownership back to Museum. Two static calls
## per frame, and the restyle only runs when the answer actually changes.
func _process(_delta: float) -> void:
	var open: bool = Popups.is_open()
	if open and not _was_open:
		_opened_tab = "museum"
	_was_open = open
	var want: String = _opened_tab if open else "museum"
	if want != _active_tab:
		_active_tab = want
		refresh_locks()

func _add_nav_button(row: HBoxContainer, id: String, label_text: String, icon_name: String) -> void:
	var b := UI.make_button(label_text, TAB_IDLE)
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
	_set_lock("museum", true, "")
	_set_lock("managers", GameState.feature_unlocked("managers"), "Rep %d" % _unlock_req("managers_rep", 6))
	_set_lock("expedition", GameState.feature_unlocked("expedition"), "Rep %d" % _unlock_req("expedition_rep", 7))
	_set_lock("event", GameState.feature_unlocked("inspection"), "Day %d" % (_unlock_req("inspection_day", 1) + 1))
	_set_lock("store", true, "")

func _unlock_req(key: String, fallback: int) -> int:
	return int(DataLoader.core.get("unlocks", {}).get(key, fallback))

func _set_lock(id: String, unlocked: bool, req_text: String) -> void:
	var b: Button = _buttons.get(id)
	if b == null:
		return
	var active: bool = id == _active_tab
	var key := "%s|%s|%s" % [unlocked, active, req_text]
	if _style_keys.get(id, "") == key:
		return
	_style_keys[id] = key
	b.text = id.capitalize()
	if unlocked:
		b.icon = UI.icon_texture(str(b.get_meta("icon_name")), 26)
		b.tooltip_text = ""
		_paint_tab(b, UI.ACCENT if active else TAB_IDLE, active)
	else:
		# Locked reads as a deliberate state, not a render fault: restyle to a
		# muted slate tab with a lock glyph. The old code dimmed the whole button
		# with modulate, which greyed the nine-patch too and just looked broken.
		# The exact requirement lives on the tooltip and in the tap toast.
		b.icon = UI.icon_texture("lock", 24)
		b.tooltip_text = "Unlocks at %s" % req_text
		_paint_tab(b, UI.INK.lerp(UI.SLATE, 0.35), false)
	b.modulate = Color(1, 1, 1, 1)
	b.add_theme_font_size_override("font_size", UI.TYPE_LABEL)
	b.add_theme_color_override("font_color",
		Color.WHITE if unlocked else Color(1, 1, 1, 0.72))

## Current tab gets a brass rim on top of the accent fill. Fill alone is not an
## indicator: a player who has never seen the other state cannot tell "orange
## because selected" from "orange because that is the colour of tabs".
func _paint_tab(b: Button, bg: Color, active: bool) -> void:
	UI.retint_button(b, bg)
	if not active:
		return
	var sb: StyleBoxFlat = (b.get_theme_stylebox("normal") as StyleBoxFlat).duplicate()
	sb.set_border_width_all(3)
	sb.border_width_bottom = 6
	sb.border_color = UI.BRASS
	b.add_theme_stylebox_override("normal", sb)

func _on_nav_pressed(id: String) -> void:
	match id:
		"museum":
			# Home: close any open popup, revealing the venue view.
			if Popups.is_open():
				Popups.close_top()
		"managers":
			if GameState.feature_unlocked("managers"):
				_open(id, PATH_MANAGERS)
			else:
				EventBus.toast_requested.emit("Unlocks at Rep %d" % _unlock_req("managers_rep", 6))
		"expedition":
			if GameState.feature_unlocked("expedition"):
				_open(id, PATH_EXPEDITION)
			else:
				EventBus.toast_requested.emit("Unlocks at Rep %d" % _unlock_req("expedition_rep", 7))
		"event":
			if GameState.feature_unlocked("inspection"):
				_open(id, PATH_INSPECTION)
			else:
				EventBus.toast_requested.emit("Unlocks on Day %d" % (_unlock_req("inspection_day", 1) + 1))
		"store":
			_open(id, PATH_STORE)

func _open(id: String, path: String) -> void:
	Popups.open(path)
	# Claim ownership after the open, so _process' rising edge does not read this
	# as a popup that arrived from somewhere else and hand it back to Museum.
	_opened_tab = id
	_was_open = Popups.is_open()
