extends Control
## VenueFloor3D — the Museum tab's floor when the venue has toy-diorama art.
##
## Drop-in for scenes/venue/floor/venue_floor.gd as far as VenueView and the
## quests bar are concerned: same node name ("VenueFloor"), same signals
## (dept_selected, item_selected), same feed (set_rates, get_choke). The 3D
## world (venue_3d.gd) renders into a SubViewport; the station chips stay 2D
## Controls on top, re-anchored to the projected counter every frame, so they
## are crisp, untouched by the tilt-shift pass, and tappable like before.
##
## Economy stays the single source of truth: the crowd is decoration scaled
## from the arrival rate, and the "+$" pops show value_per_visitor.

signal dept_selected(dept_id: String)
signal item_selected(dept_id: String, index: int)

const Venue3D := preload("res://scenes/venue3d/venue_3d.gd")
const UI := preload("res://scripts/ui/ui_kit.gd")
const Popups := preload("res://scripts/ui/popup_manager.gd")
const WingSystem := preload("res://scripts/meta/wing_system.gd")
const WINGS_PATH := "res://scenes/meta/wings_screen.tscn"
const Juice := preload("res://scripts/ui/juice.gd")

const TAP_SLOP := 14.0     # px a press may travel and still count as a tap
const CHIP := Vector2(52, 52)

## Venues that have generated 3D art (tools/blender/toybox -> art3d/venues/<id>).
static func supports(venue_id: String) -> bool:
	return ResourceLoader.exists("res://art3d/venues/%s/shell.glb" % venue_id)

var venue_id := ""
var world: Node3D

var _container: SubViewportContainer
var _viewport: SubViewport
var _chips_layer: Control
var _chips: Array[Button] = []
var _ups: Array[Button] = []
var _choke := ""
var _value_text := "1"
var _press_at := Vector2.ZERO
var _press_travel := 0.0
var _pressed := false
var _font: Font
var _floor_bar: VBoxContainer
var _floor_btns: Array[Button] = []   # top floor first, ground last
var _ground_focus := Vector3.ZERO
var _tier_set := false

func _ready() -> void:
	name = "VenueFloor"
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_PASS
	_font = UI.font()

	_container = SubViewportContainer.new()
	_container.name = "World3D"
	_container.stretch = true
	_container.set_anchors_preset(Control.PRESET_FULL_RECT)
	_container.mouse_filter = Control.MOUSE_FILTER_STOP
	_container.gui_input.connect(_on_world_input)
	add_child(_container)

	_viewport = SubViewport.new()
	_viewport.own_world_3d = true
	_viewport.handle_input_locally = true
	_viewport.msaa_3d = Viewport.MSAA_4X
	_viewport.render_target_update_mode = SubViewport.UPDATE_WHEN_VISIBLE
	_container.add_child(_viewport)

	_chips_layer = Control.new()
	_chips_layer.name = "StationUI"
	_chips_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	_chips_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_chips_layer)

	_floor_bar = VBoxContainer.new()
	_floor_bar.name = "FloorSelector"
	_floor_bar.add_theme_constant_override("separation", 6)
	_floor_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_floor_bar.position = Vector2(10, 16)
	add_child(_floor_bar)

	build(GameState.current_venue)
	EventBus.prestige_performed.connect(func(_from: String, to_vid: String) -> void: retheme(to_vid))
	EventBus.wing_renovated.connect(_on_wing_renovated)

## (Re)build the diorama for `vid`. Callers check supports() first.
func build(vid: String) -> void:
	venue_id = vid
	if world != null:
		_viewport.remove_child(world)
		world.queue_free()
	for b in _chips + _ups:
		b.queue_free()
	_chips.clear()
	_ups.clear()
	_tier_set = false
	world = Venue3D.new()
	world.name = "Venue3D"
	world.venue_id = vid
	world.ticket_sold.connect(_on_ticket_sold)
	_viewport.add_child(world)
	_apply_quality_setting()
	_ground_focus = world.camera.focus
	_build_floor_bar()
	_refresh_stations()

