extends SceneTree
## Cast suite: the crowd has to read as a crowd of people, not one person in
## fourteen shirts. Everything here is a contract that was broken at some point
## and cost a visible defect:
##   · variety must come from the SILHOUETTE, because a 20px head is all outline
##   · the palette axes must not collapse onto one RNG stream
##   · facial ink must sit on the face, with the eyes far enough apart to survive
##     being minified onto a phone
##   · the staff cap must not fuse with the eyes
##   · hair must fit inside the baked sprite, which crops silently
##   · the bake cache must stay inside a stated memory budget
## Run: godot --headless --path <repo> -s tests/venue/test_cast.gd  (exit 0 pass)

const Character := preload("res://scenes/venue/floor/character.gd")
const Baker := preload("res://scenes/venue/floor/character_baker.gd")

## Ceiling on resident baked textures. Visitor slots plus staff variants for the
## four departments, at 6 frames of RGBA8 each.
const BAKE_BUDGET_MIB := 11.0
## The floor's peak simultaneous population. Fewer look slots than this and the
## same person is guaranteed to appear twice at once.
const PEAK_POPULATION := 20

var _fail: int = 0
var _frames: int = 0
var _t: float = 0.0
var _floor: Control
var _done: bool = false

func check(cond: bool, msg: String) -> void:
	if cond:
		print("PASS: ", msg)
	else:
		_fail += 1
		printerr("FAIL: ", msg)

func _initialize() -> void:
	_check_look_table()
	_check_seed_spread()
	_check_silhouettes()
	_check_sprite_fit()
	_check_face()
	_check_staff()
	_check_bake_budget()
	_boot_floor()

# --- look table ---------------------------------------------------------------

func _check_look_table() -> void:
	check(Character.LOOK_COUNT > PEAK_POPULATION,
		"LOOK_COUNT %d exceeds peak population %d" % [Character.LOOK_COUNT, PEAK_POPULATION])
	var styles := {}
	var pairs := {}
	var used := {"skin": {}, "hair": {}, "shirt": {}, "pants": {}, "build": {}}
	for slot in Character.LOOK_COUNT:
		var lk: Dictionary = Character.look_for_slot(slot)
		var st: int = int(lk["hair_style"])
		styles[st] = int(styles.get(st, 0)) + 1
		pairs["%d/%s" % [st, lk["build"]]] = true
		for axis in used.keys():
			(used[axis] as Dictionary)[lk[axis]] = true
	check(styles.size() == Character.HAIR_STYLES,
		"every hair style appears in the look table (%d of %d)" % [
			styles.size(), Character.HAIR_STYLES])
	var worst: int = 0
	for n in styles.values():
		worst = maxi(worst, int(n))
	check(float(worst) / float(Character.LOOK_COUNT) <= 0.25,
		"no hair style holds more than 25%% of the table (worst %d/%d)" % [
			worst, Character.LOOK_COUNT])
	check(pairs.size() == Character.LOOK_COUNT,
		"every slot is a distinct (style, build) pair (%d of %d)" % [
			pairs.size(), Character.LOOK_COUNT])
	# The old table ran all axes off `seed = slot * 7919`, which left one hair
	# colour and one skin tone never selected at all.
	check((used["skin"] as Dictionary).size() == Character.SKIN_TONES.size(),
		"every skin tone is used (%d of %d)" % [
			(used["skin"] as Dictionary).size(), Character.SKIN_TONES.size()])
	check((used["hair"] as Dictionary).size() == Character.HAIR_COLORS.size(),
		"every hair colour is used (%d of %d)" % [
			(used["hair"] as Dictionary).size(), Character.HAIR_COLORS.size()])
	check((used["shirt"] as Dictionary).size() == Character.SHIRT_COLORS.size(),
		"every shirt colour is used (%d of %d)" % [
			(used["shirt"] as Dictionary).size(), Character.SHIRT_COLORS.size()])
	check((used["pants"] as Dictionary).size() == Character.PANTS_COLORS.size(),
		"every trouser colour is used")
	check((used["build"] as Dictionary).size() == Character.BUILDS.size(),
		"every build is used (%d of %d)" % [
			(used["build"] as Dictionary).size(), Character.BUILDS.size()])

## randomize_look is what the floor actually calls, so the spread that matters is
## the one measured through it rather than over the raw table.
func _check_seed_spread() -> void:
	var styles := {}
	var slots := {}
	var probe: Node2D = Character.new()
	for i in 900:
		probe.randomize_look(i * 2654435761)
		var lk: Dictionary = probe.current_look()
		styles[lk["hair_style"]] = int(styles.get(lk["hair_style"], 0)) + 1
		slots[probe.look_key()] = true
	probe.free()
	check(slots.size() == Character.LOOK_COUNT,
		"random seeds reach every look slot (%d of %d)" % [slots.size(), Character.LOOK_COUNT])
	var worst: int = 0
	for n in styles.values():
		worst = maxi(worst, int(n))
	check(float(worst) / 900.0 <= 0.25,
		"no hair style exceeds 25%% of 900 random draws (worst %.1f%%)" % [
			float(worst) / 9.0])

