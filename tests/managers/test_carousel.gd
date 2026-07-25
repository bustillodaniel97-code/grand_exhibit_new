extends SceneTree
## tests/managers/test_carousel.gd — the staff-pass coverflow: selection, drag,
## culling, and the one treatment a sealed file is allowed to have.
## Run: godot --headless --path . -s tests/managers/test_carousel.gd ; exit 0 = pass.
##
## NOTE on bootstrap: under `-s` this entry script compiles BEFORE autoload
## globals resolve, so it must not reference them by name. By the time run()
## executes the autoloads are live root children — fetch them via root.get_node()
## and only then load() scripts that reference autoload names.
const SCREEN_PATH := "res://scenes/managers/managers_screen.tscn"
const BADGE_PATH := "res://scenes/managers/manager_badge.gd"
const PORTRAIT_PATH := "res://scenes/managers/manager_portrait.gd"
const MS_PATH := "res://scripts/managers/manager_system.gd"

## Design canvas the carousel is laid out against in these tests.
const BOX := Vector2(692, 1000)

var _failures := 0

func _init() -> void:
	call_deferred("run")

func check(cond: bool, msg: String) -> void:
	if cond:
		print("PASS  ", msg)
	else:
		_failures += 1
		printerr("FAIL  ", msg)

func run() -> void:
	var gs: Node = root.get_node("GameState")
	gs.reset_to_new_game()
	var ManagerSystem: GDScript = load(MS_PATH)
	# A mixed roster: the carousel has to fly issued and sealed passes alike.
	ManagerSystem.add_cards("docent_poppy", 3)
	ManagerSystem.add_cards("night_curator", 1)

	await _check_sealed_treatment()
	await _check_carousel()

	print("DONE failures=", _failures)
	quit(0 if _failures == 0 else 1)

# ------------------------------------------------------------------ sealed

## A sealed file used to render two different ways depending on a race: the
## badge inked a finished portrait out to a near-black silhouette, so an
## undiscovered manager was a dark figure once the bake landed and a "?" plate
## until it did. There is now exactly one sealed treatment, and it never asks the
## baker for anything.
func _check_sealed_treatment() -> void:
	var DL: Node = root.get_node("DataLoader")
	var Portrait: GDScript = load(PORTRAIT_PATH)
	var def: Dictionary = DL.managers["barker_theo"]
	var host := Control.new()
	root.add_child(host)

	var sealed: Control = Portrait.new()
	host.add_child(sealed)
	sealed.setup(def, 120, false)
	var sealed_text := _labels(sealed)
	check(sealed_text.has("?") and sealed_text.has("SEALED"),
		"a sealed file renders the ? plate and the SEALED stamp %s" % [sealed_text])
	check(not sealed_text.has(str(def.get("name", "")).substr(0, 1))
			or str(def.get("name", "")).substr(0, 1) == "?",
		"a sealed file never shows the manager's initial")

	var open: Control = Portrait.new()
	host.add_child(open)
	open.setup(def, 120, true)
	var open_text := _labels(open)
	check(open_text.has(str(def.get("name", "")).substr(0, 1)),
		"an issued file shows the manager's initial until the bake lands %s" % [open_text])
	check(not open_text.has("SEALED"), "an issued file is never stamped SEALED")

	# The whole-card view of the same rule: no dark-silhouette variant survives.
	var Badge: GDScript = load(BADGE_PATH)
	var card: Control = Badge.new()
	host.add_child(card)
	card.setup("barker_theo", def, {"level": 1, "rank": 1, "cards": 0}, false, false)
	var card_text := _labels(card)
	check(card_text.has("SEALED") and card_text.has("Personnel File Sealed"),
		"a sealed pass says so on the photo AND in the name field")
	check(card_text.has("DEPT") and card_text.has("—"),
		"a sealed pass keeps the stat strip, dashed out, so the deck is one shape")
	host.free()

## Every Label string under `node`, flattened.
func _labels(node: Node) -> Array:
	var out: Array = []
	for c in node.get_children():
		if c is Label:
			out.append((c as Label).text)
		out.append_array(_labels(c))
	return out

# ---------------------------------------------------------------- carousel