func retheme(vid: String) -> void:
	if vid != venue_id and supports(vid):
		build(vid)

# --- Public API (VenueView, quests bar) -----------------------------------------

func set_rates(rates: Dictionary) -> void:
	_choke = str(rates.get("choke_id", ""))
	var vpv: Variant = rates.get("value_per_visitor")
	if vpv is BigNumber:
		_value_text = vpv.to_notation()
	var arrival := float(rates.get("arrival_per_s", 0.3))
	world.visitor_target = clampi(int(round(10.0 + arrival * 14.0)), 10, 30 if world.quality == "high" else 14)
	# Hero exhibits follow the gallery's value track (tier 1..4 across its cap).
	var cap: int = Economy.track_max_level(venue_id, "value")
	var lvl: int = GameState.dept_level(venue_id, "gallery", "value")
	var tier := 1 + mini(3, int(floor(4.0 * float(lvl) / float(maxi(cap, 1)))))
	if tier != world.exhibit_tier or not _tier_set:
		world.set_exhibit_tier(tier, _tier_set)
		_tier_set = true
	_refresh_stations()

func get_choke() -> String:
	return _choke

func theme_id() -> String:
	return venue_id

## Same code path as a real tap (tests call this directly). A tap on a floor
## that is still derelict opens Floors & Grandeur on that wing.
func simulate_tap(pos: Vector2) -> void:
	var hit: Dictionary = world.pick(pos)
	if hit.is_empty():
		return
	var wing := str(hit.get("wing", ""))
	if wing != "" and not bool(hit.get("open", true)):
		wing_requested(wing)
		return
	var dept := str(hit.get("dept", ""))
	if dept != "":
		dept_selected.emit(dept)

func wing_requested(wing_id: String) -> void:
	Popups.open(WINGS_PATH, {"focus": wing_id})

# --- Floor selector --------------------------------------------------------------

## One pill per storey on the left edge, top floor first: tap to glide there.
func _build_floor_bar() -> void:
	for b in _floor_btns:
		b.queue_free()
	_floor_btns.clear()
	var floors: Array = world.floors
	_floor_bar.visible = not floors.is_empty()
	for i in range(floors.size(), -1, -1):
		var label := "G" if i == 0 else str((floors[i - 1] as Dictionary).get("label", "%dF" % (i + 1)))
		var b := _round_button("Floor%d" % i, Color("#FFF4E0"), Color("#3A2A10"))
		b.text = label
		b.add_theme_font_size_override("font_size", 18)
		b.custom_minimum_size = Vector2(52, 44)
		b.size = Vector2(52, 44)
		_chips_layer.remove_child(b)
		_floor_bar.add_child(b)
		b.pressed.connect(go_to_floor.bind(i))
		_floor_btns.append(b)

## Glide the camera to floor `index` (0 = ground).
func go_to_floor(index: int) -> void:
	if index <= 0 or index > world.floors.size():
		world.camera.fly_to(_ground_focus)
		return
	var f: Dictionary = world.floors[index - 1]
	var r: Rect2 = f["rect"]
	world.camera.fly_to(Vector3(r.get_center().x, float(f["y"]), r.get_center().y + 2.0))

func _floor_in_view() -> int:
	var z: float = world.camera.focus.z
	var best := 0
	for i in world.floors.size():
		var r: Rect2 = (world.floors[i] as Dictionary)["rect"]
		if z <= r.end.y + 1.0:
			best = i + 1
	return best

func _style_floor_bar() -> void:
	if _floor_btns.is_empty():
		return
	var here := _floor_in_view()
	var n := _floor_btns.size()
	for k in n:
		var index := n - 1 - k
		var b := _floor_btns[k]
		var open := index == 0 or bool((world.floors[index - 1] as Dictionary)["open"])
		b.modulate = Color(1, 1, 1, 1.0 if index == here else 0.72)
		b.add_theme_color_override("font_color", Color("#3A2A10") if open else Color("#9A8F80"))

