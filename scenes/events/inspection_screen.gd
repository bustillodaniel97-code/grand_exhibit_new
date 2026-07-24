extends Control
## Inspection Frenzy event screen (SPEC §4 events.json, §6 battler, §11 registry).
## Gate: feature_unlocked("inspection") (Day 2). Time-boxed windows from
## events.json duration_hours/cooldown_hours, state persisted in
## GameState.event_state["inspection_frenzy"].

const BattleView = preload("res://scenes/events/battle_view.gd")
const BattleMath = preload("res://scripts/events/battle_math.gd")

const BG := Color("#F5EFE0")
const INK := Color("#33312E")
const PANEL := Color("#FFFDF6")
const ACCENT := Color("#C4703F")
const BRASS := Color("#B08D3E")
const SAGE := Color("#7A9B76")
const SPEC_GLYPH := {"promotions": "P", "ticket": "T", "archive": "A", "gallery": "G"}
const SPEC_COLOR := {"promotions": Color("#8E6C8A"), "ticket": Color("#C4703F"),
	"archive": Color("#5B7B8C"), "gallery": Color("#B08D3E")}

var _payload := {}
var _event: Dictionary = {}
var _selected: Array = []       # manager ids (max 3)
var _battle: Control = null
var _outcome: Control = null
var _status_label: Label
var _start_button: Button
var _timer: Timer


func setup(payload: Dictionary) -> void:
	_payload = payload


func _ready() -> void:
	_event = DataLoader.get_event("inspection_frenzy")
	_timer = Timer.new()
	_timer.wait_time = 1.0
	_timer.autostart = true
	_timer.timeout.connect(_refresh_window_status)
	add_child(_timer)
	_build()


func _es() -> Dictionary:
	if not GameState.event_state.has("inspection_frenzy"):
		GameState.event_state["inspection_frenzy"] = {
			"stage": 0, "opened_at": 0, "team_power_at_open": 0.0, "completed": []}
	return GameState.event_state["inspection_frenzy"]


func _window_active(now: int) -> bool:
	var es: Dictionary = _es()
	var dur: int = int(float(_event.get("duration_hours", 48)) * 3600.0)
	return int(es.get("opened_at", 0)) > 0 and now < int(es["opened_at"]) + dur


func _cooldown_over(now: int) -> bool:
	var es: Dictionary = _es()
	if int(es.get("opened_at", 0)) <= 0:
		return true
	var cd: int = int(float(_event.get("cooldown_hours", 72)) * 3600.0)
	return now >= int(es["opened_at"]) + cd


func _owned_team_power() -> float:
	var pairs: Array = []
	for mid in GameState.managers_state.keys():
		var st: Dictionary = GameState.managers_state[mid]
		if int(st.get("cards", 0)) >= 1:
			pairs.append({"def": DataLoader.get_manager_def(mid), "state": st})
	return BattleMath.team_power(pairs)


