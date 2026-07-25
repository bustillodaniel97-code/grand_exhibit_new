extends Control
## Expedition Mode screen (SPEC §4 events.json, §6 battler, §8 insight_rush).
## Gate: feature_unlocked("expedition") (Rep 7). Invest cash along a 5-stage
## track to unlock the boss; idle insight accrues into capped storage and is
## collected at 1x / 2x (RV "insight_rush") / 3x (gems). Progress persists in
## GameState.expedition_state (stage, invested, cycle, insight_stored).

const BattleView = preload("res://scenes/events/battle_view.gd")
const BattleMath = preload("res://scripts/events/battle_math.gd")

# Palette from ui_kit; these were private copies of the retired muted scheme.
const UI := preload("res://scripts/ui/ui_kit.gd")
# This screen is popup CONTENT, so its page is a light surface, not the
# deep app shell — it draws INK body text directly on it.
const BG := UI.SURFACE
const INK := UI.INK
const PANEL := UI.PANEL
const ACCENT := UI.ACCENT
const BRASS := UI.BRASS
const SAGE := UI.SAGE
const SLATE := UI.SLATE
const SPEC_GLYPH := {"promotions": "P", "ticket": "T", "archive": "A", "gallery": "G"}
const SPEC_COLOR := UI.DEPT_COLORS

var _payload := {}
var _event: Dictionary = {}
var _tuning: Dictionary = {}
var _selected: Array = []       # manager ids for the boss fight (max 3)
var _battle: Control = null
var _outcome: Control = null
var _scroll: ScrollContainer
var _outcome_timer: Timer
var _storage_bar: ProgressBar
var _storage_label: Label
var _timer: Timer


func setup(payload: Dictionary) -> void:
	_payload = payload


func _ready() -> void:
	_event = DataLoader.get_event("expedition")
	_tuning = DataLoader.core.get("monetization_tuning", {})
	_timer = Timer.new()
	_timer.wait_time = 1.0
	_timer.autostart = true
	_timer.timeout.connect(_on_tick)
	add_child(_timer)
	if not AdService.ad_result.is_connected(_on_ad_result):
		AdService.ad_result.connect(_on_ad_result)
	if not EventBus.insight_storage_changed.is_connected(_on_storage_changed):
		EventBus.insight_storage_changed.connect(_on_storage_changed)
	_build()


func _es() -> Dictionary:
	return GameState.expedition_state


func _cycle() -> int:
	return int(_es().get("cycle", 0))


func _owned_pairs() -> Array:
	var pairs: Array = []
	for mid in GameState.managers_state.keys():
		var st: Dictionary = GameState.managers_state[mid]
		if int(st.get("cards", 0)) >= 1:
			pairs.append({"def": DataLoader.get_manager_def(mid), "state": st, "id": mid})
	return pairs


func _build() -> void:
	for c in get_children():
		if c != _timer and c != _outcome_timer:
			c.queue_free()
	_scroll = null
	var bg_panel := Panel.new()
	bg_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg_panel.add_theme_stylebox_override("panel", _style(BG, 0))
	add_child(bg_panel)

	if not GameState.feature_unlocked("expedition"):
		var lock := Label.new()
		lock.text = "Expedition Mode\n\nUnlocks at Rep 7"
		lock.set_anchors_preset(Control.PRESET_FULL_RECT)
		lock.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lock.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		lock.add_theme_font_size_override("font_size", 28)
		lock.add_theme_color_override("font_color", INK)
		add_child(lock)
		return

	if _selected.is_empty():
		_auto_pick_team()

	_scroll = ScrollContainer.new()
	_scroll.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_scroll)
	var root := VBoxContainer.new()
	root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.add_theme_constant_override("separation", 12)
	_scroll.add_child(root)

	var title := Label.new()
	title.text = "Expedition Mode · Cycle %d" % (_cycle() + 1)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 32)
	title.add_theme_color_override("font_color", INK)
	root.add_child(title)

	_build_insight_panel(root)
	_build_invest_track(root)
	_build_boss_section(root)
	_refresh_storage()


## --- Insight idle panel -----------------------------------------------------

