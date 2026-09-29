extends Control
## Dig Site — the excavation mini game (opened from the Expedition tab).
##
## Swing the PICK (fast: two layers, but it cracks an artifact it breaks onto)
## or the BRUSH (one gentle layer) at the pit to uncover this museum's next
## artifact. Coins, gems and energy crystals turn up along the way. A recovered
## artifact joins the museum's collection and raises its income.
##
## Rules: scripts/digsite/dig_logic.gd. State and rewards: dig_system.gd. The
## 3D pit: scenes/digsite/dig_pit.gd.

const UI := preload("res://scripts/ui/ui_kit.gd")
const Chrome := preload("res://scripts/ui/museum_chrome.gd")
const Popups := preload("res://scripts/ui/popup_manager.gd")
const DigSystem := preload("res://scripts/digsite/dig_system.gd")
const DigLogic := preload("res://scripts/digsite/dig_logic.gd")
const DigPit := preload("res://scenes/digsite/dig_pit.gd")
const Juice := preload("res://scripts/ui/juice.gd")
const EXPEDITION_PATH := "res://scenes/events/expedition_screen.tscn"
const AD_PLACEMENT := "dig_energy"

var tool := "pick"
var venue_id := ""
var pit: Node3D

var _viewport: SubViewport
var _container: SubViewportContainer
var _title: Label
var _subtitle: Label
var _energy_bar: ProgressBar
var _energy_label: Label
var _progress_label: Label
var _pick_btn: Button
var _brush_btn: Button
var _ad_btn: Button
var _gem_btn: Button
var _collection_row: HBoxContainer
var _result: PanelContainer
var _press := Vector2.ZERO
var _pressed := false

func setup(_payload: Dictionary) -> void:
	pass

func _ready() -> void:
	name = "DigSiteScreen"
	venue_id = GameState.current_venue
	var bg := ColorRect.new()
	bg.color = Chrome.BG
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right"]:
		margin.add_theme_constant_override("margin_%s" % side, 14)
	margin.add_theme_constant_override("margin_top", 8)
	margin.add_theme_constant_override("margin_bottom", 10)
	add_child(margin)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
	margin.add_child(col)

	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 8)
	col.add_child(head)
	var titles := VBoxContainer.new()
	titles.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	titles.add_theme_constant_override("separation", 0)
	head.add_child(titles)
	titles.add_child(UI.make_display_label("DIG SITE", 12, Chrome.BRASS))
	_title = UI.make_display_label("", 26, Chrome.INK)
	titles.add_child(_title)
	_subtitle = _label("", 15, Chrome.DIM)
	titles.add_child(_subtitle)
	if GameState.feature_unlocked("expedition"):
		var boss := _button("Boss Expedition", false)
		boss.custom_minimum_size = Vector2(150, 48)
		boss.add_theme_font_size_override("font_size", 15)
		boss.pressed.connect(func() -> void: Popups.open(EXPEDITION_PATH))
		head.add_child(boss)

	var energy_row := HBoxContainer.new()
	energy_row.add_theme_constant_override("separation", 8)
	col.add_child(energy_row)
	var ebox := VBoxContainer.new()
	ebox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ebox.add_theme_constant_override("separation", 2)
	energy_row.add_child(ebox)
	_energy_label = _label("", 15, Chrome.INK)
	ebox.add_child(_energy_label)
	_energy_bar = ProgressBar.new()
	_energy_bar.show_percentage = false
	_energy_bar.custom_minimum_size = Vector2(0, 14)
	_energy_bar.add_theme_stylebox_override("background", UI.make_bar_bg())
	_energy_bar.add_theme_stylebox_override("fill", UI.make_bar_fill("green"))
	ebox.add_child(_energy_bar)
	_ad_btn = _button("Ad +%d" % DigSystem.ad_refill_amount(), false)
	_ad_btn.name = "AdRefill"
	_ad_btn.custom_minimum_size = Vector2(100, 48)
	_ad_btn.pressed.connect(_on_ad_refill)
	energy_row.add_child(_ad_btn)
	_gem_btn = _button("%d gems: Full" % int((DigSystem.config().get("energy", {}) as Dictionary).get("gem_refill_cost", 20)), false)
	_gem_btn.name = "GemRefill"
	_gem_btn.custom_minimum_size = Vector2(130, 48)
	_gem_btn.pressed.connect(_on_gem_refill)
	energy_row.add_child(_gem_btn)

	_container = SubViewportContainer.new()
	_container.name = "Pit"
	_container.stretch = true
	_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_container.custom_minimum_size = Vector2(0, 420)
	_container.mouse_filter = Control.MOUSE_FILTER_STOP
	_container.gui_input.connect(_on_pit_input)
	col.add_child(_container)
	_viewport = SubViewport.new()
	_viewport.own_world_3d = true
	_viewport.msaa_3d = Viewport.MSAA_4X
	_container.add_child(_viewport)
	pit = DigPit.new()
	_viewport.add_child(pit)

	_progress_label = _label("", 16, Chrome.INK)
	_progress_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(_progress_label)

	var tools := HBoxContainer.new()
	tools.add_theme_constant_override("separation", 10)
	col.add_child(tools)
	_pick_btn = _button("Pick\nfast · can crack", true)
	_pick_btn.name = "Pick"
	_pick_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_pick_btn.pressed.connect(func() -> void: set_tool("pick"))
	tools.add_child(_pick_btn)
	_brush_btn = _button("Brush\ngentle · safe", false)
	_brush_btn.name = "Brush"
	_brush_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_brush_btn.pressed.connect(func() -> void: set_tool("brush"))
	tools.add_child(_brush_btn)

	col.add_child(_label("MUSEUM COLLECTION", 12, Chrome.BRASS))
	_collection_row = HBoxContainer.new()
	_collection_row.name = "Collection"
	_collection_row.add_theme_constant_override("separation", 6)
	col.add_child(_collection_row)

	_result = PanelContainer.new()
	_result.name = "Result"
	_result.visible = false
	_result.set_anchors_preset(Control.PRESET_CENTER)
	add_child(_result)

	var t := Timer.new()
	t.wait_time = 1.0
	t.autostart = true
	t.timeout.connect(_refresh_energy)
	add_child(t)
	if not AdService.ad_result.is_connected(_on_ad_result):
		AdService.ad_result.connect(_on_ad_result)
	_load_site()

