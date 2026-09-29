extends SceneTree
## test_decor_visuals.gd — a bought piece must be a DISTINCT, VISIBLE object.
##
## Two defects are pinned here.
##
## IDENTITY. `_decor_kind` used to collapse 24 products into 8 painters by
## substring guesswork, and `_decor_spec` then handed those painters fields they
## do not read — `_bench` takes `len`/`col`/`rail`, and it was being given `size`
## and `wood`. Every bench in the game therefore drew at stock length in stock
## timber, and five different purchases were pixel-identical. Now each id carries
## an authored `visual` block in data/decor.json written in the painter's own
## vocabulary, and the checks below refuse a build where any sellable id has no
## block, names a painter that does not exist, or is indistinguishable from
## another id.
##
## PRESENCE. A piece the player paid for has to actually appear: a node on the
## floor, at an anchor that projects inside the camera, with a reveal that says
## which of thirty props is the new one. The end of this file is the full
## purchase integration assertion the handoff specifies, run without reopening
## the venue.
##
## Run: godot --headless --path <repo> -s tests/venue/test_decor_visuals.gd

const Iso := preload("res://scenes/venue/floor/iso.gd")
const Exhibits := preload("res://scenes/venue/floor/exhibits.gd")

## Pixels of margin a decor anchor must keep from the clip edge. The projected
## diamond is wider than the canvas, so a piece placed outside this simply never
## renders — silently, which is the failure players call "it did not spawn".
const EDGE_INSET := 22.0

## load() at runtime, NOT preload(). Under -s the main script compiles before
## autoload names are reliably bound, and these helpers name
## GameState/DataLoader/Analytics at class scope. Preloading them compiles
## them too early: the calls then no-op against a dead GDScript, no check()
## ever runs, and the suite reports a FALSE GREEN.
var DecorSystem: GDScript

var _fail: int = 0
var _floor: Control
var _frames: int = 0
var _done: bool = false

var GS: Node
var DL: Node
var EB: Node
var EC: Node

func check(cond: bool, msg: String) -> void:
	if cond:
		print("PASS: ", msg)
	else:
		_fail += 1
		printerr("FAIL: ", msg)

func _initialize() -> void:
	_boot()

func _boot() -> void:
	seed(20260729)
	for pair in [["EventBus", "res://autoload/event_bus.gd"],
			["DataLoader", "res://autoload/data_loader.gd"],
			["ClockGuard", "res://autoload/clock_guard.gd"],
			["Analytics", "res://autoload/analytics.gd"],
			["AdService", "res://autoload/ad_service.gd"],
			["IAPService", "res://autoload/iap_service.gd"],
			["GameState", "res://autoload/game_state.gd"],
			["SaveSystem", "res://autoload/save_system.gd"],
			["Economy", "res://autoload/economy.gd"]]:
		if root.has_node(pair[0]):
			continue
		var n: Node = (load(pair[1]) as GDScript).new()
		n.name = pair[0]
		root.add_child(n)
	# Doctoring GameState with the autosave clock running writes test values into
	# a real save. Stop it before touching anything.
	var ss: Node = root.get_node("SaveSystem")
	ss.set_process(false)
	ss.autosave_interval_sec = 1 << 30

	DecorSystem = load("res://scripts/meta/decor_system.gd") as GDScript
	GS = root.get_node("GameState")
	DL = root.get_node("DataLoader")
	EB = root.get_node("EventBus")
	EC = root.get_node("Economy")
	DL.reload_all()
	GS.reset_to_new_game()
	GS.ready_flag = true

	_floor = (load("res://scenes/venue/floor/venue_floor.tscn") as PackedScene).instantiate()
	_floor.set_size(Vector2(720, 760))
	root.add_child(_floor)

func _process(_delta: float) -> bool:
	if _done:
		return true
	_frames += 1
	if _frames < 4:  # let the floor build its theme and first prop pass
		return false
	_done = true
	_check_every_id_is_authored()
	_check_kinds_are_real()
	_check_ids_are_distinguishable()
	_check_each_category_appears()
	_check_anchors_are_on_camera()
	_check_navigation_clearance()
	_check_every_venue_places_cleanly()
	_check_purchase_integration()
	print("---")
	if _fail == 0:
		print("ALL DECOR VISUAL CHECKS PASSED")
	quit(0 if _fail == 0 else 1)
	return true

# --- helpers ------------------------------------------------------------------

