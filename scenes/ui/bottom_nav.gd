extends PanelContainer
## Museum destinations. The rail is deliberately short and quiet: the museum
## remains visible, while every destination remains named and reachable by touch.

const UI := preload("res://scripts/ui/ui_kit.gd")
const Popups := preload("res://scripts/ui/popup_manager.gd")
const Chrome := preload("res://scripts/ui/museum_chrome.gd")

const PATH_MANAGERS := "res://scenes/managers/managers_screen.tscn"
const PATH_EXPEDITION := "res://scenes/events/expedition_screen.tscn"
## The Expedition tab opens the Dig Site excavation game; the boss expedition
## is one button inside it once Rep 7 unlocks it.
const PATH_DIG := "res://scenes/digsite/dig_site_screen.tscn"
const PATH_INSPECTION := "res://scenes/events/inspection_screen.tscn"
const PATH_STORE := "res://scenes/store/store_screen.tscn"

const TAB_HEIGHT := 76
const TOUCH_HEIGHT := 48
const ICON := 21
const NAME_SIZE := 13
const REQUIREMENT_SIZE := 10

var _buttons := {}
var _requirements := {}
var _style_keys := {}
var _opened_tab := "museum"
var _active_tab := "museum"
var _was_open := false
var _margin: MarginContainer
var _timer: Timer

func _ready() -> void:
	name = "BottomNav"
	UI.install_default_font()
	custom_minimum_size.y = TAB_HEIGHT
	var nav_surface := Chrome.panel(0, Chrome.BG)
	# The helper's default panel padding suits cards. The nav owns its own compact
	# margins below, so avoid layering both and growing this shell past its budget.
	nav_surface.set_content_margin_all(0)
	add_theme_stylebox_override("panel", nav_surface)

	_margin = MarginContainer.new()
	_margin.add_theme_constant_override("margin_left", 8)
	_margin.add_theme_constant_override("margin_right", 8)
	_margin.add_theme_constant_override("margin_top", 4)
	_margin.add_theme_constant_override("margin_bottom", 4)
	add_child(_margin)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 5)
	_margin.add_child(row)
	_add_nav_button(row, "museum", "Museum", "home")
	_add_nav_button(row, "managers", "Managers", "medal")
	_add_nav_button(row, "expedition", "Dig Site", "arrow_right")
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

func _apply_safe_area() -> void:
	if _margin == null:
		return
	var inset: Dictionary = UI.safe_area_insets(self)
	_margin.add_theme_constant_override("margin_bottom", 4 + int(inset["bottom"]))
	_margin.add_theme_constant_override("margin_left", 8 + int(inset["left"]))
	_margin.add_theme_constant_override("margin_right", 8 + int(inset["right"]))

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
	var cell := VBoxContainer.new()
	cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cell.add_theme_constant_override("separation", 1)
	cell.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(cell)

	var b := Button.new()
	b.custom_minimum_size = Vector2(48, TOUCH_HEIGHT)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.add_theme_font_override("font", UI.font())
	b.icon = UI.icon_texture(icon_name, ICON)
	b.expand_icon = false
	b.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	b.vertical_icon_alignment = VERTICAL_ALIGNMENT_CENTER
	b.set_meta("icon_name", icon_name)
	b.set_meta("nav_id", id)
	UI.add_press_squish(b)
	b.pressed.connect(_on_nav_pressed.bind(id))
	cell.add_child(b)

	var name_label := UI.make_display_label(label_text, NAME_SIZE, Chrome.INK)
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	name_label.clip_text = true
	cell.add_child(name_label)
	var req := UI.make_display_label("", REQUIREMENT_SIZE, Chrome.DIM)
	req.custom_minimum_size.y = 11
	req.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	req.mouse_filter = Control.MOUSE_FILTER_IGNORE
	req.clip_text = true
	cell.add_child(req)
	_buttons[id] = b
	_requirements[id] = req

func _on_unlock_signal(_a: Variant = null, _b: Variant = null) -> void:
	refresh_locks()

func refresh_locks() -> void:
	_set_lock("museum", true, "")
	_set_lock("managers", GameState.feature_unlocked("managers"), tr("Rep %d") % _unlock_req("managers_rep", 3))
	_set_lock("expedition", GameState.feature_unlocked("dig"), tr("Rep %d") % _unlock_req("dig_rep", 2))
	_set_lock("event", GameState.feature_unlocked("inspection"), tr("Day %d") % (_unlock_req("inspection_day", 1) + 1))
	_set_lock("store", true, "")

func _unlock_req(key: String, fallback: int) -> int:
	return int(DataLoader.core.get("unlocks", {}).get(key, fallback))

func _set_lock(id: String, unlocked: bool, req_text: String) -> void:
	var b: Button = _buttons.get(id)
	var req: Label = _requirements.get(id)
	if b == null or req == null:
		return
	var active: bool = id == _active_tab
	var key := "%s|%s|%s" % [unlocked, active, req_text]
	if _style_keys.get(id, "") == key:
		return
	_style_keys[id] = key
	if unlocked:
		b.icon = UI.icon_texture(str(b.get_meta("icon_name")), ICON)
		b.tooltip_text = ""
		req.text = ""
		Chrome.button(b, active, 10)
		if active:
			b.add_theme_color_override("icon_normal_color", Chrome.TEAL)
			b.add_theme_color_override("icon_hover_color", Chrome.INK)
	else:
		b.icon = UI.icon_texture("lock", ICON - 2)
		b.tooltip_text = tr("Unlocks at %s") % req_text
		req.text = tr("Unlock: %s") % req_text
		Chrome.button(b, false, 10)
		for state in ["icon_normal_color", "icon_hover_color", "icon_pressed_color"]:
			b.add_theme_color_override(state, Chrome.DIM)

func _on_nav_pressed(id: String) -> void:
	match id:
		"museum":
			if Popups.is_open():
				Popups.close_top()
		"managers":
			if GameState.feature_unlocked("managers"):
				_open(id, PATH_MANAGERS)
			else:
				EventBus.toast_requested.emit(tr("Unlocks at Rep %d") % _unlock_req("managers_rep", 3))
		"expedition":
			if GameState.feature_unlocked("dig"):
				_open(id, PATH_DIG)
			else:
				EventBus.toast_requested.emit(tr("Unlocks at Rep %d") % _unlock_req("dig_rep", 2))
		"event":
			if GameState.feature_unlocked("inspection"):
				_open(id, PATH_INSPECTION)
			else:
				EventBus.toast_requested.emit(tr("Unlocks on Day %d") % (_unlock_req("inspection_day", 1) + 1))
		"store":
			_open(id, PATH_STORE)

func _open(id: String, path: String) -> void:
	Popups.open(path)
	_opened_tab = id
	_was_open = Popups.is_open()