func _build() -> void:
	for c in get_children():
		if c != _timer:
			c.queue_free()
	var bg_panel := Panel.new()
	bg_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg_panel.add_theme_stylebox_override("panel", _style(BG, 0))
	add_child(bg_panel)

	if not GameState.feature_unlocked("inspection"):
		var lock := _center_label("Inspection Frenzy\n\nUnlocks on Day 2")
		add_child(lock)
		return

	var scroll := ScrollContainer.new()
	scroll.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(scroll)
	var root := VBoxContainer.new()
	root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.add_theme_constant_override("separation", 12)
	scroll.add_child(root)
	var pad := MarginContainer.new()
	root.add_child(pad)

	var title := Label.new()
	title.text = str(_event.get("name", "Inspection Frenzy"))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 34)
	title.add_theme_color_override("font_color", INK)
	root.add_child(title)

	_status_label = Label.new()
	_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status_label.add_theme_color_override("font_color", INK)
	root.add_child(_status_label)

	_start_button = Button.new()
	_start_button.text = "Start Inspection"
	_start_button.custom_minimum_size = Vector2(0, 56)
	_style_button(_start_button, ACCENT)
	_start_button.pressed.connect(_on_start_pressed)
	root.add_child(_start_button)

	# Team picker.
	var team_head := Label.new()
	team_head.text = "Pick your team (up to 3 owned managers)"
	team_head.add_theme_font_size_override("font_size", 20)
	team_head.add_theme_color_override("font_color", INK)
	root.add_child(team_head)
	var flow := HFlowContainer.new()
	flow.add_theme_constant_override("h_separation", 10)
	flow.add_theme_constant_override("v_separation", 10)
	root.add_child(flow)
	var owned_count := 0
	for mid in GameState.managers_state.keys():
		var st: Dictionary = GameState.managers_state[mid]
		if int(st.get("cards", 0)) < 1:
			continue
		owned_count += 1
		flow.add_child(_manager_card(mid, st))
	if owned_count == 0:
		var none := Label.new()
		none.text = "No managers yet — open lootboxes to recruit a team."
		none.add_theme_color_override("font_color", INK)
		root.add_child(none)

	# Stage list.
	var stages_head := Label.new()
	stages_head.text = "Stages"
	stages_head.add_theme_font_size_override("font_size", 20)
	stages_head.add_theme_color_override("font_color", INK)
	root.add_child(stages_head)
	var es: Dictionary = _es()
	var stages: Array = _event.get("stages", [])
	for i in stages.size():
		root.add_child(_stage_row(i, stages[i], es))
	if int(es.get("stage", 0)) >= stages.size() and _window_active(ClockGuard.now()):
		var done := Label.new()
		done.text = "All stages cleared! Come back after the cooldown."
		done.add_theme_color_override("font_color", SAGE)
		root.add_child(done)

	_refresh_window_status()


func _manager_card(mid: String, st: Dictionary) -> Control:
	var def: Dictionary = DataLoader.get_manager_def(mid)
	var btn := Button.new()
	btn.toggle_mode = true
	btn.custom_minimum_size = Vector2(210, 92)
	btn.button_pressed = _selected.has(mid)
	var spec: String = str(def.get("specialty", ""))
	var col: Color = SPEC_COLOR.get(spec, BRASS)
	btn.add_theme_stylebox_override("normal", _style(PANEL, 12, col))
	btn.add_theme_stylebox_override("pressed", _style(col, 12, INK))
	btn.add_theme_stylebox_override("hover", _style(PANEL.lightened(0.03), 12, col))
	btn.add_theme_stylebox_override("disabled", _style(PANEL.darkened(0.1), 12))
	var atk: float = BattleMath.manager_attack(def, st)
	btn.text = "%s %s\nLv %d · Rank %d\nPower %d" % [
		str(SPEC_GLYPH.get(spec, "?")), str(def.get("name", mid)),
		int(st.get("level", 1)), int(st.get("rank", 1)), int(round(atk))]
	btn.toggled.connect(func(on: bool) -> void:
		if on:
			if _selected.size() >= 3:
				btn.button_pressed = false
				return
			_selected.append(mid)
		else:
			_selected.erase(mid))
	btn.pressed.connect(func() -> void:
		_build())  # refresh card enabled/disabled states
	if not _selected.has(mid) and _selected.size() >= 3:
		btn.disabled = true
	return btn


func _stage_row(i: int, stage: Dictionary, es: Dictionary) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	var unlocked: bool = i <= int(es.get("stage", 0))
	var cleared: bool = i < int(es.get("stage", 0)) or es.get("completed", []).has(i)
	var btn := Button.new()
	btn.custom_minimum_size = Vector2(150, 52)
	btn.text = ("✓ " if cleared else "") + "Stage %d" % (i + 1)
	_style_button(btn, SAGE if cleared else ACCENT)
	btn.disabled = not unlocked or not _window_active(ClockGuard.now()) \
		or _selected.is_empty() or cleared
	btn.pressed.connect(_on_play_stage.bind(i))
	row.add_child(btn)
	var info := Label.new()
	info.text = "%s\nHP ~%d · %d moves" % [
		_rewards_preview(stage.get("rewards", {})),
		int(round(BattleMath.stage_boss_hp(_event, i, float(es.get("team_power_at_open", 0.0))))),
		int(stage.get("moves", 20))]
	info.add_theme_color_override("font_color", INK)
	row.add_child(info)
	return row