func _sellable() -> Array:
	var out: Array = []
	for did in DL.decor.keys():
		out.append(str(did))
	out.sort()
	if OS.get_environment("GRAND_EXHIBIT_DECOR_LARGEST_FIRST") == "1":
		out.sort_custom(func(a: String, b: String) -> bool:
			var ak: String = _floor._decor_kind(a, str(DL.get_decor(a).get("slot_theme", "hall")))
			var bk: String = _floor._decor_kind(b, str(DL.get_decor(b).get("slot_theme", "hall")))
			var aa := Exhibits.footprint(_floor._decor_spec(a, ak, Vector2.ZERO, 0))
			var bb := Exhibits.footprint(_floor._decor_spec(b, bk, Vector2.ZERO, 0))
			return aa.x * aa.y > bb.x * bb.y)
	return out

func _clear_decor(vid: String) -> void:
	for did in _sellable():
		DecorSystem.remove_decor(vid, did)

func _decor_prop_count() -> int:
	return (_floor._props as Array).size()

# --- identity -----------------------------------------------------------------

func _check_every_id_is_authored() -> void:
	var unauthored: Array = []
	for did in _sellable():
		var v: Dictionary = _floor._decor_visual(did)
		if not v.has("kind"):
			unauthored.append(did)
	check(unauthored.is_empty(),
		"every sellable decor id has an authored visual (missing: %s)"
			% ("none" if unauthored.is_empty() else ", ".join(unauthored)))

func _check_kinds_are_real() -> void:
	var bad: Array = []
	for did in _sellable():
		var kind: String = _floor._decor_kind(did, str(DL.get_decor(did).get("slot_theme", "hall")))
		if not Exhibits.has_kind(kind):
			bad.append("%s->%s" % [did, kind])
	check(bad.is_empty(),
		"every decor id names a painter that exists (bad: %s)"
			% ("none" if bad.is_empty() else ", ".join(bad)))

## No two products may resolve to the same drawing. Comparing the KIND together
## with the fully resolved spec catches both "these are the same painter with the
## same numbers" and the subtler "these differ only in a field the painter never
## reads", which is exactly how the five identical benches shipped.
func _check_ids_are_distinguishable() -> void:
	var at := Vector2(4.0, 6.0)  # one fixed anchor, so position cannot mask a clash
	var seen: Dictionary = {}
	var clashes: Array = []
	for did in _sellable():
		var theme: String = str(DL.get_decor(did).get("slot_theme", "hall"))
		var kind: String = _floor._decor_kind(did, theme)
		var spec: Dictionary = _floor._decor_spec(did, kind, at, 0)
		var keys: Array = spec.keys()
		keys.sort()
		var sig: String = kind
		for k in keys:
			sig += "|%s=%s" % [str(k), str(spec[k])]
		if seen.has(sig):
			clashes.append("%s == %s" % [str(seen[sig]), did])
		else:
			seen[sig] = did
	check(clashes.is_empty(),
		"no two decor products draw identically (%d clashes%s)" % [clashes.size(),
			"" if clashes.is_empty() else ": " + ", ".join(clashes)])

	# Distinct silhouettes, not merely distinct tints. Colour alone is not enough
	# to tell two products apart at gameplay zoom, and it is invisible to a
	# colour-blind player, so the catalogue has to span many painters.
	var kinds: Dictionary = {}
	for did in _sellable():
		kinds[_floor._decor_kind(did, str(DL.get_decor(did).get("slot_theme", "hall")))] = true
	check(kinds.size() >= 12,
		"the catalogue spans %d distinct silhouettes (>= 12)" % kinds.size())

# --- presence -----------------------------------------------------------------