func _build_insight_panel(root: VBoxContainer) -> void:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _style(PANEL, 12, BRASS))
	root.add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	panel.add_child(v)
	var head := Label.new()
	head.text = "Insight Field Lab (idle)"
	head.add_theme_font_size_override("font_size", 20)
	head.add_theme_color_override("font_color", INK)
	v.add_child(head)
	_storage_bar = ProgressBar.new()
	_storage_bar.custom_minimum_size = Vector2(0, 22)
	_storage_bar.show_percentage = false
	_storage_bar.add_theme_stylebox_override("background", _style(BG, 8))
	_storage_bar.add_theme_stylebox_override("fill", _style(SLATE, 8))
	v.add_child(_storage_bar)
	_storage_label = Label.new()
	_storage_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_storage_label.add_theme_color_override("font_color", INK)
	v.add_child(_storage_label)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 10)
	v.add_child(row)
	var b1 := Button.new()
	b1.text = "Collect 1×"
	_style_button(b1, SLATE)
	b1.pressed.connect(func() -> void:
		var got: BigNumber = Economy.collect_insight(1.0)
		_toast("Collected %s insight" % got.to_notation() if not got.is_zero() else "Nothing stored yet")
		_refresh_storage())
	row.add_child(b1)
	var b2 := Button.new()
	b2.text = "Ad ×%d" % int(float(_tuning.get("insight_rush_ad_mult", 2.0)))
	_style_button(b2, ACCENT)
	b2.pressed.connect(_on_ad_collect)
	row.add_child(b2)
	var b3 := Button.new()
	b3.text = "%d Gems ×%d" % [int(_tuning.get("insight_rush_gem_cost", 10)),
		int(float(_tuning.get("insight_rush_gem_mult", 3.0)))]
	_style_button(b3, BRASS)
	b3.pressed.connect(_on_gem_collect)
	row.add_child(b3)


func _on_ad_collect() -> void:
	var stored: BigNumber = BigNumber.from_save(_es().get("insight_stored", {}))
	if stored.is_zero():
		_toast("Nothing stored yet")
		return
	AdService.show_rewarded("insight_rush",
		{"mult": float(_tuning.get("insight_rush_ad_mult", 2.0))})


func _on_ad_result(placement_id: String, success: bool, context: Dictionary) -> void:
	if placement_id != "insight_rush" or not is_inside_tree():
		return
	if success:
		var mult: float = float(context.get("mult", 2.0))
		var got: BigNumber = Economy.collect_insight(mult)
		EventBus.rv_reward_granted.emit("insight_rush", {"mult": mult})
		Analytics.rv_impression("insight_rush")
		_toast("Collected %s insight (×%s)" % [got.to_notation(), str(mult)])
	else:
		_toast("Ad unavailable")
	_refresh_storage()


func _on_gem_collect() -> void:
	var stored: BigNumber = BigNumber.from_save(_es().get("insight_stored", {}))
	if stored.is_zero():
		_toast("Nothing stored yet")
		return
	var cost: int = int(_tuning.get("insight_rush_gem_cost", 10))
	if not GameState.spend_gems(cost):
		_toast("Not enough gems")
		return
	var mult: float = float(_tuning.get("insight_rush_gem_mult", 3.0))
	var got: BigNumber = Economy.collect_insight(mult)
	_toast("Collected %s insight (×%s)" % [got.to_notation(), str(mult)])
	_refresh_storage()


func _on_storage_changed(_stored, _cap) -> void:
	_refresh_storage()


func _on_tick() -> void:
	# Economy also ticks this globally; nudging here keeps the panel live.
	Economy.tick_insight_storage(ClockGuard.now())
	_refresh_storage()


func _refresh_storage() -> void:
	if _storage_bar == null or not is_instance_valid(_storage_bar):
		return
	var stored: BigNumber = BigNumber.from_save(_es().get("insight_stored", {}))
	var cap: BigNumber = Economy.insight_cap()
	var cap_f: float = maxf(cap.to_float_approx(), 1.0)
	_storage_bar.max_value = cap_f
	_storage_bar.value = stored.to_float_approx()
	_storage_label.text = "Stored %s / %s insight" % [stored.to_notation(), cap.to_notation()]


