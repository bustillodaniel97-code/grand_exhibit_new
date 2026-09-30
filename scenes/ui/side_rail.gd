extends Control
## SideRail — vertical strip of secondary entry points parked on the right edge
## of the world, the way Idle Bank Tycoon parks its offers and events.
##
## The point is arithmetic, not fashion: a horizontal band of meta buttons costs
## every pixel of its height across the whole screen, forever. Decor + Prestige
## used to ride in the HUD's second row and cost 48px of world for two controls
## that are tapped a handful of times an hour. On a rail they cost ZERO vertical
## space — they float over sky and city, which is the least valuable real estate
## on the board.
##
## Placement rules this node enforces:
##   · Right edge, inset by the gutter AND by UI.safe_area_insets (curved-display
##     phones clip the last few columns).
##   · Top edge starts BELOW the venue strip, measured from the live QuestsBar
##     rect rather than a hardcoded y — the chrome above it is being tuned and a
##     magic number would silently drift into the museum.
##   · 56px tiles: over the 48dp floor with room for a fat thumb.
##   · The root ignores the mouse entirely; only the tiles take input, so the rail
##     never swallows a tap meant for a department room behind it.

const UI := preload("res://scripts/ui/ui_kit.gd")
const Popups := preload("res://scripts/ui/popup_manager.gd")
const PrestigeSystem := preload("res://scripts/meta/prestige_system.gd")
const Chrome := preload("res://scripts/ui/museum_chrome.gd")

const DECOR_PATH := "res://scenes/meta/decor_screen.tscn"
const PRESTIGE_PATH := "res://scenes/meta/prestige_screen.tscn"
const STATISTICS_PATH := "res://scenes/meta/statistics_screen.tscn"
const WINGS_PATH := "res://scenes/meta/wings_screen.tscn"
const SETTINGS_PATH := "res://scenes/meta/settings_screen.tscn"
const VISITORS_PATH := "res://scenes/meta/visitor_guide.tscn"
const CAFE_PATH := "res://scenes/events/cafe_screen.tscn"
const CafeSystem := preload("res://scripts/events/cafe_system.gd")
const GIFTS_PATH := "res://scenes/meta/daily_gifts_screen.tscn"
const DailyGifts := preload("res://scripts/meta/daily_gifts.gd")
const WingSystem := preload("res://scripts/meta/wing_system.gd")

const TILE := 72          # wide enough for the longest caption, still a 52px target
const TILE_HEIGHT := 52
const GAP := 8
## Clearance under the venue strip. Enough that the rail reads as floating on the
## world rather than as a fourth chrome band welded to the bottom of the strip.
const TOP_CLEARANCE := 12
## Only used if the strip cannot be measured (venue tab not built yet).
const FALLBACK_TOP := 210

var _col: VBoxContainer
var _prestige_item: Control
var _floors_item: Control
var _cafe_item: Control
var _gifts_item: Control
var _strip: Control          # QuestsBar, when it exists
var _timer: Timer
var _celebrated: Dictionary = {}

