extends SceneTree
## tests/events/test_battle_view.gd — the battler and its two host screens as the
## player meets them (SPEC §6, §11, §12). One case per shipped defect.
## Run: godot --headless --path <repo> -s tests/events/test_battle_view.gd

const BattleView = preload("res://scenes/events/battle_view.gd")
const BattleMath = preload("res://scripts/events/battle_math.gd")
const UI = preload("res://scripts/ui/ui_kit.gd")

## The two host screens reference autoload singletons by name, and those globals
## are only registered once the SceneTree has stood the autoloads up — which is
## after _initialize(). So the screens are load()ed inside run(), never preloaded.
const INSPECTION := "res://scenes/events/inspection_screen.gd"
const EXPEDITION := "res://scenes/events/expedition_screen.gd"
## The popup content area this screen lives in, measured from the shipped popup:
## rect (20, 180, 680, 984) in the 720x1280 design space.
const POPUP_W := 680

var failures := 0
var DL
var GS
var EB
var CG


func check(cond: bool, msg: String) -> void:
	if cond:
		print("PASS: ", msg)
	else:
		failures += 1
		printerr("FAIL: ", msg)


func _initialize() -> void:
	call_deferred("run")


func run() -> void:
	DL = root.get_node("DataLoader")
	GS = root.get_node("GameState")
	EB = root.get_node("EventBus")
	CG = root.get_node("ClockGuard")
	DL.reload_all()
	GS.reset_to_new_game()
	GS.settings["sfx"] = false  # keep the battery silent and fast
	# Never let a dev harness mutate the player's save: park the autosave timer
	# far out of reach before touching live GameState.
	root.get_node("SaveSystem").autosave_interval_sec = 1 << 30

	_test_view_paints_its_own_page()
	_test_board_is_readable()
	_test_board_fits_and_clears_the_touch_minimum()
	_test_setup_battle_is_synchronous()
	_test_a_whole_battle_terminates_once()
	_test_out_of_moves_loses_once()
	_test_damage_lands_on_the_board()
	_test_tap_and_swipe_both_move_the_board()
	_test_no_stage_button_is_a_dead_tap()
	_test_every_refused_tap_explains_itself()
	_test_boss_hp_follows_the_selected_team_only()
	_test_rewards_are_granted_exactly_once()
	_test_team_picker_never_refuses_a_tap()
	_test_expedition_buttons_are_never_dead()
	quit(1 if failures > 0 else 0)


# ------------------------------------------------------------------ helpers

func _mk_team(ids: Array, level: int = 5) -> Array:
	var out: Array = []
	for mid in ids:
		out.append({"def": DL.get_manager_def(mid),
			"state": {"level": level, "rank": 1, "cards": 1}, "id": mid})
	return out


func _mk_view(hp: float, moves: int, seed: int = 4242) -> Control:
	var v: Control = BattleView.new()
	v.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(v)
	v.setup_battle({"boss_name": "Chief Inspector", "boss_hp": hp, "moves": moves,
		"team": _mk_team(["barker_theo", "docent_poppy", "archivist_mabel"]), "seed": seed})
	return v


func _own(ids: Array, level: int = 5) -> void:
	for mid in GS.managers_state.keys():
		GS.managers_state[mid]["cards"] = 0
	for mid in ids:
		GS.managers_state[mid]["cards"] = 1
		GS.managers_state[mid]["level"] = level
		GS.managers_state[mid]["rank"] = 1


func _buttons(node: Node, out: Array = []) -> Array:
	for c in node.get_children():
		if c is Button:
			out.append(c)
		_buttons(c, out)
	return out


func _contrast(a: Color, b: Color) -> float:
	var la: float = a.get_luminance() + 0.05
	var lb: float = b.get_luminance() + 0.05
	return maxf(la, lb) / minf(la, lb)


func _play_until_done(v: Control, max_moves: int) -> int:
	var played := 0
	while not bool(v.battle_state()["over"]) and played < max_moves:
		var lm: Array = v._engine.legal_moves()
		if lm.is_empty():
			v._engine.reshuffle()
			continue
		played += 1
		v.play_move(lm[0]["a"], lm[0]["b"])
	return played


# ------------------------------------------------------------------ the view

