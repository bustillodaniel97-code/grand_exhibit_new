extends Control
## Inspection Frenzy event screen (SPEC §4 events.json, §6 battler, §11 registry).
## Gate: feature_unlocked("inspection") (Day 2). Time-boxed windows from
## events.json duration_hours/cooldown_hours, state persisted in
## GameState.event_state["inspection_frenzy"].
##
## NO BUTTON HERE IS EVER DISABLED FOR A REASON THE PLAYER COULD FIX. Every stage
## button stays tappable and answers with a toast that names the missing thing;
## the only greyed rows are stages already cleared, which is a state, not a
## blocker. The previous build disabled all six stages whenever no manager was
## picked — and a Day-1 player owns none, because the event opens on day 1 while
## managers unlock at rep 6, so the whole screen was six dead taps.

const BattleView = preload("res://scenes/events/battle_view.gd")
const BattleMath = preload("res://scripts/events/battle_math.gd")

# Palette from ui_kit; these were private copies of the retired muted scheme.
const UI := preload("res://scripts/ui/ui_kit.gd")
# Popup CONTENT on a DARK page: the department hues on the manager cards and the
# stage buttons are the colour here, so the ground stays deep and the ink light.
const BG := UI.PAGE
const INK := UI.TEXT
const DIM := UI.TEXT_DIM
const PANEL := UI.CARD
const ACCENT := UI.ACCENT
const BRASS := UI.BRASS
const SAGE := UI.SAGE
const SPEC_GLYPH := {"promotions": "P", "ticket": "T", "archive": "A", "gallery": "G"}
const SPEC_COLOR := UI.DEPT_COLORS
const MAX_TEAM := 3

var _payload := {}
var _event: Dictionary = {}
var _selected: Array = []       # manager ids (max MAX_TEAM)
var _battle: Control = null
var _outcome: Control = null
var _scroll: ScrollContainer
var _status_label: Label
var _start_button: Button
var _timer: Timer
var _outcome_timer: Timer


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


func _owned_pairs() -> Array:
	var pairs: Array = []
	for mid in GameState.managers_state.keys():
		var st: Dictionary = GameState.managers_state[mid]
		if int(st.get("cards", 0)) >= 1:
			pairs.append({"def": DataLoader.get_manager_def(mid), "state": st, "id": mid})
	return pairs


## Power of the managers actually being SENT IN. Boss HP keys off this and only
## this: the old screen fed the whole owned roster into stage_boss_hp(), so every
## manager the event handed out made the event harder while the three managers
## that fight stayed the same.
func _selected_team_power() -> float:
	var pairs: Array = []
	for mid in _selected:
		if GameState.managers_state.has(mid):
			pairs.append({"def": DataLoader.get_manager_def(mid),
				"state": GameState.managers_state[mid]})
	return BattleMath.team_power(pairs)


func _build() -> void:
	for c in get_children():
		if c != _timer and c != _outcome_timer:
			c.queue_free()
	_scroll = null
	var bg_panel := Panel.new()
	bg_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg_panel.add_theme_stylebox_override("panel", _style(BG, 0))
	add_child(bg_panel)

	if not GameState.feature_unlocked("inspection"):
		var lock := _center_label("Inspection Frenzy\n\nUnlocks on Day 2")
		add_child(lock)
		return

	_prune_selection()
	_scroll = ScrollContainer.new()
	_scroll.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_scroll)
	var root := VBoxContainer.new()
	root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.add_theme_constant_override("separation", 12)
	_scroll.add_child(root)
	var pad := MarginContainer.new()
	root.add_child(pad)

	var title := UI.make_display_label(str(_event.get("name", "Inspection Frenzy")),
		UI.TYPE_DISPLAY, INK)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(title)

	_status_label = UI.make_label("", UI.TYPE_BODY, DIM)
	_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	root.add_child(_status_label)

	_start_button = UI.make_button("Start Inspection", ACCENT)
	_start_button.custom_minimum_size = Vector2(0, UI.TOUCH_MIN + 8)
	_start_button.pressed.connect(_on_start_pressed)
	root.add_child(_start_button)

	var owned: Array = _owned_pairs()
	if owned.is_empty():
		root.add_child(_no_managers_card())
	else:
		root.add_child(_rules_card())
		var team_head := UI.make_display_label(
			"Your team  %d/%d" % [_selected.size(), MAX_TEAM], UI.TYPE_HEADING, INK)
		root.add_child(team_head)
		var flow := HFlowContainer.new()
		flow.add_theme_constant_override("h_separation", 10)
		flow.add_theme_constant_override("v_separation", 10)
		root.add_child(flow)
		for pair in owned:
			flow.add_child(_manager_card(pair))

	# Stage list.
	root.add_child(UI.make_display_label("Stages", UI.TYPE_HEADING, INK))
	var es: Dictionary = _es()
	var stages: Array = _event.get("stages", [])
	for i in stages.size():
		root.add_child(_stage_row(i, stages[i], es))
	if int(es.get("stage", 0)) >= stages.size() and _window_active(ClockGuard.now()):
		var done := UI.make_label("All stages cleared! Come back after the cooldown.", UI.TYPE_BODY)
		done.add_theme_color_override("font_color", SAGE)
		root.add_child(done)

	_refresh_window_status()