func _rewards_preview(rewards: Dictionary) -> String:
	var parts: Array = []
	var box_id: String = str(rewards.get("cards_box", ""))
	if box_id != "":
		parts.append(str(DataLoader.get_lootbox(box_id).get("name", box_id)))
	if int(rewards.get("gems", 0)) > 0:
		parts.append("%d gems" % int(rewards["gems"]))
	if float(rewards.get("insight_m", 0.0)) > 0.0:
		parts.append("%s insight" % str(rewards.get("insight_m")))
	return " · ".join(parts)


func _refresh_window_status() -> void:
	if _status_label == null or not is_instance_valid(_status_label):
		return
	var now: int = ClockGuard.now()
	var es: Dictionary = _es()
	if _window_active(now):
		var left: int = int(es["opened_at"]) + int(float(_event.get("duration_hours", 48)) * 3600.0) - now
		_status_label.text = "Window OPEN — closes in %s · team power at open: %d" % [
			_fmt_hours(left), int(round(float(es.get("team_power_at_open", 0.0))))]
		_start_button.visible = false
	else:
		if _cooldown_over(now):
			_status_label.text = "Next inspection: READY"
			_start_button.visible = true
			_start_button.disabled = false
			_start_button.text = "Start Inspection"
		else:
			var left: int = int(es.get("opened_at", 0)) \
				+ int(float(_event.get("cooldown_hours", 72)) * 3600.0) - now
			_status_label.text = "Next inspection in %s" % _fmt_hours(left)
			_start_button.visible = true
			_start_button.disabled = true
			_start_button.text = "On cooldown"


func _on_start_pressed() -> void:
	var now: int = ClockGuard.now()
	if not _cooldown_over(now):
		return
	var es: Dictionary = _es()
	es["opened_at"] = now
	es["stage"] = 0
	es["completed"] = []
	es["team_power_at_open"] = _owned_team_power()
	Analytics.log_event("inspection_open", {"team_power": es["team_power_at_open"]})
	_build()


func _on_play_stage(stage_index: int) -> void:
	var es: Dictionary = _es()
	if not _window_active(ClockGuard.now()) or _selected.is_empty():
		return
	var stage: Dictionary = _event.get("stages", [])[stage_index]
	var team: Array = []
	for mid in _selected:
		team.append({"def": DataLoader.get_manager_def(mid),
			"state": GameState.managers_state[mid], "id": mid})
	_battle = BattleView.new()
	_battle.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_battle)
	_battle.setup_battle({
		"boss_name": "Chief Inspector — Stage %d" % (stage_index + 1),
		"boss_hp": BattleMath.stage_boss_hp(_event, stage_index,
			float(es.get("team_power_at_open", 0.0))),
		"moves": int(stage.get("moves", 20)),
		"team": team,
	})
	_battle.battle_finished.connect(_on_battle_finished.bind(stage_index), CONNECT_ONE_SHOT)


func _on_battle_finished(result: String, stage_index: int) -> void:
	Analytics.log_event("inspection_stage", {"stage": stage_index, "result": result})
	if result == "win":
		var stage: Dictionary = _event.get("stages", [])[stage_index]
		var applied: Dictionary = _apply_rewards(stage.get("rewards", {}))
		var es: Dictionary = _es()
		if not es.get("completed", []).has(stage_index):
			es["completed"].append(stage_index)
		es["stage"] = maxi(int(es.get("stage", 0)), stage_index + 1)
		EventBus.event_stage_completed.emit("inspection_frenzy", stage_index, applied)
		_show_outcome("Stage %d cleared!\n%s" % [stage_index + 1, _applied_text(applied)])
	else:
		_show_outcome("The inspectors were unimpressed.\nAdjust your team and retry!")