## The view is parented over a live screen. Without an opaque page of its own the
## host's team picker, stage rows and reward text rendered straight THROUGH the
## board — the defect that read as "the game is broken".
func _test_view_paints_its_own_page() -> void:
	var v := _mk_view(400.0, 20)
	check(v.get_child_count() > 0, "battle view builds children")
	var first: Node = v.get_child(0)
	check(first is Panel, "the first child is a Panel, painted before anything else")
	var sb: StyleBox = (first as Panel).get_theme_stylebox("panel")
	check(sb is StyleBoxFlat, "the page is a flat fill")
	var flat := sb as StyleBoxFlat
	check(flat.bg_color.a >= 1.0, "the page is fully opaque (a=%.2f)" % flat.bg_color.a)
	check(flat.bg_color == UI.SURFACE,
		"the page is UI.SURFACE — popup content, not the deep app shell")
	check((first as Control).anchor_right == 1.0 and (first as Control).anchor_bottom == 1.0,
		"the page covers the whole view")
	check((first as Control).mouse_filter != Control.MOUSE_FILTER_IGNORE,
		"the page swallows taps meant for the screen underneath")
	v.free()


## Neutral was #F3ECFF on a #F7F2FF page — 1.03:1, with a white glyph on top, so
## a fifth of the board read as holes.
func _test_board_is_readable() -> void:
	var neutral: Color = BattleView.TILE_COLORS[4]
	check(_contrast(neutral, UI.SURFACE) >= 3.0,
		"the neutral tile separates from the page (%.2f:1)" % _contrast(neutral, UI.SURFACE))
	for i in BattleView.TILE_COLORS.size():
		var tile: Color = BattleView.TILE_COLORS[i]
		# Every department hue is light, so the RIM is what bounds the tile
		# against a #F7F2FF page — the fill cannot do it and never could.
		check(_contrast(BattleView.tile_rim(i), UI.SURFACE) >= 2.2,
			"tile %d is visibly bounded on the page (rim %.2f:1)" % [
				i, _contrast(BattleView.tile_rim(i), UI.SURFACE)])
		check(_contrast(BattleView.glyph_ink(i), tile) >= 3.0,
			"tile %d's glyph reads on it (%.2f:1)" % [
				i, _contrast(BattleView.glyph_ink(i), tile)])
	for i in 4:
		for j in range(i + 1, 5):
			check(_contrast(BattleView.TILE_COLORS[i], BattleView.TILE_COLORS[j]) >= 1.15
					or BattleView.TILE_RADIUS[i] != BattleView.TILE_RADIUS[j],
				"tiles %d and %d differ by value or by silhouette" % [i, j])


func _test_board_fits_and_clears_the_touch_minimum() -> void:
	check(BattleView.TILE >= UI.TOUCH_MIN,
		"a tile is at least the 48dp touch minimum (%d)" % BattleView.TILE)
	var span: int = 8 * BattleView.TILE + 7 * BattleView.GAP
	check(span <= POPUP_W, "the board fits the popup content width (%d <= %d)" % [span, POPUP_W])
	var v := _mk_view(400.0, 20)
	check(v._cells.size() == 8 and (v._cells[0] as Array).size() == 8, "8x8 of touch targets")
	var cell: Control = v._cells[3][5]
	check(cell.size.x >= float(UI.TOUCH_MIN) and cell.size.y >= float(UI.TOUCH_MIN),
		"each touch target is %dx%d" % [int(cell.size.x), int(cell.size.y)])
	check(cell.position == Vector2(5.0 * BattleView.BOARD_SPAN, 3.0 * BattleView.BOARD_SPAN),
		"cells sit on the board lattice so swaps and drops can be tweened")
	v.free()


## queue_free is deferred: a second setup_battle used to leave the previous board
## alive for a frame (2 children became 4). The retry button reuses the view.
func _test_setup_battle_is_synchronous() -> void:
	var v := _mk_view(400.0, 20)
	var first_count: int = v.get_child_count()
	v.setup_battle({"boss_name": "Chief Inspector", "boss_hp": 400.0, "moves": 20,
		"team": _mk_team(["barker_theo", "docent_poppy", "archivist_mabel"]), "seed": 77})
	check(v.get_child_count() == first_count,
		"re-arming the view leaves exactly one board (%d then %d children)" % [
			first_count, v.get_child_count()])
	check(v._cells.size() == 8, "the rebuilt board is still 8x8")
	check(int(v.battle_state()["moves"]) == 20, "the rebuilt battle starts fresh")
	v.free()


