extends Control
## Settings: sound, music, graphics quality, language, fullscreen (PC), replay
## the walkthrough, and the platform line (which store backend is live). Values
## live in GameState.settings and are saved with the game.

const UI := preload("res://scripts/ui/ui_kit.gd")
const Chrome := preload("res://scripts/ui/museum_chrome.gd")
const Popups := preload("res://scripts/ui/popup_manager.gd")
const Languages := preload("res://scripts/ui/languages.gd")

var _body: VBoxContainer

func setup(_payload: Dictionary) -> void:
	pass

func _ready() -> void:
	name = "SettingsScreen"
	var bg := ColorRect.new()
	bg.color = Chrome.BG
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_%s" % side, 20)
	add_child(margin)
	_body = VBoxContainer.new()
	_body.add_theme_constant_override("separation", 14)
	margin.add_child(_body)
	_build()

func _build() -> void:
	for c in _body.get_children():
		c.queue_free()
	_body.add_child(UI.make_display_label("Settings", 30, Chrome.INK))
	_body.add_child(_toggle("Music", "music", true))
	_body.add_child(_toggle("Sound effects", "sfx", true))
	var ps_n := get_node_or_null("/root/PlatformServices")
	if ps_n != null and bool(ps_n.call("notifications_available")):
		_body.add_child(_toggle("Notifications", "notifications", true))
	_body.add_child(_choice("Graphics", "gfx", ["auto", "high", "low"], ["Auto", "High", "Low"],
		"Low turns off shadows, anti-aliasing and the tilt-shift blur for older phones. Auto switches by itself if the museum runs slowly."))
	_body.add_child(_language_card())
	if OS.has_feature("pc"):
		var fs := Button.new()
		fs.name = "Fullscreen"
		var full := DisplayServer.window_get_mode() in [DisplayServer.WINDOW_MODE_FULLSCREEN, DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN]
		fs.text = "Windowed" if full else "Fullscreen"
		_style(fs, false)
		fs.pressed.connect(func() -> void:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED if full else DisplayServer.WINDOW_MODE_FULLSCREEN)
			_build())
		_body.add_child(_row("Display", fs))
	var tut := Button.new()
	tut.name = "ReplayTutorial"
	tut.text = "Replay walkthrough"
	_style(tut, false)
	tut.pressed.connect(func() -> void:
		GameState.settings["tutorial_step"] = 0
		var t := get_tree().root.find_child("Tutorial", true, false)
		if t != null:
			t.set("step", 0)
			t.call("_show")
		Popups.close_top())
	_body.add_child(_row("Help", tut))
	var ps := get_node_or_null("/root/PlatformServices")
	var backend := str(ps.get("backend")) if ps != null else "none"
	var store: String = str({"steam": "Steam", "epic": "Epic Games Store", "play_games": "Google Play Games",
		"game_center": "Game Center", "none": "Offline"}.get(backend, backend))
	if ps != null and bool(ps.call("can_show_platform_achievements")):
		var ach := Button.new()
		ach.name = "PlatformAchievements"
		ach.text = "View"
		_style(ach, false)
		ach.pressed.connect(func() -> void: ps.call("show_platform_achievements"))
		_body.add_child(_row(store, ach))
	if ps != null and not (ps.call("cloud_summary") as Dictionary).is_empty():
		_body.add_child(_cloud_card(ps, ps.call("cloud_summary") as Dictionary))
	_body.add_child(_label(tr("Achievements: %s · %d unlocked") % [store, (ps.call("unlocked") as Array).size() if ps != null else 0], 14, Chrome.DIM))
	var version := str(ProjectSettings.get_setting("application/config/version", ""))
	_body.add_child(_label(tr("Grand Exhibit · v%s") % (version if version != "" else "1.0.0"), 13, Chrome.DIM))

func _toggle(title: String, key: String, default_on: bool) -> Control:
	var on := bool(GameState.settings.get(key, default_on))
	var b := Button.new()
	b.name = "Toggle_%s" % key
	b.text = "On" if on else "Off"
	b.custom_minimum_size = Vector2(120, 52)
	_style(b, on)
	b.pressed.connect(func() -> void:
		GameState.settings[key] = not bool(GameState.settings.get(key, default_on))
		_build())
	return _row(title, b)