func _apply_rewards(rewards: Dictionary) -> Dictionary:
	var applied := {"cards": {}, "gems": 0, "insight_m": 0.0}
	var box_id: String = str(rewards.get("cards_box", ""))
	if box_id != "":
		var rng := RandomNumberGenerator.new()
		rng.randomize()
		var drawn: Dictionary = BattleMath.draw_cards(
			DataLoader.get_lootbox(box_id), DataLoader.managers, rng)
		applied["cards"] = drawn
		for mid in drawn.keys():
			if GameState.managers_state.has(mid):
				GameState.managers_state[mid]["cards"] = \
					int(GameState.managers_state[mid].get("cards", 0)) + int(drawn[mid])
				EventBus.manager_obtained.emit(mid, int(drawn[mid]))
	var gems: int = int(rewards.get("gems", 0))
	if gems > 0:
		GameState.add_gems(gems)
		applied["gems"] = gems
	var insight_m: float = float(rewards.get("insight_m", 0.0))
	if insight_m > 0.0:
		GameState.add_insight(BigNumber.from_float(insight_m))
		applied["insight_m"] = insight_m
	return applied


func _applied_text(applied: Dictionary) -> String:
	var parts: Array = []
	var cards: Dictionary = applied.get("cards", {})
	for mid in cards.keys():
		var def: Dictionary = DataLoader.get_manager_def(mid)
		parts.append("%dx %s" % [int(cards[mid]), str(def.get("name", mid))])
	if int(applied.get("gems", 0)) > 0:
		parts.append("%d gems" % int(applied["gems"]))
	if float(applied.get("insight_m", 0.0)) > 0.0:
		parts.append("%s insight" % str(applied["insight_m"]))
	return "Rewards: " + (" · ".join(parts) if not parts.is_empty() else "none")


func _show_outcome(text: String) -> void:
	_outcome = Panel.new()
	_outcome.set_anchors_preset(Control.PRESET_FULL_RECT)
	_outcome.add_theme_stylebox_override("panel", _style(Color(0, 0, 0, 0.6), 0))
	add_child(_outcome)
	var card := Panel.new()
	card.custom_minimum_size = Vector2(560, 320)
	card.position = Vector2(80, 480)
	card.add_theme_stylebox_override("panel", _style(PANEL, 12, BRASS))
	_outcome.add_child(card)
	var v := VBoxContainer.new()
	v.set_anchors_preset(Control.PRESET_FULL_RECT)
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_theme_constant_override("separation", 20)
	card.add_child(v)
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_font_size_override("font_size", 22)
	l.add_theme_color_override("font_color", INK)
	v.add_child(l)
	var btn := Button.new()
	btn.text = "Continue"
	btn.custom_minimum_size = Vector2(0, 56)
	_style_button(btn, ACCENT)
	btn.pressed.connect(func() -> void:
		if _battle != null:
			_battle.queue_free()
			_battle = null
		_outcome.queue_free()
		_outcome = null
		_build())
	v.add_child(btn)


func _center_label(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.set_anchors_preset(Control.PRESET_FULL_RECT)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", 28)
	l.add_theme_color_override("font_color", INK)
	return l


func _fmt_hours(seconds: int) -> String:
	var h: int = seconds / 3600
	var m: int = (seconds % 3600) / 60
	return "%dh %02dm" % [h, m]


func _style(color: Color, radius: int, border := Color.TRANSPARENT) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = color
	sb.set_corner_radius_all(radius)
	if border != Color.TRANSPARENT:
		sb.set_border_width_all(3)
		sb.border_color = border
	sb.content_margin_left = 12
	sb.content_margin_right = 12
	return sb


func _style_button(btn: Button, color: Color) -> void:
	btn.add_theme_stylebox_override("normal", _style(color, 12))
	btn.add_theme_stylebox_override("hover", _style(color.lightened(0.08), 12))
	btn.add_theme_stylebox_override("pressed", _style(color.darkened(0.1), 12))
	btn.add_theme_stylebox_override("disabled", _style(color.darkened(0.35), 12))
	btn.add_theme_color_override("font_color", Color.WHITE)
	btn.add_theme_font_size_override("font_size", 20)