func _on_wing_renovated(vid: String, wing_id: String) -> void:
	if vid != venue_id or world == null:
		return
	for i in world.floors.size():
		if str((world.floors[i] as Dictionary)["id"]) == wing_id:
			go_to_floor(i + 1)
			return
	# The facade (no floor): pull back to the entrance for the grandeur moment.
	world.camera.fly_to(_ground_focus + Vector3(0, 0, 3.0))

## Screen-space anchor of ticket station `index` (for tests / quest routing).
func station_center(index: int) -> Vector2:
	if world.camera == null or index >= world.open_windows():
		return Vector2.ZERO
	return world.camera.unproject_position(world.station_anchor(index))

# --- Input -----------------------------------------------------------------------

## Pan and zoom belong to the ToyCamera inside the viewport; a press that
## barely moved is a tap on whatever room is under it.
func _on_world_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_pressed = true
			_press_at = event.position
			_press_travel = 0.0
		elif _pressed:
			_pressed = false
			if _press_travel <= TAP_SLOP:
				simulate_tap(event.position)
	elif event is InputEventMouseMotion and _pressed:
		_press_travel += event.relative.length()

# --- Station chips ---------------------------------------------------------------

func _refresh_stations() -> void:
	if world == null or not GameState.ready_flag:
		return
	var owned: int = GameState.dept_items(venue_id, "ticket").size()
	world.set_open_windows(maxi(owned, 1))
	world.refresh_signs()
	world.refresh_decor()
	var count: int = mini(owned, world.window_count())
	while _chips.size() < count:
		var index := _chips.size()
		var chip := _round_button("StationCash%d" % index, Color("#F2C14E"), Color("#8A5A12"))
		chip.pressed.connect(_on_station_cash.bind(index))
		_chips.append(chip)
		var up := _round_button("StationUpgrade%d" % index, Color("#3FAE6A"), Color("#1F5E3A"))
		up.tooltip_text = "Upgrade station %d" % (index + 1)
		up.pressed.connect(func() -> void: item_selected.emit("ticket", index))
		up.draw.connect(_draw_arrow.bind(up))
		_ups.append(up)
	while _chips.size() > count:
		_chips.pop_back().queue_free()
		_ups.pop_back().queue_free()
	for i in count:
		var pending: BigNumber = Economy.item_pending(venue_id, "ticket", i)
		var cooldown: int = Economy.item_collect_remaining(venue_id, "ticket", i)
		var level: int = GameState.item_level(venue_id, "ticket", i)
		var chip := _chips[i]
		if cooldown > 0:
			chip.text = "%d:%02d" % [cooldown / 60, cooldown % 60]
			chip.modulate = Color(1, 1, 1, 0.7)
			chip.tooltip_text = "Station %d · Ready in %s" % [i + 1, chip.text]
		elif not pending.is_zero():
			chip.text = "$" + pending.to_notation()
			chip.modulate = Color.WHITE
			chip.tooltip_text = "Station %d · Level %d\nCollect $%s" % [i + 1, level, pending.to_notation()]
		else:
			chip.text = str(i + 1)
			chip.modulate = Color(1, 1, 1, 0.85)
			chip.tooltip_text = "Station %d · Level %d\nOpen station upgrades" % [i + 1, level]
		var maxed: bool = level >= Economy.item_max_level()
		_ups[i].disabled = maxed
		_ups[i].set_meta("maxed", maxed)

func _round_button(node_name: String, fill: Color, rim: Color) -> Button:
	var b := Button.new()
	b.name = node_name
	b.custom_minimum_size = CHIP
	b.size = CHIP
	b.clip_text = true
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", 13)
	if _font:
		b.add_theme_font_override("font", _font)
	b.add_theme_color_override("font_color", Color("#3A2A10"))
	b.add_theme_color_override("font_hover_color", Color("#3A2A10"))
	b.add_theme_color_override("font_pressed_color", Color("#3A2A10"))
	for state in ["normal", "hover", "pressed", "disabled", "focus"]:
		var sb := StyleBoxFlat.new()
		sb.bg_color = fill.lightened(0.12) if state == "hover" else (fill.darkened(0.1) if state == "pressed" else fill)
		sb.set_corner_radius_all(26)
		sb.set_border_width_all(3)
		sb.border_color = rim
		sb.shadow_color = Color(0, 0, 0, 0.28)
		sb.shadow_size = 3
		sb.shadow_offset = Vector2(0, 3)
		if state == "focus":
			sb.draw_center = false
			sb.border_color = Color(0, 0, 0, 0)
			sb.shadow_size = 0
		b.add_theme_stylebox_override(state, sb)
	_chips_layer.add_child(b)
	return b