# --- geometry -----------------------------------------------------------------

## What a player resolves on a phone is the outline. Styles that only differ in
## hue are one haircut, which is exactly how four styles read as "all the same".
func _check_silhouettes() -> void:
	var cap: float = Character.HEAD_R + 0.8
	var proud: int = 0
	for s in Character.HAIR_STYLES:
		if Character.hair_reach(s) >= cap + 3.0:
			proud += 1
	check(proud >= 5, "at least 5 hair styles push the outline 3px past the skull cap (%d)" % proud)

## Hair that overruns the baked sprite is cropped silently — no error, just a
## flat-topped head on the floor.
func _check_sprite_fit() -> void:
	var lift: float = absf(Character.HEAD_Y) * (1.0 + Character.SQUASH_AMP * 0.5) \
		+ Character.BOB_AMP * 0.8
	var k: float = 1.0 + (Character.BUILDS[Character.BUILDS.size() - 1] - 1.0) * 0.45
	var head_room: float = float(Baker.ANCHOR.y) / float(Baker.STORE)
	var half_w: float = float(Baker.DESIGN.x) * 0.5
	var worst_top: float = 0.0
	var worst_side: float = 0.0
	for s in Character.HAIR_STYLES:
		var bb: Rect2 = Character.hair_bounds(s)
		worst_top = maxf(worst_top,
			lift + absf(bb.position.y) * k + Character.OUTLINE_W * 0.5)
		worst_side = maxf(worst_side,
			maxf(absf(bb.position.x), bb.end.x) * k + Character.OUTLINE_W * 0.5)
	check(worst_top <= head_room,
		"tallest hair fits above the sprite anchor (%.2f of %.2f design px)" % [
			worst_top, head_room])
	check(worst_side <= half_w,
		"widest hair fits inside the sprite (%.2f of %.2f design px)" % [worst_side, half_w])

func _check_face() -> void:
	var gap: float = 2.0 * Character.EYE_DX - 2.0 * Character.EYE_R.x
	# The old eyes were 1.2 design px apart, which lands under one screen texel
	# once the sprite is minified, so they fused into a single dark blob.
	check(gap >= 2.5, "eyes are at least 2.5 design px apart edge to edge (%.2f)" % gap)
	var fe: Vector2 = Character.face_extent()
	var centre: float = (fe.x + fe.y) * 0.5
	check(absf(centre) <= Character.HEAD_R * 0.25,
		"facial ink is centred on the skull, not piled into one half (centre %.2f)" % centre)
	check(maxf(absf(fe.x), fe.y) <= Character.HEAD_R - 2.0,
		"facial ink stays clear of the head silhouette (reach %.2f of %.2f)" % [
			maxf(absf(fe.x), fe.y), Character.HEAD_R - 2.0])

func _check_staff() -> void:
	var eye_top: float = -0.8 - Character.EYE_R.y
	var clearance: float = eye_top - Character.CAP_PEAK_Y.y
	# The peak used to end exactly on the eye tops; both were near-black, so they
	# fused into one bar and every staff member wore wraparound sunglasses.
	check(clearance >= 2.0,
		"staff cap peak clears the eyes by at least 2 design px (%.2f)" % clearance)
	check(Character.CAP_PEAK_X.y <= Character.HEAD_R + 1.0,
		"staff cap peak stays inside the cap crown (%.2f of %.2f)" % [
			Character.CAP_PEAK_X.y, Character.HEAD_R + 1.0])
	var keys := {}
	var looks := {}
	for v in Character.STAFF_LOOK_COUNT:
		var c: Node2D = Character.new()
		c.set_uniform(Color("#C4703F"), v)
		keys[c.look_key()] = true
		var lk: Dictionary = c.current_look()
		looks["%s/%s/%s/%s" % [lk["skin"], lk["hair"], lk["hair_style"], lk["build"]]] = true
		c.free()
	check(keys.size() == Character.STAFF_LOOK_COUNT,
		"staff variants get distinct bake keys (%d of %d)" % [
			keys.size(), Character.STAFF_LOOK_COUNT])
	check(looks.size() == Character.STAFF_LOOK_COUNT,
		"staff variants differ in more than the bake key (%d distinct)" % looks.size())

func _check_bake_budget() -> void:
	var per_look: int = int(Baker.SPRITE.x) * int(Baker.SPRITE.y) * 4 * int(Baker.FRAMES)
	var slots: int = Character.LOOK_COUNT + 4 * Character.STAFF_LOOK_COUNT
	var mib: float = float(per_look * slots) / 1048576.0
	check(mib <= BAKE_BUDGET_MIB,
		"bake cache ceiling %.2f MiB is inside the %.1f MiB budget (%d slots)" % [
			mib, BAKE_BUDGET_MIB, slots])

