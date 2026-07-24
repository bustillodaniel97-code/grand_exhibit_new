extends Control
## Expedition Mode screen (SPEC §4 events.json, §6 battler, §8 insight_rush).
## Gate: feature_unlocked("expedition") (Rep 7). Invest cash along a 5-stage
## track to unlock the boss; idle insight accrues into capped storage and is
## collected at 1x / 2x (RV "insight_rush") / 3x (gems). Progress persists in
## GameState.expedition_state (stage, invested, cycle, insight_stored).

const BattleView = preload("res://scenes/events/battle_view.gd")
const BattleMath = preload("res://scripts/events/battle_math.gd")

const BG := Color("#F5EFE0")
const INK := Color("#33312E")
const PANEL := Color("#FFFDF6")
const ACCENT := Color("#C4703F")
const BRASS := Color("#B08D3E")
const SAGE := Color("#7A9B76")
const SLATE := Color("#5B7B8C")
const SPEC_GLYPH := {"promotions": "P", "ticket": "T", "archive": "A", "gallery": "G"}
const SPEC_COLOR := {"promotions": Color("#8E6C8A"), "ticket": Color("#C4703F"),
	"archive": Color("#5B7B8C"), "gallery": Color("#B08D3E")}

var _payload := {}
var _event: Dictionary = {}
var _tuning: Dictionary = {}
var _selected: Array = []       # manager ids for the boss fight (max 3)
var _battle: Control = null
var _outcome: Control = null
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
		if c != _timer:
			c.queue_free()
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

	var scroll := ScrollContainer.new()
	scroll.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(scroll)
	var root := VBoxContainer.new()
	root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.add_theme_constant_override("separation", 12)
	scroll.add_child(root)

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
		btn.text = "✓ Done" if done else "Invest " + cost.to_notation()
		_style_button(btn, SAGE if done else ACCENT)
		btn.disabled = done or i != stage or GameState.cash.lt(cost)
		btn.pressed.connect(_on_invest.bind(i))
		row.add_child(btn)
		var info := Label.new()
		info.text = "%s — +%s insight" % [str(s.get("name", "Site")), str(s.get("insight_reward", 0))]
		info.add_theme_color_override("font_color", INK)
		row.add_child(info)
		root.add_child(row)


func _on_invest(i: int) -> void:
	var es: Dictionary = _es()
	if i != int(es.get("stage", 0)):
		return
	var s: Dictionary = _event.get("stages", [])[i]
	var cost: BigNumber = BigNumber.from_parts(
		float(s.get("invest_cost_m", 1.0)), int(s.get("invest_cost_e", 0)))
	if not GameState.spend_cash(cost):
		_toast("Not enough cash")
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
	for pair in _owned_pairs():
		flow.add_child(_manager_card(pair))
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
	btn.custom_minimum_size = Vector2(0, 56)
	_style_button(btn, ACCENT)
	btn.disabled = _selected.is_empty()
	btn.pressed.connect(_on_fight_boss.bind(hp))
	root.add_child(btn)


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
	btn.toggled.connect(func(on: bool) -> void:
		if on:
			if _selected.size() >= 3:
				btn.button_pressed = false
				return
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
	_battle = BattleView.new()
	_battle.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_battle)
	_battle.setup_battle({
		"boss_name": str(boss.get("name", "The Temple Guardian")),
		"boss_hp": hp,
		"moves": int(boss.get("moves", 24)),
		"team": team,
	})
	_battle.battle_finished.connect(_on_boss_finished, CONNECT_ONE_SHOT)


func _on_boss_finished(result: String) -> void:
	Analytics.log_event("expedition_boss", {"cycle": _cycle(), "result": result})
	if result == "win":
		var boss: Dictionary = _event.get("boss", {})
		var applied: Dictionary = _apply_rewards(boss.get("rewards", {}))
		EventBus.event_stage_completed.emit("expedition", _cycle(), applied)
		# New cycle: track resets, boss hp scales +25%/cycle via persisted count.
		var es: Dictionary = _es()
		es["stage"] = 0
		es["invested"] = BigNumber.zero().to_save()
		es["boss_unlocked"] = false
		es["cycle"] = _cycle() + 1
		_show_outcome("Guardian defeated!\n%s\nA new expedition begins (cycle %d)." % [
			_applied_text(applied), _cycle() + 1])
	else:
		_show_outcome("The Guardian holds the temple.\nGrow your team and retry!")


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


func _show_outcome(text: String) -> void:
	_outcome = Panel.new()
	_outcome.set_anchors_preset(Control.PRESET_FULL_RECT)
	_outcome.add_theme_stylebox_override("panel", _style(Color(0, 0, 0, 0.6), 0))
	add_child(_outcome)
	var card := Panel.new()
	card.custom_minimum_size = Vector2(560, 340)
	card.position = Vector2(80, 470)
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