func _draw_arrow(b: Button) -> void:
	var c := b.size * 0.5
	var ink := Color.WHITE
	b.draw_line(c + Vector2(0, 10), c + Vector2(0, -9), ink, 4.0, true)
	b.draw_polyline(PackedVector2Array([c + Vector2(-8, -1), c + Vector2(0, -10), c + Vector2(8, -1)]), ink, 4.0, true)

## settings["gfx"]: "high", "low" or "auto" (default). Auto starts high and
## watches the frame rate; a sustained dip below 40 fps switches to low and
## remembers it for next time (settings["gfx_auto_low"]).
func _apply_quality_setting() -> void:
	var q := str(GameState.settings.get("gfx", "auto"))
	if q == "auto":
		q = "low" if bool(GameState.settings.get("gfx_auto_low", false)) else "high"
	world.apply_quality(q)
	_fps_samples.clear()

var _fps_samples: Array[float] = []
var _fps_clock := 0.0

func _watch_fps(delta: float) -> void:
	if str(GameState.settings.get("gfx", "auto")) != "auto" or world.quality == "low":
		return
	_fps_clock += delta
	if _fps_clock < 1.0:
		return
	_fps_clock = 0.0
	_fps_samples.append(Engine.get_frames_per_second())
	if _fps_samples.size() > 8:
		_fps_samples.pop_front()
	# Ignore the first seconds (navigation bake, shader warm-up).
	if _fps_samples.size() == 8:
		var total := 0.0
		for f in _fps_samples:
			total += f
		if total / 8.0 < 40.0:
			GameState.settings["gfx_auto_low"] = true
			world.apply_quality("low")

func _process(delta: float) -> void:
	if world == null or world.camera == null:
		return
	if is_visible_in_tree():
		_watch_fps(delta)
	_style_floor_bar()
	var cam: Camera3D = world.camera
	var bounds := Rect2(Vector2.ZERO, size).grow(-8.0)
	for i in _chips.size():
		var anchor: Vector3 = world.station_anchor(i)
		var p := cam.unproject_position(anchor)
		# Coin sits on the counter, upgrade arrow beside it.
		var chip_pos := p + Vector2(-CHIP.x - 2.0, -CHIP.y - 10.0)
		var shown := not cam.is_position_behind(anchor) and bounds.has_point(p)
		_chips[i].visible = shown
		_chips[i].position = chip_pos
		_ups[i].visible = shown and not bool(_ups[i].get_meta("maxed", false))
		_ups[i].position = chip_pos + Vector2(CHIP.x + 4.0, 0.0)

func _on_station_cash(index: int) -> void:
	var cooldown: int = Economy.item_collect_remaining(venue_id, "ticket", index)
	if cooldown > 0:
		EventBus.toast_requested.emit("Cashier ready in %d:%02d" % [cooldown / 60, cooldown % 60])
		return
	var amount: BigNumber = Economy.collect_item(venue_id, "ticket", index)
	if amount.is_zero():
		item_selected.emit("ticket", index)
		return
	world.pop_text(world.station_anchor(index) + Vector3(0, 0.4, 0), "+$" + amount.to_notation(), Color("#FFE680"), true)
	Juice.coin_burst(_chips[index].get_global_rect().get_center())
	UI.play_sfx(self, "buy")
	_refresh_stations()

func _on_ticket_sold(_index: int, at: Vector3) -> void:
	world.pop_text(at, "+$" + _value_text)