## Managers unlock at rep 6 but the event opens on day 1, so a new player reaches
## this screen with an empty roster. Say so once, loudly, instead of leaving six
## grey bricks and one line of body text to explain themselves.
func _no_managers_card() -> Control:
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", UI.make_dark_frame(BRASS))
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	card.add_child(v)
	v.add_child(UI.make_display_label("You need a team first", UI.TYPE_TITLE, INK))
	var body := UI.make_label(
		"Inspections are fought by managers. Recruit your first one from a lootbox "
		+ "in the Store, then come back and pick up to three.", UI.TYPE_BODY, DIM)
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(body)
	return card


func _rules_card() -> Control:
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", UI.make_dark_inset())
	var body := UI.make_label(
		"Match your managers' colours to charge them. The inspector audits one "
		+ "department at a time — clearing THAT colour charges far faster, and the "
		+ "audit moves as soon as you satisfy it.", UI.TYPE_LABEL, DIM)
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	card.add_child(body)
	return card


## Drops selections the player no longer owns (a prestige or a save edit) so the
## team never carries a phantom manager into stage_boss_hp().
func _prune_selection() -> void:
	var keep: Array = []
	for mid in _selected:
		var st: Dictionary = GameState.managers_state.get(mid, {})
		if int(st.get("cards", 0)) >= 1 and keep.size() < MAX_TEAM:
			keep.append(mid)
	_selected = keep


func _manager_card(pair: Dictionary) -> Control:
	var mid: String = str(pair["id"])
	var def: Dictionary = pair["def"]
	var st: Dictionary = pair["state"]
	var on: bool = _selected.has(mid)
	var spec: String = str(def.get("specialty", ""))
	var col: Color = SPEC_COLOR.get(spec, BRASS)
	var btn := Button.new()
	btn.custom_minimum_size = Vector2(212, 96)
	btn.add_theme_stylebox_override("normal", _style(col if on else PANEL, 12, INK if on else col))
	btn.add_theme_stylebox_override("hover", _style(col if on else PANEL.lightened(0.03), 12, col))
	btn.add_theme_stylebox_override("pressed", _style(col.darkened(0.1), 12, INK))
	# White on the gold department card is a 1.26:1 label; pick the ink that wins
	# on whichever hue this manager carries. UI.INK, not the screen's INK alias — a
	# SELECTED card is a light saturated fill and still wants the dark ink, while an
	# unselected one is the dark CARD and wants the light one.
	btn.add_theme_color_override("font_color",
		(UI.INK if col.get_luminance() > 0.45 else Color.WHITE) if on else INK)
	btn.add_theme_font_size_override("font_size", UI.TYPE_LABEL)
	var atk: float = BattleMath.manager_attack(def, st)
	btn.text = "%s %s\nLv %d · Rank %d · Power %d\n%s" % [
		str(SPEC_GLYPH.get(spec, "?")), str(def.get("name", mid)),
		int(st.get("level", 1)), int(st.get("rank", 1)), int(round(atk)),
		"IN TEAM" if on else "tap to add"]
	# A fourth pick used to disable every other card. Nothing here refuses a tap:
	# picking past the cap rotates the oldest manager out.
	btn.pressed.connect(func() -> void:
		if _selected.has(mid):
			_selected.erase(mid)
		else:
			if _selected.size() >= MAX_TEAM:
				var dropped: String = str(_selected.pop_front())
				_toast("%s stepped aside for %s" % [
					str(DataLoader.get_manager_def(dropped).get("name", dropped)),
					str(def.get("name", mid))])
			_selected.append(mid)
		_build())
	return btn