## One before/after assertion per visual category: place a representative of the
## category into the live venue and prove the floor gained a node for it.
func _check_each_category_appears() -> void:
	var vid: String = GS.current_venue
	var by_kind: Dictionary = {}
	for did in _sellable():
		var kind: String = _floor._decor_kind(did, str(DL.get_decor(did).get("slot_theme", "hall")))
		if not by_kind.has(kind):
			by_kind[kind] = did
	var kinds: Array = by_kind.keys()
	kinds.sort()

	var missed: Array = []
	var no_anchor: Array = []
	for kind in kinds:
		var did: String = str(by_kind[kind])
		_clear_decor(vid)
		_floor._props_key = ""
		_floor._rebuild_props()
		var before: int = _decor_prop_count()
		var had_anchor: bool = (_floor._decor_anchor_by_id as Dictionary).has(did)

		# Buying is per museum now, so stock it HERE rather than unlocking globally.
		GS.cash = BigNumber.from_parts(9.0, 12)
		GS.gems = 100000
		# Event-exclusive pieces are deliberately unbuyable; they arrive as
		# expedition rewards, so acquire them the way the game does.
		var got: bool = DecorSystem.buy_decor(vid, did)
		if not got and bool(DL.get_decor(did).get("event_exclusive", false)):
			got = DecorSystem.grant_event_decor(did, vid)
		if not got:
			missed.append("%s(acquire failed)" % did)
			continue
		_floor._props_key = ""
		_floor._rebuild_props()
		var after: int = _decor_prop_count()
		if after <= before:
			missed.append("%s(%s: %d->%d)" % [did, str(kind), before, after])
		if had_anchor or not (_floor._decor_anchor_by_id as Dictionary).has(did):
			no_anchor.append("%s(%s)" % [did, str(kind)])

	check(missed.is_empty(),
		"every visual category adds a prop when placed (%d categories; failures: %s)"
			% [kinds.size(), "none" if missed.is_empty() else ", ".join(missed)])
	check(no_anchor.is_empty(),
		"every placed piece records a floor anchor (failures: %s)"
			% ("none" if no_anchor.is_empty() else ", ".join(no_anchor)))
	_clear_decor(vid)

## A piece placed outside the projected canvas renders nothing at all, with no
## error. Every anchor a venue can hand a decor piece must be comfortably inside.
func _check_anchors_are_on_camera() -> void:
	var vid: String = GS.current_venue
	var offscreen: Array = []
	for slot_theme in ["entrance", "hall", "garden"]:
		var anchors: Array = _floor._decor_room_anchors(slot_theme)
		if anchors.is_empty():
			continue
		for a in anchors:
			var p: Vector2 = Iso.to_screen(a as Vector2)
			if p.x < EDGE_INSET or p.x > Iso.VIEW.x - EDGE_INSET \
					or p.y < 0.0 or p.y > Iso.VIEW.y:
				offscreen.append("%s%s->%.0f,%.0f" % [slot_theme, str(a), p.x, p.y])
	check(offscreen.is_empty(),
		"every decor anchor in %s projects inside the camera (%s)"
			% [vid, "all clear" if offscreen.is_empty() else ", ".join(offscreen)])

	# And the same for the anchors actually used when the venue is full.
	_clear_decor(vid)
	var filled: int = 0
	for did in _sellable():
		if DecorSystem.first_free_slot(vid) < 0:
			break
		GS.cash = BigNumber.from_parts(9.0, 12)
		GS.gems = 100000
		if DecorSystem.buy_decor(vid, did) or DecorSystem.grant_event_decor(did, vid):
			filled += 1
	_floor._props_key = ""
	_floor._rebuild_props()
	check(filled > 0, "the venue could be filled for the on-camera sweep (%d pieces)" % filled)
	var bad: Array = []
	for did in (_floor._decor_anchor_by_id as Dictionary).keys():
		var g: Vector2 = _floor._decor_anchor_by_id[did] as Vector2
		var p: Vector2 = Iso.to_screen(g)
		if p.x < EDGE_INSET or p.x > Iso.VIEW.x - EDGE_INSET:
			bad.append("%s@%.0f" % [str(did), p.x])
	check(bad.is_empty(),
		"every placed piece sits inside the horizontal clip (%s)"
			% ("all clear" if bad.is_empty() else ", ".join(bad)))
	check((_floor._decor_anchor_by_id as Dictionary).size() == filled,
		"all %d placed pieces got anchors (%d)"
			% [filled, (_floor._decor_anchor_by_id as Dictionary).size()])

## Flat and overhead pieces must not become obstacles, and solid ones must not be
## dropped onto a spot the cast is required to stand on.
func _check_navigation_clearance() -> void:
	var flat_blocking: Array = []
	for did in _sellable():
		var kind: String = _floor._decor_kind(did, str(DL.get_decor(did).get("slot_theme", "hall")))
		var blocks: bool = _floor._decor_blocks_nav(did, kind)
		if blocks and kind in ["rug", "patch", "banner", "hanging", "bunting"]:
			flat_blocking.append("%s(%s)" % [did, kind])
	check(flat_blocking.is_empty(),
		"nothing flat or overhead is treated as an obstacle (%s)"
			% ("all clear" if flat_blocking.is_empty() else ", ".join(flat_blocking)))

	# The venue is still full from the previous check. Rebuild navigation and
	# confirm the floor did not strand itself.
	_floor._props_key = ""
	_floor._rebuild_props()
	var solid: int = (_floor._prop_g as Array).size()
	check(solid > 0, "the full venue still registers solid props for navigation (%d)" % solid)