func _ready() -> void:
	name = "SideRail"
	# Keep floating controls above every museum storey and its finishing pass.
	z_index = 100
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# The rail is a floating overlay, not a page: it must be transparent to every
	# tap that is not on one of its tiles.
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	_col = VBoxContainer.new()
	_col.add_theme_constant_override("separation", GAP)
	_col.alignment = BoxContainer.ALIGNMENT_BEGIN
	_col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_col)

	# Today's gift, until it is opened.
	_gifts_item = _rail_item("Gift", "star", Chrome.ACTION, func() -> void: Popups.open(GIFTS_PATH))
	_gifts_item.visible = false
	_col.add_child(_gifts_item)
	# The Pop-Up Café tile only exists while an event is live.
	_cafe_item = _rail_item("Café", "cart", Chrome.DANGER, func() -> void: Popups.open(CAFE_PATH))
	_cafe_item.visible = false
	_col.add_child(_cafe_item)
	_col.add_child(_rail_item("Stats", "disc", Chrome.TEAL, _on_stats_pressed))
	_col.add_child(_rail_item("Decor", "star", Chrome.TEAL, _on_decor_pressed))
	_floors_item = _rail_item("Floors", "home", Chrome.BRASS, _on_floors_pressed)
	_col.add_child(_floors_item)
	_col.add_child(_rail_item("Visitors", "medal", Chrome.BRASS, func() -> void: Popups.open(VISITORS_PATH)))
	_col.add_child(_rail_item("Settings", "gear", Chrome.DIM, func() -> void: Popups.open(SETTINGS_PATH)))
	_prestige_item = _rail_item("Next Museum", "trophy", Chrome.BRASS, _on_prestige_pressed)
	_col.add_child(_prestige_item)

	EventBus.reputation_changed.connect(_on_state_changed)
	EventBus.milestone_completed.connect(_on_state_changed)
	EventBus.prestige_available.connect(_on_state_changed)
	EventBus.prestige_performed.connect(_on_state_changed)

	# Cheap heartbeat: unlocks flip on data the rail does not otherwise watch.
	_timer = Timer.new()
	_timer.wait_time = 1.0
	_timer.autostart = true
	_timer.timeout.connect(refresh)
	add_child(_timer)

	get_viewport().size_changed.connect(_reposition)
	resized.connect(_reposition)
	call_deferred("_bind")
	refresh()

## Bind to the chrome above us and re-measure. Deferred because
## UI.safe_area_insets and every global_position here are meaningless until the
## first layout pass has run.
func _bind() -> void:
	if _strip == null:
		var n: Node = get_tree().root.find_child("QuestsBar", true, false)
		if n is Control:
			_strip = n as Control
			_strip.resized.connect(_reposition)
	_reposition()

## One full-width museum tile plus its caption. Captions are part of the measured
## item width so "Next Museum" cannot be clipped on narrow handsets.
func _rail_item(text: String, icon_name: String, tint: Color, cb: Callable) -> Control:
	var item := VBoxContainer.new()
	item.name = "Item%s" % text
	item.add_theme_constant_override("separation", 2)
	item.mouse_filter = Control.MOUSE_FILTER_IGNORE
	item.custom_minimum_size = Vector2(TILE, 0)

	var b := Button.new()
	b.custom_minimum_size = Vector2(TILE, TILE_HEIGHT)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.tooltip_text = text
	b.icon = UI.icon_texture(icon_name, 22)
	b.expand_icon = false
	b.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	b.vertical_icon_alignment = VERTICAL_ALIGNMENT_CENTER
	Chrome.button(b, false, 12)
	for state in ["icon_normal_color", "icon_hover_color", "icon_pressed_color"]:
		b.add_theme_color_override(state, tint)
	UI.add_press_squish(b)
	b.pressed.connect(cb)
	item.add_child(b)
	# Notification dot: something is ready behind this tile.
	var dot := Panel.new()
	dot.name = "Badge"
	var sb := StyleBoxFlat.new()
	sb.bg_color = Chrome.DANGER
	sb.set_corner_radius_all(7)
	sb.set_border_width_all(2)
	sb.border_color = Chrome.PANEL
	dot.add_theme_stylebox_override("panel", sb)
	dot.size = Vector2(14, 14)
	dot.position = Vector2(TILE - 16, 2)
	dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	dot.visible = false
	b.add_child(dot)

	var cap := UI.make_display_label(text, UI.TYPE_CAPTION, Chrome.INK)
	cap.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cap.clip_text = false
	item.add_child(cap)
	return item