func _stage_row(i: int, stage: Dictionary, es: Dictionary) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	var unlocked: bool = i <= int(es.get("stage", 0))
	var cleared: bool = i < int(es.get("stage", 0)) or es.get("completed", []).has(i)
	var btn := UI.make_button(("Cleared" if cleared else "Stage %d" % (i + 1)),
		SAGE if cleared else ACCENT)
	btn.custom_minimum_size = Vector2(160, UI.TOUCH_MIN + 4)
	# Only an already-cleared stage is inert, and that is a state rather than a
	# blocker. Locked / no-team / closed-window all stay tappable and explain.
	btn.disabled = cleared
	btn.pressed.connect(_on_play_stage.bind(i))
	row.add_child(btn)
	var power: float = _selected_team_power()
	var hp: float = BattleMath.stage_boss_hp(_event, i, power)
	var odds := "pick a team to see the odds"
	if power > 0.0:
		odds = "%d HP · %d moves" % [int(round(hp)), BattleMath.stage_moves(_event, i)]
	elif not unlocked:
		odds = "clear stage %d first" % i
	var info := UI.make_label("%s\n%s" % [_rewards_preview(stage.get("rewards", {})), odds],
		UI.TYPE_LABEL, DIM)
	info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
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
	var power: float = _selected_team_power()
	var team_line := "\nTeam power %d" % int(round(power)) if power > 0.0 else ""
	if _window_active(now):
		var left: int = int(es["opened_at"]) + int(float(_event.get("duration_hours", 48)) * 3600.0) - now
		_status_label.text = "Window OPEN — closes in %s%s" % [_fmt_hours(left), team_line]
		_start_button.visible = false
	else:
		_start_button.visible = true
		_start_button.disabled = false
		if _cooldown_over(now):
			_status_label.text = "Next inspection: READY" + team_line
			_start_button.text = "Start Inspection"
		else:
			var wait: int = int(es.get("opened_at", 0)) \
				+ int(float(_event.get("cooldown_hours", 72)) * 3600.0) - now
			_status_label.text = "Next inspection in %s" % _fmt_hours(wait)
			_start_button.text = "On cooldown"


func _on_start_pressed() -> void:
	var now: int = ClockGuard.now()
	if not _cooldown_over(now):
		_toast("The inspectors need %s to write up the last visit."
			% _fmt_hours(int(_es().get("opened_at", 0))
				+ int(float(_event.get("cooldown_hours", 72)) * 3600.0) - now))
		return
	var es: Dictionary = _es()
	es["opened_at"] = now
	es["stage"] = 0
	es["completed"] = []
	es["team_power_at_open"] = _selected_team_power()
	Analytics.log_event("inspection_open", {"team_power": es["team_power_at_open"]})
	_build()


func _on_play_stage(stage_index: int) -> void:
	var es: Dictionary = _es()
	if not _window_active(ClockGuard.now()):
		_toast("Start the inspection first — the window is closed.")
		return
	if int(stage_index) > int(es.get("stage", 0)):
		_toast("Clear stage %d first." % int(es.get("stage", 0) + 1))
		return
	if _owned_pairs().is_empty():
		_toast("Recruit a manager from the Store to fight an inspection.")
		return
	if _selected.is_empty():
		_toast("Pick up to %d managers first." % MAX_TEAM)
		return
	var stage: Dictionary = _event.get("stages", [])[stage_index]
	var team: Array = []
	for mid in _selected:
		team.append({"def": DataLoader.get_manager_def(mid),
			"state": GameState.managers_state[mid], "id": mid})
	_open_battle(stage_index, team, int(stage.get("moves", 20)))


func _open_battle(stage_index: int, team: Array, moves: int) -> void:
	if _scroll != null and is_instance_valid(_scroll):
		_scroll.visible = false  # nothing of the host can bleed past the board
	_battle = BattleView.new()
	_battle.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_battle)
	_battle.setup_battle({
		"boss_name": "Chief Inspector — Stage %d" % (stage_index + 1),
		"boss_hp": BattleMath.stage_boss_hp(_event, stage_index, _selected_team_power()),
		"moves": moves,
		"team": team,
	})
	_battle.battle_finished.connect(_on_battle_finished.bind(stage_index), CONNECT_ONE_SHOT)