## --- Invest track -----------------------------------------------------------

func _build_invest_track(root: VBoxContainer) -> void:
	var head := Label.new()
	head.text = "Invest to reveal the dig site"
	head.add_theme_font_size_override("font_size", 20)
	head.add_theme_color_override("font_color", INK)
	root.add_child(head)
	var es: Dictionary = _es()
	var stage: int = int(es.get("stage", 0))
	var stages: Array = _event.get("stages", [])
	for i in stages.size():
		var s: Dictionary = stages[i]
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 12)
		var done: bool = i < stage
		var btn := Button.new()
		btn.custom_minimum_size = Vector2(170, 52)
		var cost: BigNumber = BigNumber.from_parts(
			float(s.get("invest_cost_m", 1.0)), int(s.get("invest_cost_e", 0)))
		btn.text = "Funded" if done else "Invest " + cost.to_notation()
		_style_button(btn, SAGE if done else (ACCENT if i == stage else SLATE))
		# Only a funded step is inert. "Too expensive" and "not your turn" are
		# explained by _on_invest's toasts, never by a dead tap.
		btn.disabled = done
		btn.pressed.connect(_on_invest.bind(i))
		row.add_child(btn)
		var info := UI.make_label("%s — +%s insight" % [
			str(s.get("name", "Site")), str(s.get("insight_reward", 0))], UI.TYPE_LABEL)
		info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(info)
		root.add_child(row)


func _on_invest(i: int) -> void:
	var es: Dictionary = _es()
	var stage: int = int(es.get("stage", 0))
	if i != stage:
		var stages: Array = _event.get("stages", [])
		if stage >= stages.size():
			_toast("Every dig site is funded — the Guardian is waiting.")
		elif i < stage:
			_toast("That site is already funded.")
		else:
			_toast("Fund %s first." % str((stages[stage] as Dictionary).get("name", "the next site")))
		return
	var s: Dictionary = _event.get("stages", [])[i]
	var cost: BigNumber = BigNumber.from_parts(
		float(s.get("invest_cost_m", 1.0)), int(s.get("invest_cost_e", 0)))
	if not GameState.spend_cash(cost):
		_toast("Needs %s — keep the museum earning." % cost.to_notation())
		return
	var invested: BigNumber = BigNumber.from_save(es.get("invested", {}))
	es["invested"] = invested.add(cost).to_save()
	var reward: float = float(s.get("insight_reward", 0.0))
	if reward > 0.0:
		GameState.add_insight(BigNumber.from_float(reward))
	es["stage"] = i + 1
	Analytics.log_event("expedition_invest", {"stage": i})
	if int(es["stage"]) >= _event.get("stages", []).size():
		es["boss_unlocked"] = true
		_toast("The Temple Guardian stirs…")
	_build()


## --- Boss section -----------------------------------------------------------

func _build_boss_section(root: VBoxContainer) -> void:
	var boss: Dictionary = _event.get("boss", {})
	var head := Label.new()
	head.text = "Boss: %s" % str(boss.get("name", "The Temple Guardian"))
	head.add_theme_font_size_override("font_size", 20)
	head.add_theme_color_override("font_color", INK)
	root.add_child(head)
	if not bool(_es().get("boss_unlocked", false)):
		var locked := Label.new()
		locked.text = "Complete the invest track to unlock the boss."
		locked.add_theme_color_override("font_color", INK)
		root.add_child(locked)
		return
	# Team picker for the boss fight.
	var team_head := Label.new()
	team_head.text = "Boss team (up to 3):"
	team_head.add_theme_color_override("font_color", INK)
	root.add_child(team_head)
	var flow := HFlowContainer.new()
	flow.add_theme_constant_override("h_separation", 10)
	flow.add_theme_constant_override("v_separation", 10)
	root.add_child(flow)
	var owned: Array = _owned_pairs()
	for pair in owned:
		flow.add_child(_manager_card(pair))
	if owned.is_empty():
		var none := UI.make_label(
			"No managers yet — recruit one from a Store lootbox to field a team.",
			UI.TYPE_BODY)
		none.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		root.add_child(none)
	var power: float = _team_power_selected()
	var hp: float = BattleMath.expedition_boss_hp(boss, power, _cycle())
	var info := Label.new()
	info.text = "HP ~%d · %d moves · team power %d\nRewards: %s" % [
		int(round(hp)), int(boss.get("moves", 24)), int(round(power)),
		_rewards_preview(boss.get("rewards", {}))]
	info.add_theme_color_override("font_color", INK)
	root.add_child(info)
	var btn := Button.new()
	btn.text = "Fight the Guardian"
	btn.custom_minimum_size = Vector2(0, UI.TOUCH_MIN + 8)
	_style_button(btn, ACCENT)
	btn.pressed.connect(_on_fight_pressed.bind(hp))
	root.add_child(btn)