# --- the handoff's purchase integration assertion -----------------------------

## Buy one piece in the venue currently on screen and prove, WITHOUT reopening
## the venue, every consequence the handoff lists.
func _check_purchase_integration() -> void:
	print("-- purchase integration --")
	var vid: String = GS.current_venue
	_clear_decor(vid)
	GS.decor_owned = []
	_floor._props_key = ""
	_floor._rebuild_props()

	var target := "relic_case"
	var def: Dictionary = DL.get_decor(target)
	check(not def.is_empty(), "the piece under test exists")

	GS.cash = BigNumber.from_parts(1.0, 9)
	GS.gems = 100000

	var props_before: int = _decor_prop_count()
	var slot_before: int = DecorSystem.slots_used(vid)
	var points_before: float = DecorSystem.venue_decor_points(vid)
	var stars_before: float = float(EC.venue_satisfaction(vid)["stars"])
	var reveals_before: int = _count_reveal_nodes()

	var fired: Array = []
	var probe := func(v: String, d: String) -> void: fired.append([v, d])
	EB.decor_purchased.connect(probe)
	var bought: bool = DecorSystem.buy_decor(vid, target)
	EB.decor_purchased.disconnect(probe)

	check(bought, "the purchase succeeded")
	check(fired.size() == 1, "decor_purchased fired exactly once (%d)" % fired.size())

	# 1. the save slot changed
	var placed: Dictionary = GS.venue_state(vid).get("decor", {})
	check(DecorSystem.slots_used(vid) == slot_before + 1,
		"a save slot was taken (%d -> %d)" % [slot_before, DecorSystem.slots_used(vid)])
	check(DecorSystem.placed_slot(vid, target) >= 0,
		"the piece is recorded at slot %d" % DecorSystem.placed_slot(vid, target))
	check(placed.values().has(target), "the venue's decor dict names the piece")

	# 2. the floor gained the intended node, with the intended spec — and it did
	#    so from the signal alone, with nobody reopening the venue.
	check(_decor_prop_count() > props_before,
		"the live floor gained a prop (%d -> %d)" % [props_before, _decor_prop_count()])
	check((_floor._decor_anchor_by_id as Dictionary).has(target),
		"the floor recorded an anchor for the new piece")
	var kind: String = _floor._decor_kind(target, str(def.get("slot_theme", "hall")))
	check(kind == str((def.get("visual", {}) as Dictionary).get("kind", "")),
		"it drew with its authored painter ('%s')" % kind)
	var spec: Dictionary = _floor._decor_spec(target, kind, Vector2(4.0, 6.0), 0)
	check(Exhibits.footprint(spec) != Vector2.ZERO or spec.has("at"),
		"its spec resolves to a real footprint")

	# 3. it has an on-screen anchor
	var g: Vector2 = _floor._decor_anchor_by_id[target] as Vector2
	var p: Vector2 = Iso.to_screen(g)
	check(p.x >= EDGE_INSET and p.x <= Iso.VIEW.x - EDGE_INSET,
		"its anchor projects on screen (%.0f, %.0f)" % [p.x, p.y])

	# 4. the placement reveal ran, so the player can see WHICH prop is new
	check(_count_reveal_nodes() > reveals_before,
		"a placement reveal was spawned (%d -> %d)" % [reveals_before, _count_reveal_nodes()])

	# 5. satisfaction / decor points moved
	check(DecorSystem.venue_decor_points(vid) > points_before,
		"decor points rose (%.1f -> %.1f)" % [points_before, DecorSystem.venue_decor_points(vid)])
	check(float(EC.venue_satisfaction(vid)["stars"]) >= stars_before,
		"the venue rating did not regress")

	# 6. save/load restores it
	var snap: Dictionary = JSON.parse_string(JSON.stringify(GS.to_save_dict()))
	GS.from_save_dict(snap)
	check(DecorSystem.owned(vid, target), "the placement survived save/load")
	check(GS.owns_decor_design(target), "and so did the design")
	_floor._props_key = ""
	_floor._rebuild_props()
	check((_floor._decor_anchor_by_id as Dictionary).has(target),
		"and the floor rebuilds it from the loaded save")

## Reveal nodes are the only children of the canvas carrying a "u" progress meta.
func _count_reveal_nodes() -> int:
	var n: int = 0
	for c in (_floor._canvas as Node).get_children():
		if c.has_meta("u"):
			n += 1
	return n