func _load_site() -> void:
	var site: Dictionary = DigSystem.current_site(venue_id)
	var def: Dictionary = DigSystem.site_def(venue_id)
	pit.setup(site, def, DigSystem.artifact(venue_id, str(site["artifact"])))
	_title.text = str(def.get("name", "Dig Site"))
	_refresh()
	if bool(site.get("done", false)):
		_show_result({"artifact": site["artifact"], "quality": DigLogic.quality(site), "first": false})

func set_tool(t: String) -> void:
	tool = t
	Chrome.button(_pick_btn, tool == "pick")
	Chrome.button(_brush_btn, tool == "brush")

## Same path as a tap on the pit (tests call this directly).
func swing_at(x: int, y: int) -> Dictionary:
	var res: Dictionary = DigSystem.swing(venue_id, x, y, tool)
	if bool(res.get("ok", false)):
		pit.apply_result(x, y, res)
		UI.play_sfx(self, "click")
		var find: Dictionary = res.get("find", {})
		if not find.is_empty() and str(find["kind"]) in ["coins", "gems"]:
			var at: Vector2 = pit.camera.unproject_position(pit.cell_center(x, y)) + _container.get_global_rect().position
			Juice.coin_burst(at, "gems" if str(find["kind"]) == "gems" else "cash", 6)
		if bool(res.get("complete", false)):
			get_tree().create_timer(1.2).timeout.connect(func() -> void:
				if is_instance_valid(self):
					_show_result(res))
	else:
		match str(res.get("reason", "")):
			"energy":
				EventBus.toast_requested.emit("Out of energy: it refills over time, or watch an ad")
			"rock":
				EventBus.toast_requested.emit("Rock! Only the pick breaks it")
	_refresh()
	return res

func _on_pit_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_pressed = true
			_press = event.position
		elif _pressed:
			_pressed = false
			if _press.distance_to(event.position) < 16.0 and not _result.visible:
				var cell: Array = pit.cell_at(event.position)
				if not cell.is_empty():
					swing_at(int(cell[0]), int(cell[1]))