func _on_fight_pressed(hp: float) -> void:
	if _owned_pairs().is_empty():
		_toast("Recruit a manager from the Store before facing the Guardian.")
		return
	if _selected.is_empty():
		_toast("Pick up to 3 managers for the expedition team.")
		return
	_on_fight_boss(hp)


func _auto_pick_team() -> void:
	var pairs: Array = _owned_pairs()
	pairs.sort_custom(func(a, b) -> bool:
		return BattleMath.manager_attack(a["def"], a["state"]) \
			> BattleMath.manager_attack(b["def"], b["state"]))
	for i in mini(3, pairs.size()):
		_selected.append(str(pairs[i]["id"]))


func _team_power_selected() -> float:
	var pairs: Array = []
	for mid in _selected:
		pairs.append({"def": DataLoader.get_manager_def(mid),
			"state": GameState.managers_state[mid]})
	return BattleMath.team_power(pairs)


func _manager_card(pair: Dictionary) -> Control:
	var mid: String = str(pair["id"])
	var def: Dictionary = pair["def"]
	var st: Dictionary = pair["state"]
	var btn := Button.new()
	btn.toggle_mode = true
	btn.custom_minimum_size = Vector2(210, 92)
	btn.button_pressed = _selected.has(mid)
	var spec: String = str(def.get("specialty", ""))
	var col: Color = SPEC_COLOR.get(spec, BRASS)
	btn.add_theme_stylebox_override("normal", _style(PANEL, 12, col))
	btn.add_theme_stylebox_override("pressed", _style(col, 12, INK))
	btn.add_theme_stylebox_override("disabled", _style(PANEL.darkened(0.1), 12))
	btn.text = "%s %s\nLv %d · Rank %d\nPower %d" % [
		str(SPEC_GLYPH.get(spec, "?")), str(def.get("name", mid)),
		int(st.get("level", 1)), int(st.get("rank", 1)),
		int(round(BattleMath.manager_attack(def, st)))]
	# A fourth pick used to silently snap back to unpressed. Nothing refuses a
	# tap: picking past the cap rotates the oldest manager out of the team.
	btn.toggled.connect(func(on: bool) -> void:
		if on:
			if _selected.size() >= 3:
				var dropped: String = str(_selected.pop_front())
				_toast("%s stepped aside for %s" % [
					str(DataLoader.get_manager_def(dropped).get("name", dropped)),
					str(def.get("name", mid))])
			_selected.append(mid)
		else:
			_selected.erase(mid)
		_build())
	return btn


func _on_fight_boss(hp: float) -> void:
	var boss: Dictionary = _event.get("boss", {})
	var team: Array = []
	for mid in _selected:
		team.append({"def": DataLoader.get_manager_def(mid),
			"state": GameState.managers_state[mid], "id": mid})
	if _scroll != null and is_instance_valid(_scroll):
		_scroll.visible = false  # nothing of the host can bleed past the board
	_battle = BattleView.new()
	_battle.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_battle)
	_battle.setup_battle({
		"boss_name": str(boss.get("name", "The Temple Guardian")),
		"boss_hp": hp,
		"moves": int(boss.get("moves", 24)),
		"team": team,
	})
	_battle.battle_finished.connect(_on_boss_finished.bind(hp), CONNECT_ONE_SHOT)