func _choice(title: String, key: String, values: Array, labels: Array, note: String) -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 8)
	var t := _label(title, 20, Chrome.INK)
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hb.add_child(t)
	var cur := str(GameState.settings.get(key, values[0]))
	for i in values.size():
		var b := Button.new()
		b.name = "%s_%s" % [key, values[i]]
		b.text = str(labels[i])
		b.custom_minimum_size = Vector2(92, 52)
		_style(b, cur == str(values[i]))
		var v := str(values[i])
		b.pressed.connect(func() -> void:
			GameState.settings[key] = v
			GameState.settings.erase("gfx_auto_low")
			var floor := get_tree().root.find_child("VenueFloor", true, false)
			if floor != null and floor.has_method("_apply_quality_setting"):
				floor.call("_apply_quality_setting")
			_build())
		hb.add_child(b)
	box.add_child(hb)
	box.add_child(_label(note, 14, Chrome.DIM))
	return _card(box)

## A cloud save further along than this phone's: the player decides. Loading
## restarts the game on it; keeping this phone's makes it the cloud copy.
func _cloud_card(ps: Node, summary: Dictionary) -> Control:
	var box := VBoxContainer.new()
	box.name = "CloudSave"
	box.add_theme_constant_override("separation", 8)
	box.add_child(_label("Cloud save found", 20, Chrome.INK))
	var venue := tr(str(DataLoader.get_venue(str(summary.get("venue", ""))).get("name", "")))
	box.add_child(_label(tr("%s · %d museums") % [venue, int(summary.get("museums", 0))], 15, Chrome.DIM))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var load_b := Button.new()
	load_b.name = "LoadCloud"
	load_b.text = "Load cloud save"
	load_b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_style(load_b, true)
	load_b.pressed.connect(func() -> void: ps.call("load_cloud_save"))
	row.add_child(load_b)
	var keep_b := Button.new()
	keep_b.name = "KeepLocal"
	keep_b.text = "Keep this phone's"
	keep_b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_style(keep_b, false)
	keep_b.pressed.connect(func() -> void:
		ps.call("keep_local_save")
		_build())
	row.add_child(keep_b)
	box.add_child(row)
	return _card(box)

## Automatic (the device's language) plus every complete catalog, each named
## in its own language.
func _language_card() -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	box.add_child(_label("Language", 20, Chrome.INK))
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	var cur := Languages.choice()
	var picks: Array = [["auto", tr("Automatic")]]
	picks.append_array(Languages.LANGUAGES)
	for p in picks:
		var code := str(p[0])
		var b := Button.new()
		b.name = "Lang_%s" % code
		b.text = str(p[1])
		if code != "auto":
			b.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED  # endonyms stay as written
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.clip_text = true
		_style(b, cur == code)
		b.add_theme_font_size_override("font_size", 16)
		b.pressed.connect(func() -> void:
			Languages.set_choice(code)
			_build())
		grid.add_child(b)
	box.add_child(grid)
	return _card(box)

func _row(title: String, control: Control) -> Control:
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 10)
	var t := _label(title, 20, Chrome.INK)
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	t.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	hb.add_child(t)
	hb.add_child(control)
	return _card(hb)

func _card(child: Control) -> PanelContainer:
	var card := PanelContainer.new()
	var sb := Chrome.panel(16, Chrome.PANEL)
	sb.set_content_margin_all(14)
	card.add_theme_stylebox_override("panel", sb)
	card.add_child(child)
	return card

func _style(b: Button, active: bool) -> void:
	b.add_theme_font_override("font", UI.font())
	b.add_theme_font_size_override("font_size", 18)
	if b.custom_minimum_size.y < 52:
		b.custom_minimum_size.y = 52
	Chrome.button(b, active)

func _label(text: String, size_px: int, color: Color) -> Label:
	var l := UI.make_label(text, size_px)
	l.add_theme_color_override("font_color", color)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return l