func _test_a_whole_battle_terminates_once() -> void:
	var v := _mk_view(40.0, 30)  # low HP: this one is meant to be won
	var results: Array = []
	v.battle_finished.connect(func(r: String) -> void: results.append(r))
	var played: int = _play_until_done(v, 30)
	check(results.size() == 1, "a finished battle emits battle_finished exactly once (%d)" % results.size())
	check(results.size() > 0 and str(results[0]) == "win", "beating the boss reports a win")
	check(float(v.battle_state()["hp"]) <= 0.0, "the boss is actually at zero")
	check(played < 30, "the win landed before the move budget ran out (%d moves)" % played)
	# A terminal battle refuses further moves rather than double-emitting.
	var lm: Array = v._engine.legal_moves(1)
	if not lm.is_empty():
		check(not v.play_move(lm[0]["a"], lm[0]["b"]), "a finished battle refuses more moves")
	check(results.size() == 1, "no second battle_finished after the end")
	v.free()


func _test_out_of_moves_loses_once() -> void:
	var v := _mk_view(1.0e9, 6)  # unreachable HP: this one is meant to be lost
	var results: Array = []
	v.battle_finished.connect(func(r: String) -> void: results.append(r))
	_play_until_done(v, 20)
	check(results.size() == 1, "running out of moves emits once (%d)" % results.size())
	check(results.size() > 0 and str(results[0]) == "lose", "running out of moves reports a loss")
	check(int(v.battle_state()["moves"]) <= 0, "the move counter really reached zero")
	check(bool(v.battle_state()["over"]), "the battle is marked over")
	v.free()


## Damage numbers used to spawn at a fixed (300,120) in view space — the host's
## "Pick your team" band, ~130px above the first tile row.
func _test_damage_lands_on_the_board() -> void:
	var v := _mk_view(400.0, 20)
	var top_left: Vector2 = v._centroid([Vector2i(0, 0)])
	var bottom_right: Vector2 = v._centroid([Vector2i(7, 7)])
	var delta: Vector2 = bottom_right - top_left
	check(is_equal_approx(delta.x, 7.0 * BattleView.BOARD_SPAN)
			and is_equal_approx(delta.y, 7.0 * BattleView.BOARD_SPAN),
		"floaters track the cleared cells across the whole board (delta %s)" % str(delta))
	var mid: Vector2 = v._centroid([Vector2i(3, 3), Vector2i(4, 3)])
	check(is_equal_approx(mid.y, v._centroid([Vector2i(3, 3)]).y),
		"a multi-cell clear floats from the centroid of its own cells")
	check(mid != Vector2(300.0, 120.0), "floaters are no longer pinned to the header band")
	v.free()


func _press(v: Control, cell: Vector2i, at: Vector2, down: bool) -> void:
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = down
	e.position = at
	v._on_cell_input(e, cell)


func _drag_to(v: Control, cell: Vector2i, at: Vector2) -> void:
	var e := InputEventMouseMotion.new()
	e.position = at
	v._on_cell_input(e, cell)


## Priority one: every tap acts. Tap-then-tap was the only gesture the shipped
## board understood; a thumb flick — the genre standard — did nothing at all.
func _test_tap_and_swipe_both_move_the_board() -> void:
	var centre := Vector2(BattleView.TILE, BattleView.TILE) * 0.5

	var tapper := _mk_view(1.0e9, 20)
	var mv: Dictionary = tapper._engine.legal_moves(1)[0]
	_press(tapper, mv["a"], centre, true)
	_press(tapper, mv["a"], centre, false)
	check(tapper._selected == Vector2i(mv["a"]), "the first tap selects a tile")
	_press(tapper, mv["b"], centre, true)
	_press(tapper, mv["b"], centre, false)
	check(int(tapper.battle_state()["moves"]) == 19, "tap-then-tap plays the move")
	check(tapper._selected == Vector2i(-1, -1), "the selection clears after the move")
	tapper.free()

	var swiper := _mk_view(1.0e9, 20)
	var mv2: Dictionary = swiper._engine.legal_moves(1)[0]
	var from: Vector2i = mv2["a"]
	var to: Vector2i = mv2["b"]
	var dir := Vector2(to - from) * (BattleView.DRAG_THRESHOLD + 8.0)
	_press(swiper, from, centre, true)
	_drag_to(swiper, from, centre + dir)
	check(int(swiper.battle_state()["moves"]) == 19, "a swipe plays the move under the thumb")
	check(swiper._press_cell == Vector2i(-1, -1), "the swipe releases its own press")
	# A swipe shorter than the threshold must not fire — that is a tap, not a drag.
	var quiet := _mk_view(1.0e9, 20)
	var mv3: Dictionary = quiet._engine.legal_moves(1)[0]
	_press(quiet, mv3["a"], centre, true)
	_drag_to(quiet, mv3["a"], centre + Vector2(BattleView.DRAG_THRESHOLD - 10.0, 0))
	check(int(quiet.battle_state()["moves"]) == 20, "a jitter under the threshold is not a swipe")
	_press(quiet, mv3["a"], centre, false)
	check(quiet._selected == Vector2i(mv3["a"]), "and it still lands as a tap")
	quiet.free()
	swiper.free()