# --- live floor ---------------------------------------------------------------

func _boot_floor() -> void:
	# The floor picks looks with the global randi(). Pinning the seed keeps the
	# census reproducible: how many visitors have spawned by the census still
	# varies with frame timing, but they are always a prefix of the same sequence,
	# so this suite cannot fail on an unlucky draw.
	seed(20260725)
	var autoloads := [
		["EventBus", "res://autoload/event_bus.gd"],
		["DataLoader", "res://autoload/data_loader.gd"],
		["ClockGuard", "res://autoload/clock_guard.gd"],
		["Analytics", "res://autoload/analytics.gd"],
		["AdService", "res://autoload/ad_service.gd"],
		["IAPService", "res://autoload/iap_service.gd"],
		["GameState", "res://autoload/game_state.gd"],
		["SaveSystem", "res://autoload/save_system.gd"],
		["Economy", "res://autoload/economy.gd"],
	]
	for pair in autoloads:
		if root.has_node(pair[0]):
			continue
		var n: Node = (load(pair[1]) as GDScript).new()
		n.name = pair[0]
		root.add_child(n)
	# Doctoring GameState with SaveSystem's autosave running writes the doctored
	# values into the player's real save, which is how the battery went red once.
	var ss: Node = root.get_node("SaveSystem")
	ss.set_process(false)
	ss.autosave_interval_sec = 1 << 30

	var gs: Node = root.get_node("GameState")
	root.get_node("DataLoader").reload_all()
	gs.reset_to_new_game()
	# A new-game floor holds five or six visitors, which is too thin to see a
	# crowd repeat itself. Upgraded departments pull the population up to where
	# the defect was originally measured.
	for dept in ["ticket", "archive", "promotions", "gallery"]:
		for track in ["staff", "speed", "value"]:
			gs.set_dept_level(gs.current_venue, dept, track, 10)
	gs.ready_flag = true

	_floor = (load("res://scenes/venue/floor/venue_floor.tscn") as PackedScene).instantiate()
	_floor.set_size(Vector2(720, 760))
	root.add_child(_floor)
	_floor.time_scale = 8.0

func _process(delta: float) -> bool:
	if _done:
		return true
	_frames += 1
	if _frames < 3:
		return false
	_t += delta
	_floor.set_rates(root.get_node("Economy").venue_rates(
		root.get_node("GameState").current_venue))
	if _t < 6.0:
		return false
	_done = true
	_check_crowd()
	print("---")
	if _fail == 0:
		print("ALL CAST CHECKS PASSED")
	quit(0 if _fail == 0 else 1)
	return true

func _check_crowd() -> void:
	var keys: PackedStringArray = _floor.cast_look_keys()
	var alive: int = keys.size()
	check(alive >= 4, "floor populated for the census (%d visitors)" % alive)
	if alive < 4:
		return
	var seen := {}
	var worst: int = 0
	for k in keys:
		seen[k] = int(seen.get(k, 0)) + 1
		worst = maxi(worst, int(seen[k]))
	# Measured before this pass: 15 visitors, 9 distinct looks, one look worn by
	# three people at once. The floor deals the rarest look slot, so up to
	# LOOK_COUNT people on screen must all be different.
	#
	# Above LOOK_COUNT the "all of them, right now" form is not satisfiable and
	# never was — it only became reachable when visitors started resting, which
	# raised the concurrent population past 24. The dealer fills vacant slots
	# first, so every slot is refilled on the next spawn; but between a visitor
	# leaving and that spawn there is an instant where the look it was wearing is
	# on nobody, and this census samples instants. One vacancy is that, not a
	# regression. Two would mean the dealer had stopped preferring empty slots.
	#
	# Below LOOK_COUNT the guarantee is absolute and stays asserted exactly.
	var want: int = mini(alive, Character.LOOK_COUNT)
	var floor_ok: int = want if alive <= Character.LOOK_COUNT else want - 1
	check(seen.size() >= floor_ok,
		"crowd of %d shows %d distinct looks (%d required)" % [alive, seen.size(), floor_ok])
	var ceiling: int = int(ceil(float(alive) / float(Character.LOOK_COUNT)))
	check(worst <= ceiling,
		"no look is worn by more than %d visitors at once (worst %d)" % [ceiling, worst])
	var staff: PackedStringArray = _floor.cast_look_keys(true)
	var staff_seen := {}
	for k in staff:
		staff_seen[k] = true
	check(staff_seen.size() > seen.size(),
		"staff add looks of their own on top of the visitor crowd (%d total)" % staff_seen.size())
