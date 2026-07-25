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

const DECOR_PATH := "res://scenes/meta/decor_screen.tscn"
const PRESTIGE_PATH := "res://scenes/meta/prestige_screen.tscn"

const TILE := 56          # > 48dp touch floor
const GAP := 10
## Clearance under the venue strip. Enough that the rail reads as floating on the
## world rather than as a fourth chrome band welded to the bottom of the strip.
const TOP_CLEARANCE := 12
## Only used if the strip cannot be measured (venue tab not built yet).
const FALLBACK_TOP := 210

var _col: VBoxContainer
var _prestige_item: Control
var _strip: Control          # QuestsBar, when it exists
var _timer: Timer

func _ready() -> void:
	name = "SideRail"
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# The rail is a floating overlay, not a page: it must be transparent to every
	# tap that is not on one of its tiles.
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	_col = VBoxContainer.new()
	_col.add_theme_constant_override("separation", GAP)
	_col.alignment = BoxContainer.ALIGNMENT_BEGIN
	_col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_col)

	_col.add_child(_rail_item("Decor", "star", UI.SAGE, _on_decor_pressed))
	_prestige_item = _rail_item("Prestige", "trophy", UI.BRASS, _on_prestige_pressed)
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

## One rail entry: a square glass tile plus a caption under it. Icon-only tiles
## are what IBT ships, but its icons are illustrated objects; ours are 24px
## monochrome glyphs, so the caption is what keeps the rail readable.
func _rail_item(text: String, icon_name: String, tint: Color, cb: Callable) -> Control:
	var item := VBoxContainer.new()
	item.name = "Item%s" % text
	item.add_theme_constant_override("separation", 1)
	item.mouse_filter = Control.MOUSE_FILTER_IGNORE
	item.custom_minimum_size = Vector2(TILE, 0)

	var b := Button.new()
	b.custom_minimum_size = Vector2(TILE, TILE)
	b.tooltip_text = text
	b.icon = UI.icon_texture(icon_name, 26)
	b.expand_icon = false
	for state in ["icon_normal_color", "icon_hover_color", "icon_pressed_color"]:
		b.add_theme_color_override(state, tint)
	var normal := UI.make_glass(16)
	b.add_theme_stylebox_override("normal", normal)
	b.add_theme_stylebox_override("hover", UI.make_glass(16, 0.92, Color(1, 1, 1, 0.28)))
	var pressed := UI.make_glass(16, 0.96, Color(1, 1, 1, 0.34))
	b.add_theme_stylebox_override("pressed", pressed)
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	UI.add_press_squish(b)
	b.pressed.connect(cb)
	item.add_child(b)

	var cap := UI.make_display_label(text, UI.TYPE_CAPTION, Color.WHITE)
	cap.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# The caption sits straight on the world, so it carries its own contrast.
	UI.add_text_halo(cap, Color(0, 0, 0, 0.75), 4)
	item.add_child(cap)
	return item

## Park the column against the right edge, under the venue strip.
func _reposition() -> void:
	if _col == null or not is_inside_tree():
		return
	var inset: Dictionary = UI.safe_area_insets(self)
	var w: float = float(TILE)
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
	var milestones_done: int = GameState.venue_state(GameState.current_venue) \
		.get("milestones", []).size()
	var show_prestige: bool = GameState.feature_unlocked("prestige") or milestones_done >= 8
	if _prestige_item.visible != show_prestige:
		_prestige_item.visible = show_prestige
		_reposition()

func _on_decor_pressed() -> void:
	if GameState.feature_unlocked("decor"):
		Popups.open(DECOR_PATH)
	else:
		var req: int = int(DataLoader.core.get("unlocks", {}).get("decor_rep", 2))
		EventBus.toast_requested.emit("Decor unlocks at Rep %d" % req)

func _on_prestige_pressed() -> void:
	Popups.open(PRESTIGE_PATH)