func _check_carousel() -> void:
	var DL: Node = root.get_node("DataLoader")
	var screen: Control = (load(SCREEN_PATH) as PackedScene).instantiate()
	root.add_child(screen)
	screen.set_anchors_preset(Control.PRESET_TOP_LEFT)
	screen.size = BOX
	await process_frame
	await process_frame
	var n: int = DL.managers.size()

	# --- selection is position, not a stored field -----------------------------
	check(screen.selected_index() == 0, "carousel opens on the first pass")
	check(screen.selected_id() == screen._ids[0], "selected_id follows selected_index")
	check(screen._dots.get_child_count() == n, "one position dot per pass (%d)" % n)
	check(screen._counter.text == "1 of %d" % n,
		"the counter reads the position (%s)" % screen._counter.text)

	var target: String = str(screen._ids[9])
	screen.select_manager(target)
	await _settle(screen)
	check(screen.selected_index() == 9, "select_manager centres the pass it is given")
	check(screen.selected_id() == target, "the centred pass is the selected one")
	check(screen._counter.text == "10 of %d" % n, "the counter follows selection")
	# Nine places forward is five places back on a fourteen-pass merry-go-round.
	check(absf(screen._target + 5.0) < 0.001,
		"selection turns the short way round (%.1f)" % screen._target)

	# --- the ring: only a few passes are ever alive ----------------------------
	var here: int = roundi(screen._target)
	var live := 0
	var far := 0
	for s in screen._slots:
		if s["card"] != null:
			live += 1
		if absi(int(s["index"]) - here) > 2:
			far += 1
	check(live <= 5, "at most five passes exist at once (%d)" % live)
	check(far == 0, "every live pass is within two places of the centre")
	var visible := 0
	for s in screen._slots:
		if (s["holder"] as Control).visible:
			visible += 1
	check(visible <= 5 and visible >= 3, "three to five passes are on stage (%d)" % visible)

	# --- drag: the deck tracks the finger, then snaps ---------------------------
	screen.select_manager(screen._ids[5], true)
	await _settle(screen)
	var stride: float = screen._stride()
	var from: float = screen._pos
	screen._press(Vector2(600, 500))
	screen._move(Vector2(600 - stride, 500))
	check(absf(screen._pos - (from + 1.0)) < 0.02,
		"dragging one stride left moves the deck exactly one pass (%.3f)" % (screen._pos - from))
	screen._move(Vector2(600 - stride * 0.5, 500))
	check(absf(screen._pos - (from + 0.5)) < 0.02,
		"the deck follows the finger back (%.3f)" % (screen._pos - from))
	screen._release(Vector2(600 - stride * 0.5, 500))
	await _settle(screen)
	check(screen._pos > from, "a leftward swipe advances the carousel")
	check(absf(screen._pos - float(roundi(screen._pos))) < 0.001,
		"the deck settles exactly on a pass, never between two (%.4f)" % screen._pos)
	check(screen.selected_index() == screen._wrap(roundi(screen._pos)),
		"the selected pass is the one the deck settled on")

	# --- a tap is not a drag ----------------------------------------------------
	var before: int = screen.selected_index()
	screen._press(Vector2(400, 500))
	screen._move(Vector2(404, 500))
	screen._release(Vector2(404, 500))
	await _settle(screen)
	check(screen.selected_index() == before,
		"a press that wobbles four pixels on the centred pass changes nothing")
	# Tapping a receded pass brings it to the front.
	var place: int = roundi(screen._target)
	var right: Dictionary = _slot_at(screen, place + 1)
	check(not right.is_empty(), "the next pass is on stage to be tapped")
	if not right.is_empty():
		# Aim at the part of the neighbour that is actually exposed. Its middle is
		# behind the centred pass, and a tap there belongs to the card in front.
		var aim := Vector2(float(right["x"]) + float(right["w"]) * 0.35, float(right["y"]))
		screen._press(aim)
		screen._release(aim)
		await _settle(screen)
		check(screen.selected_index() == screen._wrap(place + 1),
			"tapping a receded pass centres it")

	# --- the merry-go-round has no ends -----------------------------------------
	check(screen._wraps(), "a fourteen-pass roster wraps")
	screen.select_manager(screen._ids[0], true)
	await _settle(screen)
	screen._press(Vector2(300, 500))
	screen._move(Vector2(300 + stride * 2.0, 500))
	check(screen._pos < -1.9,
		"the deck turns straight past the first pass (%.3f)" % screen._pos)
	# Selection commits on release, so mid-drag it is the DECK that has moved.
	check(screen._wrap(roundi(screen._pos)) == n - 2,
		"two places back from the first pass is the second-to-last (%d)"
			% screen._wrap(roundi(screen._pos)))
	screen._release(Vector2(300 + stride * 2.0, 500))
	await _settle(screen)
	screen.select_manager(screen._ids[n - 1], true)
	await _settle(screen)
	var last_place: int = roundi(screen._target)
	screen._press(Vector2(600, 500))
	screen._move(Vector2(600 - stride * 2.0, 500))
	screen._release(Vector2(600 - stride * 2.0, 500))
	await _settle(screen)
	check(roundi(screen._target) > last_place and screen.selected_index() < n - 1,
		"turning past the last pass comes back round to the front (%d)" % screen.selected_index())

	# --- recede: the shape of the effect ---------------------------------------
	screen.select_manager(screen._ids[6], true)
	await _settle(screen)
	var centre_place: int = roundi(screen._target)
	var mid: Dictionary = _slot_at(screen, centre_place)
	var side: Dictionary = _slot_at(screen, centre_place + 1)
	var out: Dictionary = _slot_at(screen, centre_place + 2)
	check(not mid.is_empty() and not side.is_empty() and not out.is_empty(),
		"centre and two neighbours are on stage")
	if not mid.is_empty() and not side.is_empty() and not out.is_empty():
		var mh: Control = mid["holder"]
		var sh: Control = side["holder"]
		var oh: Control = out["holder"]
		check(absf(float(mid["x"]) - screen._deck.size.x * 0.5) < 1.0,
			"the centred pass is dead centre (%.1f of %.0f)"
				% [float(mid["x"]), screen._deck.size.x])
		check(float(side["x"]) > float(mid["x"]) and float(out["x"]) > float(side["x"]),
			"neighbours step outward, in order")
		check(sh.scale.y < mh.scale.y and oh.scale.y < sh.scale.y,
			"each step out is smaller")
		check(sh.scale.x / sh.scale.y < 0.75,
			"side passes are squashed horizontally to fake the turn (%.2f)"
				% (sh.scale.x / sh.scale.y))
		check(float(side["y"]) > float(mid["y"]) and float(out["y"]) > float(side["y"]),
			"each step out also drops")
		check(sh.modulate.r < mh.modulate.r and oh.modulate.a < sh.modulate.a,
			"each step out dims and fades")
		check(mh.get_index() > sh.get_index() and sh.get_index() > oh.get_index(),
			"the nearest pass draws in front, by sibling order rather than z_index")
		check(float(side["x"]) - float(mid["x"]) < mh.scale.x * 352.0,
			"the first neighbour tucks behind the centred pass, not beside it")

	# --- the action bar belongs to the centred pass -----------------------------
	var MS: GDScript = load(MS_PATH)
	screen.select_manager("barker_theo")      # sealed in this fixture
	await _settle(screen)
	check(_buttons(screen._actions).is_empty(),
		"a sealed pass offers no actions, only the line saying where to find it")
	check(screen._actions.custom_minimum_size.y >= 3.0 * 48.0,
		"the action bar holds its height either way, so the deck never shifts")
	screen.select_manager("docent_poppy")     # issued, ticket specialty
	await _settle(screen)
	var acts: Array = _buttons(screen._actions)
	check(acts.size() == 4, "an issued pass offers level, rank, trade and post (%d)" % acts.size())
	var live_actions := true
	var post: Button = null
	for b in acts:
		if (b as Button).disabled:
			live_actions = false
		if str((b as Button).text).begins_with("Post to"):
			post = b
	check(live_actions, "no action is ever disabled — a dead tap reads as a broken screen")
	check(post != null, "the post button names the one department that will take them")
	if post != null:
		post.emit_signal("pressed")
		await process_frame
		check(MS.assigned_to("docent_poppy") == "ticket", "the post button posts them")
		var on_duty := false
		for b in _buttons(screen._actions):
			if str((b as Button).text).begins_with("On duty"):
				on_duty = true
		check(on_duty, "the bar rebuilds itself into the stand-down state")

	# --- a short stage shrinks the deck instead of clipping it -----------------
	screen.size = Vector2(BOX.x, 520)
	await process_frame
	await process_frame
	var squeezed: Dictionary = _slot_at(screen, roundi(screen._target))
	check(not squeezed.is_empty() and (squeezed["holder"] as Control).scale.y < 1.0,
		"a short viewport scales the whole carousel down rather than cropping it")
	screen.free()

## Wait for the settle animation to finish, with a frame budget so a carousel
## that never lands fails the assertion instead of hanging the suite.
func _settle(screen: Control) -> void:
	for _i in 240:
		await process_frame
		if is_equal_approx(screen._pos, screen._target):
			return

## Every Button under `node`.
func _buttons(node: Node) -> Array:
	var out: Array = []
	for c in node.get_children():
		if c is Button:
			out.append(c)
		out.append_array(_buttons(c))
	return out

## The live slot at carousel place `place`, or an empty dictionary.
func _slot_at(screen: Control, place: int) -> Dictionary:
	for s in screen._slots:
		if int(s["index"]) == place and (s["holder"] as Control).visible:
			return s
	return {}