## Park the column against the right edge, under the venue strip.
func _reposition() -> void:
	if _col == null or not is_inside_tree():
		return
	var inset: Dictionary = UI.safe_area_insets(self)
	# The label determines the real width; do not force the column back to the
	# icon width after Godot has measured it.
	var w: float = maxf(float(TILE), _col.get_combined_minimum_size().x)
	var h: float = _col.get_combined_minimum_size().y
	_col.size = Vector2(w, h)
	_col.position = Vector2(
		size.x - w - float(UI.GUTTER) - float(inset["right"]),
		_content_top() + float(inset["top"]))

## Bottom of the venue strip, measured live. Falls back to a constant only when
## the strip is not on screen (another tab is up), where the rail's exact y is
## not load-bearing anyway.
func _content_top() -> float:
	if _strip != null and is_instance_valid(_strip) and _strip.is_inside_tree() \
			and _strip.size.y > 0.0:
		return _strip.global_position.y + _strip.size.y + float(TOP_CLEARANCE)
	return float(FALLBACK_TOP)

func _on_state_changed(_a: Variant = null, _b: Variant = null) -> void:
	refresh()

func refresh() -> void:
	# Never disable a control for availability — a disabled button swallows the
	# tap and tells the player nothing. Prestige is simply absent until it means
	# something, and Decor stays live and explains itself.
	# This is not an optional prestige/reset control. It appears only when the
	# current museum is genuinely 100% complete and its sole meaning is opening
	# the next authored level.
	var show_prestige: bool = PrestigeSystem.gate_met(GameState.current_venue) \
		and PrestigeSystem.next_venue_id() != ""
	if _prestige_item.visible != show_prestige:
		_prestige_item.visible = show_prestige
		_reposition()
	# The Floors tile glows while a wing is ready to renovate.
	var nxt: Dictionary = WingSystem.next_wing(GameState.current_venue)
	var ready: bool = not nxt.is_empty() and WingSystem.status(GameState.current_venue, str(nxt["id"])) == WingSystem.STATUS_READY
	_badge(_floors_item, ready)
	var gift_ready: bool = GameState.ready_flag and DailyGifts.available()
	if _gifts_item.visible != gift_ready:
		_gifts_item.visible = gift_ready
		_reposition()
	_badge(_gifts_item, gift_ready)
	var cafe_live: bool = CafeSystem.is_live()
	if _cafe_item.visible != cafe_live:
		_cafe_item.visible = cafe_live
		_reposition()
		if cafe_live and GameState.ready_flag:
			var days := int(round(float(CafeSystem.config().get("duration_hours", 72)) / 24.0))
			EventBus.toast_requested.emit(tr("%s is open! A pop-up café for %d days") % [tr(str(CafeSystem.theme().get("name", "The Pop-Up Café"))), days])
	if cafe_live:
		_badge(_cafe_item, CafeSystem.any_claimable())
	if show_prestige and not bool(_celebrated.get(GameState.current_venue, false)) \
			and not Popups.is_open():
		_celebrated[GameState.current_venue] = true
		call_deferred("_open_completion")

func _badge(item: Control, on: bool) -> void:
	var dot := item.find_child("Badge", true, false) as Control
	if dot != null:
		dot.visible = on

func _open_completion() -> void:
	if PrestigeSystem.gate_met(GameState.current_venue) and not Popups.is_open():
		Popups.open(PRESTIGE_PATH, {"celebrate": true})

func _on_decor_pressed() -> void:
	if GameState.feature_unlocked("decor"):
		Popups.open(DECOR_PATH)
	else:
		var req: int = int(DataLoader.core.get("unlocks", {}).get("decor_rep", 2))
		EventBus.toast_requested.emit(tr("Decor unlocks at Rep %d") % req)

func _on_stats_pressed() -> void:
	Popups.open(STATISTICS_PATH)

func _on_floors_pressed() -> void:
	Popups.open(WINGS_PATH, {"focus": str(WingSystem.next_wing(GameState.current_venue).get("id", ""))})

func _on_prestige_pressed() -> void:
	Popups.open(PRESTIGE_PATH)