func _refresh() -> void:
	var site: Dictionary = DigSystem.current_site(venue_id)
	var art := DigSystem.artifact(venue_id, str(site["artifact"]))
	var col: Dictionary = DigSystem.collection(venue_id)
	_subtitle.text = "Collection %d / %d · each find raises %s's income" % [col.size(), DigSystem.artifacts(venue_id).size(),
		str(DataLoader.get_venue(venue_id).get("name", "the museum"))]
	var stars := DigLogic.quality(site)
	var hidden := str(art.get("name", "Artifact")) if bool(site.get("done", false)) else "Buried " + str(art.get("rarity", "common"))
	_progress_label.text = "%s · %d%% uncovered · quality %s" % [hidden, int(DigLogic.progress(site) * 100.0),
		"★★★".substr(0, stars) + "☆☆☆".substr(0, 3 - stars)]
	for c in _collection_row.get_children():
		c.queue_free()
	for a in DigSystem.artifacts(venue_id):
		var have := col.has(str(a["id"]))
		var chip := PanelContainer.new()
		var sb := Chrome.panel(10, Chrome.RAISED if have else Chrome.PANEL)
		sb.set_content_margin_all(6)
		if have:
			sb.border_color = Color(str((a.get("colors", ["#FFD34D"]) as Array)[0]))
			sb.set_border_width_all(2)
		chip.add_theme_stylebox_override("panel", sb)
		chip.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var l := _label(str(a["name"]) if have else "?", 12, Chrome.INK if have else Chrome.DIM)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		chip.add_child(l)
		_collection_row.add_child(chip)
	_refresh_energy()

func _refresh_energy() -> void:
	var e: int = DigSystem.energy()
	var mx: int = DigSystem.max_energy()
	_energy_bar.max_value = mx
	_energy_bar.value = mini(e, mx)
	var nxt: int = DigSystem.next_energy_in()
	_energy_label.text = "Energy %d / %d%s" % [e, mx, ("  ·  +1 in %d:%02d" % [nxt / 60, nxt % 60]) if nxt > 0 else ""]
	_gem_btn.disabled = e >= mx

func _on_ad_refill() -> void:
	AdService.show_rewarded(AD_PLACEMENT, {"venue": venue_id})

func _on_ad_result(placement_id: String, success: bool, ctx: Dictionary) -> void:
	if placement_id != AD_PLACEMENT or not success:
		return
	if not AdService.consume_reward_token(str(ctx.get("reward_token", "")), AD_PLACEMENT):
		return
	DigSystem.add_energy(DigSystem.ad_refill_amount())
	EventBus.toast_requested.emit("+%d energy" % DigSystem.ad_refill_amount())
	_refresh_energy()

func _on_gem_refill() -> void:
	if DigSystem.refill_with_gems():
		UI.play_sfx(self, "buy")
		_refresh_energy()
	else:
		EventBus.toast_requested.emit("Not enough gems")

func _show_result(res: Dictionary) -> void:
	for c in _result.get_children():
		c.queue_free()
	var art := DigSystem.artifact(venue_id, str(res.get("artifact", "")))
	var sb := Chrome.panel(18, Chrome.RAISED)
	sb.set_content_margin_all(18)
	sb.border_color = Color("#FFD34D")
	sb.set_border_width_all(3)
	_result.add_theme_stylebox_override("panel", sb)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	box.custom_minimum_size = Vector2(420, 0)
	_result.add_child(box)
	box.add_child(UI.make_display_label("ARTIFACT RECOVERED!", 14, Chrome.BRASS))
	box.add_child(UI.make_display_label(str(art.get("name", "")), 28, Chrome.INK))
	var q := int(res.get("quality", 3))
	box.add_child(_label("Quality " + "★★★".substr(0, q) + "☆☆☆".substr(0, 3 - q), 20, Color("#FFD34D")))
	var bonus := float((DigSystem.config().get("rewards", {}) as Dictionary).get("income_bonus", 0.04)) * float(q) / 3.0
	box.add_child(_label("Now on display: +%d%% museum income" % int(round(bonus * 100.0)), 17, Chrome.TEAL))
	if int(res.get("bonus_gems", 0)) > 0:
		box.add_child(_label("+%d gems for a first find" % int(res["bonus_gems"]), 16, Chrome.INK))
	if DigSystem.set_complete(venue_id):
		box.add_child(_label("Collection complete! Set bonus active.", 16, Color("#FFD34D")))
	var nxt := _button("Next dig site", true)
	nxt.name = "NextSite"
	nxt.pressed.connect(func() -> void:
		DigSystem.next_site(venue_id)
		_result.visible = false
		_load_site())
	box.add_child(nxt)
	_result.visible = true
	_result.reset_size()
	_result.position = (size - _result.get_combined_minimum_size()) * 0.5

func _button(text: String, primary: bool) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size.y = 56
	b.add_theme_font_override("font", UI.font())
	b.add_theme_font_size_override("font_size", 17)
	Chrome.button(b, primary)
	return b

func _label(text: String, size_px: int, color: Color) -> Label:
	var l := UI.make_label(text, size_px)
	l.add_theme_color_override("font_color", color)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return l
