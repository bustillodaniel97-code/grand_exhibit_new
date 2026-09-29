extends SceneTree
## Guided tour — boots the real game (main.tscn) in the window and drives it
## through a timeline of screens, with a caption for each step. Record it with
## Godot's movie maker to get a video of the game:
##
##   GRAND_EXHIBIT_TEST_RUN=1 xvfb-run -a -s "-screen 0 800x1400x24" \
##     godot --path . --resolution 720x1280 --fixed-fps 24 \
##     --write-movie /tmp/tour.avi -s tools/tour.gd
##
## Dev tool only (outside tests/). GRAND_EXHIBIT_TEST_RUN keeps it off the
## player's save; the autosave is stopped too.

const MAIN := "res://scenes/main.tscn"

## [seconds, action, argument, caption]
const STEPS := [
	[0.0, "", "", "Grand Exhibit · the museum floor"],
	[5.0, "floor", "1", "New floors: the 2F hall, furnished"],
	[9.0, "floor", "2", "…and the 3F terrace above it"],
	[13.0, "floor", "0", "Back to the ground floor"],
	[15.0, "wish", "collector", "NEW · VIP wish: meet it before the timer runs out"],
	[21.0, "open", "res://scenes/meta/wings_screen.tscn", "Floors & Grandeur"],
	[26.0, "close", "", ""],
	[26.5, "open", "res://scenes/events/cafe_screen.tscn", "NEW · Seasonal café: the Frost Fair (snow!)"],
	[33.0, "close", "", ""],
	[33.5, "open", "res://scenes/meta/settings_screen.tscn", "NEW · Settings: language, notifications"],
	[37.0, "press", "Lang_es", "Switching the game to Spanish, live"],
	[41.0, "close", "", "Everything is now in Spanish"],
	[44.0, "open", "res://scenes/digsite/dig_site_screen.tscn", "The Dig Site, in Spanish"],
	[49.0, "close", "", ""],
	[49.5, "open", "res://scenes/store/store_screen.tscn", "The Store, in Spanish"],
	[54.0, "close", "", ""],
	[54.5, "open", "res://scenes/meta/prestige_screen.tscn", "Next museum: re-rendered previews"],
	[60.0, "close", "", ""],
	[60.5, "press_lang", "de", "…and German, French, Italian, Portuguese"],
	[64.0, "end", "", ""],
]

var _t := 0.0
var _next := 0
var _caption: Label
var _seeded := false

func _initialize() -> void:
	root.add_child((load(MAIN) as PackedScene).instantiate())
	var layer := CanvasLayer.new()
	layer.layer = 100
	root.add_child(layer)
	var panel := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.1, 0.08, 0.2, 0.82)
	sb.set_corner_radius_all(14)
	sb.set_content_margin_all(12)
	panel.add_theme_stylebox_override("panel", sb)
	panel.position = Vector2(30, 1010)
	panel.custom_minimum_size = Vector2(660, 0)
	layer.add_child(panel)
	_caption = Label.new()
	_caption.add_theme_font_override("font", load("res://assets/fonts/Quicksand-Bold.ttf"))
	_caption.add_theme_font_size_override("font_size", 24)
	_caption.add_theme_color_override("font_color", Color("#FFF3B0"))
	_caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_caption.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_caption.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	panel.add_child(_caption)

func _process(delta: float) -> bool:
	_t += delta
	if not _seeded and _t > 0.3:
		_seeded = true
		_seed()
	while _next < STEPS.size() and _t >= float(STEPS[_next][0]):
		_run(STEPS[_next])
		_next += 1
	return false

## A developed museum: cash, levels, reputation, two renovated floors, the
## café live and dressed for winter.
func _seed() -> void:
	var ss: Node = root.get_node("SaveSystem")
	ss.set_process(false)
	var gs: Node = root.get_node("GameState")
	var dl: Node = root.get_node("DataLoader")
	var BN: GDScript = load("res://scripts/core/big_number.gd")
	gs.settings["tutorial_step"] = 99
	var tut := root.find_child("Tutorial", true, false)
	if tut != null:
		tut.visible = false
	var th: Array = dl.core.get("reputation", {}).get("thresholds_mantissa", [])
	if th.size() >= 5:
		gs.reputation_xp = BN.from_float(float(th[4]))
	gs.add_cash(BN.from_parts(5.0, 6))
	gs.gems += 200
	var econ: Node = root.get_node("Economy")
	for _i in 6:
		for dept in dl.core.get("departments", {}).keys():
			for track in ["speed", "value"]:
				econ.purchase_upgrade(gs.current_venue, str(dept), track)
	var WS: GDScript = load("res://scripts/meta/wing_system.gd")
	var ids: Array = []
	for ms in dl.milestones.get(gs.current_venue, []):
		ids.append(str(ms["id"]))
	gs.venue_state(gs.current_venue)["milestones"] = ids
	for _i in 2:
		var w: Dictionary = WS.next_wing(gs.current_venue)
		if w.is_empty():
			break
		gs.add_cash(WS.price(gs.current_venue, str(w["id"])).add(BN.from_float(1.0)))
		WS.renovate(gs.current_venue, str(w["id"]))
	var CS: GDScript = load("res://scripts/events/cafe_system.gd")
	CS.tick()
	(CS._raw() as Dictionary)["season"] = "frost_fair"

func _run(step: Array) -> void:
	# Loaded at runtime: popup_manager names autoloads, which a -s script can't
	# see at compile time.
	var Popups: GDScript = load("res://scripts/ui/popup_manager.gd")
	var action := str(step[1])
	var arg := str(step[2])
	if str(step[3]) != "":
		_caption.text = str(step[3])
	match action:
		"floor":
			var fl := root.find_child("VenueFloor", true, false)
			if fl != null and fl.has_method("go_to_floor"):
				fl.call("go_to_floor", int(arg))
		"wish":
			var VS: GDScript = load("res://scripts/meta/visitor_system.gd")
			(root.get_node("GameState").visitors_state as Dictionary)["tip_ready"] = 0
			var r: Dictionary = VS.accept_request(arg)
			if not r.is_empty():
				root.get_node("EventBus").toast_requested.emit(VS.request_text(r))
		"open":
			Popups.open(arg, {})
		"close":
			for _i in 3:
				Popups.close_top()
		"press":
			var b := root.find_child(arg, true, false)
			if b is BaseButton:
				(b as BaseButton).pressed.emit()
		"press_lang":
			(load("res://scripts/ui/languages.gd") as GDScript).call("set_choice", arg)
		"end":
			(load("res://scripts/ui/languages.gd") as GDScript).call("set_choice", "auto")
			quit(0)