# ------------------------------------------------------------ host screens

func _open_inspection() -> Control:
	GS.first_launch_unix = CG.now() - 3 * 86400  # past the day-1 gate
	var s: Control = load(INSPECTION).new()
	s.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(s)
	return s


## A disabled button swallows the tap and reads as a broken game. The shipped
## screen disabled all six stages whenever no manager was picked — and a Day-1
## player owns none, because the event opens on day 1 and managers unlock at rep 6.
func _test_no_stage_button_is_a_dead_tap() -> void:
	_own([])
	GS.event_state.erase("inspection_frenzy")
	var s := _open_inspection()
	var dead: Array = []
	for b in _buttons(s):
		if b.disabled:
			dead.append(b.text)
	check(dead.is_empty(), "a rosterless player faces no disabled buttons (dead: %s)" % str(dead))
	var stage_buttons := 0
	for b in _buttons(s):
		if b.text.begins_with("Stage "):
			stage_buttons += 1
	check(stage_buttons == 6, "all six stage buttons are present and live (%d)" % stage_buttons)
	s.free()


func _test_every_refused_tap_explains_itself() -> void:
	_own([])
	GS.event_state.erase("inspection_frenzy")
	var s := _open_inspection()
	var toasts: Array = []
	var sink := func(t: String) -> void: toasts.append(t)
	EB.toast_requested.connect(sink)

	s._on_play_stage(0)
	check(toasts.size() == 1, "tapping a stage with the window closed says something")
	toasts.clear()

	s._on_start_pressed()  # opens the window
	s._on_play_stage(0)
	check(toasts.size() == 1 and str(toasts[0]).contains("Recruit"),
		"with no managers the stage tap points at the Store (got %s)" % str(toasts))
	toasts.clear()

	_own(["barker_theo", "docent_poppy"])
	s._build()
	s._on_play_stage(0)
	check(toasts.size() == 1 and str(toasts[0]).contains("Pick"),
		"with managers but no picks the stage tap asks for a team (got %s)" % str(toasts))
	toasts.clear()

	s._selected = ["barker_theo"]
	s._on_play_stage(3)
	check(toasts.size() == 1 and str(toasts[0]).contains("Clear stage"),
		"tapping a locked stage says which one to clear first (got %s)" % str(toasts))
	toasts.clear()

	s._on_play_stage(0)
	check(toasts.is_empty(), "a legal stage tap opens a battle instead of talking")
	check(s._battle != null, "the battle view actually opened")
	check(not s._scroll.visible, "the host page is hidden so nothing bleeds past the board")
	EB.toast_requested.disconnect(sink)
	s.free()


## THE inversion regression at the screen level: boss HP must key off the three
## managers being SENT IN, never the owned roster. The shipped screen fed
## _owned_team_power() into stage_boss_hp(), so every manager the event handed
## out made the event harder.
func _test_boss_hp_follows_the_selected_team_only() -> void:
	var all_ids: Array = []
	for mid in GS.managers_state.keys():
		all_ids.append(mid)
	_own(all_ids, 5)
	GS.event_state.erase("inspection_frenzy")
	var s := _open_inspection()
	s._on_start_pressed()
	var picks: Array = [all_ids[0], all_ids[1], all_ids[2]]
	s._selected = picks.duplicate()
	s._on_play_stage(0)
	check(s._battle != null, "battle opened with a full roster owned")
	var ev: Dictionary = DL.get_event("inspection_frenzy")
	var selected_power: float = s._selected_team_power()
	var owned_pairs: Array = []
	for mid in all_ids:
		owned_pairs.append({"def": DL.get_manager_def(mid), "state": GS.managers_state[mid]})
	var owned_power: float = BattleMath.team_power(owned_pairs)
	var hp: float = float(s._battle.battle_state()["hp_max"])
	check(is_equal_approx(hp, BattleMath.stage_boss_hp(ev, 0, selected_power)),
		"boss HP is quoted against the selected team (%.0f)" % hp)
	check(owned_power > selected_power * 2.0,
		"the test really is holding a much larger roster (%.0f vs %.0f)" % [
			owned_power, selected_power])
	check(hp < BattleMath.stage_boss_hp(ev, 0, owned_power),
		"owning more managers than you bring does NOT raise the boss")
	check(hp < BattleMath.expected_damage(selected_power, BattleMath.stage_moves(ev, 0)),
		"the fight the player actually gets is inside their damage budget")
	s.free()