func _on_battle_finished(result: String, stage_index: int) -> void:
	Analytics.log_event("inspection_stage", {"stage": stage_index, "result": result})
	if result != "win":
		_queue_outcome("Inspection failed", "The inspectors ran out of patience.\n"
			+ "Chase the audit colour — it charges 1.8x — or bring stronger managers.",
			UI.DANGER, stage_index)
		return
	var es: Dictionary = _es()
	# Idempotence lives HERE, not in whether the stage button happened to be
	# disabled. A retry path or a re-emitted signal must never double-grant.
	if es.get("completed", []).has(stage_index):
		_queue_outcome("Already cleared", "This stage was already signed off.",
			SAGE, stage_index)
		return
	var stage: Dictionary = _event.get("stages", [])[stage_index]
	var applied: Dictionary = _apply_rewards(stage.get("rewards", {}))
	es["completed"].append(stage_index)
	es["stage"] = maxi(int(es.get("stage", 0)), stage_index + 1)
	EventBus.event_stage_completed.emit("inspection_frenzy", stage_index, applied)
	_queue_outcome("Stage %d cleared" % (stage_index + 1), _applied_text(applied),
		SAGE, stage_index)


## Lets the last cascade and the last damage number land before the card covers
## the board. Rewards are already applied by this point; only the card waits.
func _queue_outcome(title: String, body: String, tint: Color, stage_index: int) -> void:
	if _outcome_timer != null and is_instance_valid(_outcome_timer):
		_outcome_timer.queue_free()
	_outcome_timer = Timer.new()
	_outcome_timer.one_shot = true
	_outcome_timer.wait_time = 0.55
	add_child(_outcome_timer)
	_outcome_timer.timeout.connect(func() -> void:
		_show_outcome(title, body, tint, stage_index))
	_outcome_timer.start()


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


func _show_outcome(title: String, body: String, tint: Color, stage_index: int) -> void:
	if not is_inside_tree():
		return
	_outcome = Panel.new()
	_outcome.set_anchors_preset(Control.PRESET_FULL_RECT)
	_outcome.add_theme_stylebox_override("panel", _style(Color(0, 0, 0, 0.62), 0))
	add_child(_outcome)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_outcome.add_child(center)
	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(560, 0)
	card.add_theme_stylebox_override("panel", UI.make_dark_frame(tint))
	center.add_child(card)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 14)
	card.add_child(v)

	# A win and a loss have to be unmistakable from across the room: a full-width
	# colour band, not two lines of body copy on the same cream card.
	var band := PanelContainer.new()
	band.add_theme_stylebox_override("panel", UI.make_panel(tint, 14, 0))
	var band_l := UI.make_display_label(title.to_upper(), UI.TYPE_HERO, Color.WHITE)
	band_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	UI.add_text_halo(band_l)
	band.add_child(band_l)
	v.add_child(band)

	var l := UI.make_label(body, UI.TYPE_BODY, INK)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(l)

	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 12)
	v.add_child(row)
	var cleared: bool = _es().get("completed", []).has(stage_index)
	if not cleared:
		var retry := UI.make_button("Retry", ACCENT)
		retry.custom_minimum_size = Vector2(180, UI.TOUCH_MIN + 8)
		retry.pressed.connect(_on_retry.bind(stage_index))
		row.add_child(retry)
	var btn := UI.make_button("Continue", SAGE if cleared else UI.SLATE)
	btn.custom_minimum_size = Vector2(180, UI.TOUCH_MIN + 8)
	btn.pressed.connect(_close_battle)
	row.add_child(btn)


func _on_retry(stage_index: int) -> void:
	if not _window_active(ClockGuard.now()) or _selected.is_empty():
		_close_battle()
		return
	if _outcome != null and is_instance_valid(_outcome):
		_outcome.queue_free()
	_outcome = null
	var stage: Dictionary = _event.get("stages", [])[stage_index]
	var team: Array = []
	for mid in _selected:
		team.append({"def": DataLoader.get_manager_def(mid),
			"state": GameState.managers_state[mid], "id": mid})
	if _battle != null and is_instance_valid(_battle):
		_battle.queue_free()
	_battle = null
	_open_battle(stage_index, team, int(stage.get("moves", 20)))


func _close_battle() -> void:
	if _battle != null and is_instance_valid(_battle):
		_battle.queue_free()
	_battle = null
	if _outcome != null and is_instance_valid(_outcome):
		_outcome.queue_free()
	_outcome = null
	_build()


func _toast(text: String) -> void:
	EventBus.toast_requested.emit(text)


func _center_label(text: String) -> Label:
	var l := UI.make_display_label(text, UI.TYPE_DISPLAY, INK)
	l.set_anchors_preset(Control.PRESET_FULL_RECT)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	return l


func _fmt_hours(seconds: int) -> String:
	var s: int = maxi(seconds, 0)
	return "%dh %02dm" % [s / 3600, (s % 3600) / 60]


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