## Fill EVERY venue to its slot cap and prove no piece is lost.
##
## Two failure modes, both of which shipped and both of which the player reports
## as "my decor isn't showing up":
##
##   · Two pieces handed the same anchor. One stands inside the other and is
##     invisible. The old code indexed a 3-or-4 entry derived list with
##     `slot % size`, so any venue with more than four slots stacked pieces —
##     and the late venues have up to twenty.
##   · A piece outside actual room floor, or unreachable by the real camera.
##     Large museums exceed the legacy base canvas and must be tested with pan.
##
## This runs across all twelve venues rather than the current one, because the
## late venues are exactly where both bugs were worst and where a venue author
## is most likely to add a bad anchor next.
func _check_every_venue_places_cleanly() -> void:
	var start_venue: String = GS.current_venue
	var total_dupes: int = 0
	var total_off: int = 0
	var checked: int = 0
	var worst: Array = []
	for vid_v in DL.venue_order():
		var vid: String = str(vid_v)
		GS.current_venue = vid
		GS.venues_unlocked = [vid]
		_floor.retheme(vid)
		GS.venue_state(vid)["decor"] = {}
		GS.decor_owned = []
		GS.cash = BigNumber.from_parts(9.0, 12)
		GS.gems = 1000000
		for did in _sellable():
			if not DecorSystem.buy_decor(vid, did):
				DecorSystem.grant_event_decor(did, vid)
		_floor._props_key = ""
		_floor._rebuild_props()

		var anchors: Dictionary = _floor._decor_anchor_by_id
		var seen: Dictionary = {}
		var dupes: int = 0
		var off: int = 0
		for did in anchors.keys():
			var g: Vector2 = anchors[did] as Vector2
			var key: String = "%.2f,%.2f" % [g.x, g.y]
			if seen.has(key):
				dupes += 1
			seen[key] = did
			EB.decor_focus_requested.emit(vid, did)
			var view: Vector2 = _floor._canvas.position + (Iso.to_screen(g) + Vector2(0, _floor._theme.lift_at(g))) * _floor._canvas.scale.x
			check(Rect2(Vector2(20, 70), _floor.size - Vector2(40, 100)).has_point(view), "%s/%s focus is visible on real viewport" % [vid, did])
			var spec: Dictionary = _floor._decor_spec_by_id[did]
			var at: Vector2 = spec.at
			var footprint := Exhibits.footprint(spec)
			if footprint == Vector2.ZERO:footprint = Vector2(0.9, 0.7)
			var rect := Rect2(at, footprint)
			var contained := false
			for room in _floor._theme.rooms:
				if (room.rect as Rect2).encloses(rect):contained = true
			if not contained:off += 1
			for fixed in _floor._theme.props + _floor._theme.exhibits:
				if str(fixed.get("kind", "")) in ["rug", "patch", "banner", "hanging", "bunting", "mural", "picture", "poster"]:continue
				var solid := Exhibits.solid_rect(fixed)
				if solid.size != Vector2.ZERO:
					check(not rect.intersects(solid), "%s/%s avoids %s" % [vid, did, fixed.get("kind", "")])
			for other in anchors.keys():
				if str(other) >= str(did):continue
				var other_spec: Dictionary = _floor._decor_spec_by_id[other]
				var other_size := Exhibits.footprint(other_spec)
				if other_size == Vector2.ZERO:other_size = Vector2(0.9, 0.7)
				check(not rect.intersects(Rect2(other_spec.at, other_size)), "%s/%s avoids %s" % [vid, did, other])
		if anchors.size() != DecorSystem.slots_used(vid):
			worst.append("%s anchored %d of %d placed" % [vid, anchors.size(), DecorSystem.slots_used(vid)])
		if dupes > 0 or off > 0:
			worst.append("%s dupes=%d off=%d" % [vid, dupes, off])
		total_dupes += dupes
		total_off += off
		checked += 1

	check(checked >= 12, "swept every venue (%d)" % checked)
	check(total_dupes == 0,
		"no two pieces share an anchor in any venue (%d clashes%s)"
			% [total_dupes, "" if worst.is_empty() else ": " + ", ".join(worst)])
	check(total_off == 0,
		"every placed footprint is inside actual room floor (%d outside)" % total_off)

	GS.current_venue = start_venue
	_floor.retheme(start_venue)
	GS.venues_unlocked = [start_venue]
	_clear_decor(start_venue)
	_floor._props_key = ""
	_floor._rebuild_props()