## _apply_rewards used to run BEFORE the "already completed" check; the only
## thing preventing a double grant was the stage button happening to be disabled.
func _test_rewards_are_granted_exactly_once() -> void:
	_own(["barker_theo", "docent_poppy", "archivist_mabel"])
	GS.event_state.erase("inspection_frenzy")
	var s := _open_inspection()
	s._on_start_pressed()
	s._selected = ["barker_theo", "docent_poppy", "archivist_mabel"]
	var gems_before: int = GS.gems
	var grants: Array = []
	var sink := func(_id: String, _i: int, r: Dictionary) -> void: grants.append(r)
	EB.event_stage_completed.connect(sink)
	s._on_battle_finished("win", 1)  # stage 2 pays 5 gems
	var gems_after: int = GS.gems
	s._on_battle_finished("win", 1)  # a retry, a re-emitted signal, a double tap
	check(grants.size() == 1, "a repeated win emits event_stage_completed once (%d)" % grants.size())
	check(GS.gems == gems_after, "a repeated win grants no second reward")
	check(gems_after == gems_before + 5, "the first win did pay out (%d -> %d)" % [
		gems_before, gems_after])
	check(GS.event_state["inspection_frenzy"]["completed"].count(1) == 1,
		"the stage is recorded as cleared exactly once")
	EB.event_stage_completed.disconnect(sink)
	s.free()


## Picking a fourth manager used to disable every other card / snap silently back.
func _test_team_picker_never_refuses_a_tap() -> void:
	_own(["barker_theo", "docent_poppy", "archivist_mabel", "storyteller_june"])
	GS.event_state.erase("inspection_frenzy")
	var s := _open_inspection()
	s._on_start_pressed()
	for mid in ["barker_theo", "docent_poppy", "archivist_mabel"]:
		s._selected.append(mid)
	s._build()
	var dead: Array = []
	for b in _buttons(s):
		if b.disabled:
			dead.append(b.text)
	check(dead.is_empty(), "a full team leaves every card tappable (dead: %s)" % str(dead))
	# The fourth pick rotates the oldest out rather than doing nothing.
	var before: Array = s._selected.duplicate()
	for b in _buttons(s):
		if b.text.contains("June"):
			b.pressed.emit()
			break
	check(s._selected.size() == 3, "the team stays capped at three (%d)" % s._selected.size())
	check(s._selected.has("storyteller_june"), "the fourth pick actually joined")
	check(not s._selected.has(before[0]), "the oldest pick stepped aside")
	s.free()


func _test_expedition_buttons_are_never_dead() -> void:
	GS.reputation_xp = BigNumber.from_float(1.0e9)  # past the rep-7 gate
	_own(["barker_theo", "docent_poppy"])
	GS.expedition_state["stage"] = 0
	GS.expedition_state["boss_unlocked"] = false
	GS.cash = BigNumber.zero()  # cannot afford a single dig site
	var s: Control = load(EXPEDITION).new()
	s.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(s)
	check(GS.feature_unlocked("expedition"), "test really is past the expedition gate")
	var dead: Array = []
	for b in _buttons(s):
		if b.disabled:
			dead.append(b.text)
	check(dead.is_empty(), "a broke player faces no disabled invest buttons (dead: %s)" % str(dead))
	var toasts: Array = []
	var sink := func(t: String) -> void: toasts.append(t)
	EB.toast_requested.connect(sink)
	s._on_invest(0)
	check(toasts.size() == 1 and str(toasts[0]).contains("Needs"),
		"an unaffordable dig site names its price (got %s)" % str(toasts))
	toasts.clear()
	s._on_invest(3)
	check(toasts.size() == 1 and str(toasts[0]).contains("Fund"),
		"an out-of-order dig site says which one comes first (got %s)" % str(toasts))
	EB.toast_requested.disconnect(sink)
	s.free()
