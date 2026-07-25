extends PanelContainer
## Bottom nav (SPEC §9): Museum / Managers / Expedition / Event / Store.
## Locked features show their requirement and toast when tapped.
## Screens open by path string via PopupManager (SPEC §11 — no cross-branch preloads).
##
## Chrome, not candy. Five expand-filled candy tabs made the nav the loudest thing
## on the world view: a solid 720px band of terracotta and slate directly under the
## rewarded-video dock, so the two read as a stacked pair of bars fighting each
## other and the museum lost the bottom fifth of the screen. The genre reference
## does the opposite — small round icon buttons separated by world, no bar at all.
##
## So each destination is now a 64px glass disc centred in its fifth of the row,
## with a caption under it. The discs are far apart, share the HUD's dark-glass
## surface, and carry no saturated fill, which leaves exactly one saturated row on
## the screen: the money dock above. Colour is spent where it earns.
##
## Only the current destination is tinted (azure rim + azure icon + azure caption).
## Azure rather than the money palette on purpose: green/orange/gold/violet all
## mean "reward" one row up, and a nav marker that borrows a reward colour reads as
## a reward. Locked discs keep a lock glyph and print the requirement in place of
## the name, so the state is legible without a tap.
##
## The disc IS the touch target: 64px, over TOUCH_MIN, with ~70px of dead shell
## between neighbours so a thumb landing between two never fires the wrong screen.

const UI := preload("res://scripts/ui/ui_kit.gd")
const Popups := preload("res://scripts/ui/popup_manager.gd")

const PATH_MANAGERS := "res://scenes/managers/managers_screen.tscn"
const PATH_EXPEDITION := "res://scenes/events/expedition_screen.tscn"
const PATH_INSPECTION := "res://scenes/events/inspection_screen.tscn"
const PATH_STORE := "res://scenes/store/store_screen.tscn"

const DOT := 64          # disc diameter; also the whole touch target
const ICON := 30
const CAPTION := 12

## Current destination. Azure = navigation, kept clear of the money palette.
const TAB_ON := Color("#3BA9F5")

var _buttons := {}       # id -> Button
var _captions := {}      # id -> Label
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
	_margin.add_theme_constant_override("margin_left", 6)
	_margin.add_theme_constant_override("margin_right", 6)
	_margin.add_theme_constant_override("margin_top", 2)
	_margin.add_theme_constant_override("margin_bottom", 6)
	add_child(_margin)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 0)
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

## Keep the discs above the gesture pill / home indicator.
func _apply_safe_area() -> void:
	if _margin == null:
		return
	var inset: Dictionary = UI.safe_area_insets(self)
	_margin.add_theme_constant_override("margin_bottom", 6 + int(inset["bottom"]))
	_margin.add_theme_constant_override("margin_left", 6 + int(inset["left"]))
	_margin.add_theme_constant_override("margin_right", 6 + int(inset["right"]))

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
	# The cell expands, the disc does not: the gap between discs is what stops the
	# row from reading as a bar.
	var cell := VBoxContainer.new()
	cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cell.add_theme_constant_override("separation", 3)
	cell.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(cell)

	var b := Button.new()
	b.custom_minimum_size = Vector2(DOT, DOT)
	b.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	b.add_theme_font_override("font", UI.font())
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	b.icon = UI.icon_texture(icon_name, ICON)
	b.expand_icon = false
	b.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	b.vertical_icon_alignment = VERTICAL_ALIGNMENT_CENTER
	b.set_meta("icon_name", icon_name)
	b.set_meta("nav_id", id)
	UI.add_press_squish(b)
	b.pressed.connect(_on_nav_pressed.bind(id))
	cell.add_child(b)

	# Halo, not a plain label: on a tall handset the venue floor grows down to the
	# caption baseline, so the word has to survive landing on a lit room as well as
	# on the deep shell.
	var cap := UI.make_display_label(label_text, CAPTION, Color.WHITE)
	cap.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cap.clip_text = true
	UI.add_text_halo(cap, Color(0.05, 0.03, 0.12, 0.75), 3)
	cell.add_child(cap)

	_buttons[id] = b
	_captions[id] = cap

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
	var cap: Label = _captions.get(id)
	if b == null or cap == null:
		return
	var active: bool = id == _active_tab
	var key := "%s|%s|%s" % [unlocked, active, req_text]
	if _style_keys.get(id, "") == key:
		return
	_style_keys[id] = key
	b.modulate = Color(1, 1, 1, 1)
	if unlocked:
		b.icon = UI.icon_texture(str(b.get_meta("icon_name")), ICON)
		b.tooltip_text = ""
		cap.text = id.capitalize()
		_paint(b, cap, TAB_ON if active else Color.WHITE, 0.80 if active else 0.68,
			3 if active else 2)
	else:
		# Locked reads as a deliberate state, not a render fault: a dimmer disc with
		# a lock glyph, and the caption prints the requirement instead of a name the
		# player cannot reach yet. Never modulate the whole button — that greys the
		# surface as well and just looks broken.
		b.icon = UI.icon_texture("lock", ICON - 4)
		b.tooltip_text = "Unlocks at %s" % req_text
		cap.text = req_text
		_paint(b, cap, Color(0.72, 0.70, 0.86), 0.46, 2)

## One disc, one tint. `tint` colours the icon, the rim and the caption together so
## state reads from any of the three; `alpha` is the surface opacity, which is what
## separates a live destination from a locked one at a glance.
func _paint(b: Button, cap: Label, tint: Color, alpha: float, rim_w: int) -> void:
	var rim := Color(tint.r, tint.g, tint.b, 0.85 if rim_w > 2 else 0.20)
	var normal := _disc(alpha, rim, rim_w)
	b.add_theme_stylebox_override("normal", normal)
	b.add_theme_stylebox_override("hover", normal)
	var pressed: StyleBoxFlat = normal.duplicate()
	pressed.bg_color = UI.GLASS.lerp(Color.WHITE, 0.22)
	pressed.bg_color.a = minf(alpha + 0.15, 1.0)
	pressed.shadow_size = 0
	b.add_theme_stylebox_override("pressed", pressed)
	b.add_theme_color_override("icon_normal_color", tint)
	b.add_theme_color_override("icon_hover_color", tint)
	b.add_theme_color_override("icon_pressed_color", tint)
	cap.add_theme_color_override("font_color", tint)

func _disc(alpha: float, rim: Color, rim_w: int) -> StyleBoxFlat:
	var sb := UI.make_glass(DOT / 2, alpha, rim)
	sb.set_content_margin_all(0)
	sb.set_border_width_all(rim_w)
	sb.border_color = rim
	return sb

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