func _on_boss_finished(result: String, hp: float) -> void:
	Analytics.log_event("expedition_boss", {"cycle": _cycle(), "result": result})
	if result != "win":
		_queue_outcome("Expedition failed", "The Guardian holds the temple.\n"
			+ "Chase the audit colour or bring stronger managers.", UI.DANGER, hp)
		return
	var es: Dictionary = _es()
	# Idempotence lives here, not in whether a button happened to be disabled:
	# clearing the boss closes the cycle, so a second emission finds it closed.
	if not bool(es.get("boss_unlocked", false)):
		_queue_outcome("Already claimed", "This expedition is already written up.",
			SAGE, hp)
		return
	var boss: Dictionary = _event.get("boss", {})
	var applied: Dictionary = _apply_rewards(boss.get("rewards", {}))
	EventBus.event_stage_completed.emit("expedition", _cycle(), applied)
	# New cycle: the track resets and the boss escalates via the persisted count.
	es["stage"] = 0
	es["invested"] = BigNumber.zero().to_save()
	es["boss_unlocked"] = false
	es["cycle"] = _cycle() + 1
	_queue_outcome("Guardian defeated", "%s\nA new expedition begins (cycle %d)." % [
		_applied_text(applied), _cycle() + 1], SAGE, hp)


## Lets the last cascade and the last damage number land before the card covers
## the board. Rewards are already applied by this point; only the card waits.
func _queue_outcome(title: String, body: String, tint: Color, hp: float) -> void:
	if _outcome_timer != null and is_instance_valid(_outcome_timer):
		_outcome_timer.queue_free()
	_outcome_timer = Timer.new()
	_outcome_timer.one_shot = true
	_outcome_timer.wait_time = 0.55
	add_child(_outcome_timer)
	_outcome_timer.timeout.connect(func() -> void: _show_outcome(title, body, tint, hp))
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


func _show_outcome(title: String, body: String, tint: Color, hp: float) -> void:
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
	card.add_theme_stylebox_override("panel", UI.make_frame(tint))
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

	var l := UI.make_label(body, UI.TYPE_BODY)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(l)

	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 12)
	v.add_child(row)
	var still_open: bool = bool(_es().get("boss_unlocked", false))
	if still_open and not _selected.is_empty():
		var retry := UI.make_button("Retry", ACCENT)
		retry.custom_minimum_size = Vector2(180, UI.TOUCH_MIN + 8)
		retry.pressed.connect(_on_retry.bind(hp))
		row.add_child(retry)
	var btn := UI.make_button("Continue", SAGE if not still_open else UI.SLATE)
	btn.custom_minimum_size = Vector2(180, UI.TOUCH_MIN + 8)
	btn.pressed.connect(_close_battle)
	row.add_child(btn)


func _on_retry(hp: float) -> void:
	if _outcome != null and is_instance_valid(_outcome):
		_outcome.queue_free()
	_outcome = null
	if _battle != null and is_instance_valid(_battle):
		_battle.queue_free()
	_battle = null
	_on_fight_boss(hp)


func _close_battle() -> void:
	if _battle != null and is_instance_valid(_battle):
		_battle.queue_free()
	_battle = null
	if _outcome != null and is_instance_valid(_outcome):
		_outcome.queue_free()
	_outcome = null
	_build()


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


func _applied_text(applied: Dictionary) -> String:
	var parts: Array = []
	for mid in applied.get("cards", {}).keys():
		parts.append("%dx %s" % [int(applied["cards"][mid]),
			str(DataLoader.get_manager_def(mid).get("name", mid))])
	if int(applied.get("gems", 0)) > 0:
		parts.append("%d gems" % int(applied["gems"]))
	if float(applied.get("insight_m", 0.0)) > 0.0:
		parts.append("%s insight" % str(applied["insight_m"]))
	return "Rewards: " + (" · ".join(parts) if not parts.is_empty() else "none")


func _toast(text: String) -> void:
	EventBus.toast_requested.emit(text)


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
