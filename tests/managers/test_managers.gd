extends SceneTree
## tests/managers/test_managers.gd — manager system rules (SPEC §5, §12).
## Run: godot --headless --path . -s tests/managers/test_managers.gd ; exit 0 = pass.

## NOTE on bootstrap: under `-s` this entry script compiles BEFORE autoload globals
## resolve, so it must not reference them by name. By the time run() executes the
## autoloads are live root children — fetch them via root.get_node() and only then
## load() scripts that reference autoload names (a const preload would compile too
## early and fail). Do NOT add duplicate nodes: that shadows the real singletons.
const MS_PATH := "res://scripts/managers/manager_system.gd"
const BADGE_PATH := "res://scenes/managers/manager_badge.gd"
const PORTRAIT_PATH := "res://scenes/managers/manager_portrait.gd"
const BAKER_PATH := "res://scenes/managers/portrait_baker.gd"
const CHARACTER_PATH := "res://scenes/venue/floor/character.gd"
const UI_PATH := "res://scripts/ui/ui_kit.gd"

## A badge bio has to fit two wrapped lines of TYPE_CAPTION in the ~490px the
## card gives it. Past this the card grows a third line and the roster stops
## being one repeating height.
const BIO_MAX_CHARS := 90
## Smallest text/background ratio the badge's pills are allowed to run at.
const MIN_CONTRAST := 4.5

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
	var eb: Node = root.get_node("EventBus")
	var eco: Node = root.get_node("Economy")
	var ManagerSystem: GDScript = load(MS_PATH)
	gs.reset_to_new_game()

	# --- roster sanity ---------------------------------------------------------
	check(root.get_node("DataLoader").managers.size() == 14, "roster has 14 managers")
	var by_rarity := {"common": 0, "rare": 0, "epic": 0, "legendary": 0}
	for mid in root.get_node("DataLoader").managers.keys():
		by_rarity[root.get_node("DataLoader").managers[mid]["rarity"]] += 1
	check(by_rarity["common"] == 4 and by_rarity["rare"] == 4
		and by_rarity["epic"] == 4 and by_rarity["legendary"] == 2, "rarity split 4/4/4/2")
	check(ManagerSystem.exchange_ratio() == 5, "exchange_ratio = 5 from data")

	# --- level-up cost curve + cap ----------------------------------------------
	ManagerSystem.add_cards("docent_poppy", 1)  # common: base 10, growth 1.12, cap 50
	check(ManagerSystem.owned("docent_poppy"), "owned = cards >= 1")
	check(not ManagerSystem.owned("barker_theo"), "unowned at 0 cards")
	gs.add_insight(BigNumber.from_float(100000.0))
	var c1: float = ManagerSystem.level_up_cost("docent_poppy").to_float_approx()
	check(absf(c1 - 10.0) < 0.001, "level 1->2 cost = base 10")
	var leveled_signal := {"fired": false, "level": 0}
	eb.manager_leveled.connect(func(_id: String, lvl: int) -> void:
		leveled_signal["fired"] = true
		leveled_signal["level"] = lvl)
	check(ManagerSystem.level_up("docent_poppy"), "level_up succeeds")
	check(ManagerSystem.level("docent_poppy") == 2, "level incremented to 2")
	check(leveled_signal["fired"] and leveled_signal["level"] == 2, "manager_leveled emitted")
	var c2: float = ManagerSystem.level_up_cost("docent_poppy").to_float_approx()
	check(absf(c2 - 11.2) < 0.001, "level 2->3 cost = 10 * 1.12")
	check(ManagerSystem.level_up("docent_poppy"), "second level_up succeeds")
	ManagerSystem.state("docent_poppy")["level"] = 50  # cap
	check(not ManagerSystem.can_level_up("docent_poppy"), "capped at level_cap 50")
	check(not ManagerSystem.level_up("docent_poppy"), "level_up refused at cap")
	ManagerSystem.state("docent_poppy")["level"] = 2
	gs.insight = BigNumber.zero()
	check(not ManagerSystem.level_up("docent_poppy"), "level_up refused when insight short")
	gs.add_insight(BigNumber.from_float(100000.0))

	# --- rank-up duplicate spend + keep-1 ---------------------------------------
	ManagerSystem.add_cards("paleontologist_rex", 3)  # rare, dup_costs [2,4,8]
	var ranked_signal := {"fired": false, "rank": 0}
	eb.manager_ranked_up.connect(func(_id: String, r: int) -> void:
		ranked_signal["fired"] = true
		ranked_signal["rank"] = r)
	check(ManagerSystem.rank_up("paleontologist_rex"), "rank_up to 2 with 3 cards (cost 2, keep 1)")
	check(ManagerSystem.cards("paleontologist_rex") == 1, "cards 3 -> 1 after rank-up")
	check(ManagerSystem.rank("paleontologist_rex") == 2, "rank is 2")
	check(ranked_signal["fired"] and ranked_signal["rank"] == 2, "manager_ranked_up emitted")
	check(not ManagerSystem.rank_up("paleontologist_rex"), "rank-up refused: 1 card < cost 4 + keep 1")
	ManagerSystem.add_cards("paleontologist_rex", 4)  # now 5 cards
	check(ManagerSystem.rank_up("paleontologist_rex"), "rank_up to 3 (cost 4, keeps 1)")
	check(ManagerSystem.cards("paleontologist_rex") == 1 and ManagerSystem.rank("paleontologist_rex") == 3,
		"cards 5 -> 1, rank 3")
	ManagerSystem.state("paleontologist_rex")["rank"] = 10
	check(ManagerSystem.rank_up_cost("paleontologist_rex") == 0, "rank 10 is max")
	check(not ManagerSystem.rank_up("paleontologist_rex"), "rank_up refused at max rank")

	# --- assign: specialty rule + one-per-dept -----------------------------------
	check(not ManagerSystem.assign("docent_poppy", "gallery"), "assign wrong specialty refused")
	check(not ManagerSystem.assign("barker_theo", "promotions"), "assign unowned refused")
	check(ManagerSystem.assign("docent_poppy", "ticket"), "assign to specialty dept works")
	check(ManagerSystem.assigned_to("docent_poppy") == "ticket", "assigned_to stored in state")
	ManagerSystem.add_cards("usher_bram", 1)  # also ticket specialty
	check(not ManagerSystem.assign("usher_bram", "ticket"), "one manager per dept enforced")
	gs.reputation_xp = BigNumber.from_float(5000.0)
	check(ManagerSystem.assignment_slots("ticket") >= 2,
		"Reputation opens a second manager post")
	check(ManagerSystem.assign("usher_bram", "ticket"),
		"second specialist can fill the Reputation-unlocked post")
	check(ManagerSystem.assigned_ids("ticket").size() == 2,
		"department retains both assigned managers")
	check(ManagerSystem.unassign("usher_bram"), "second post can stand down")
	check(ManagerSystem.unassign("docent_poppy"), "unassign works")
	check(ManagerSystem.assign("usher_bram", "ticket"), "dept free after unassign")

	# --- economy multiplier hook --------------------------------------------------
	var before: float = eco.manager_multiplier_for("gallery")
	ManagerSystem.add_cards("night_curator", 1)  # legendary, gallery, base_mult 0.10
	check(ManagerSystem.assign("night_curator", "gallery"), "assign legendary to gallery")
	var after: float = eco.manager_multiplier_for("gallery")
	check(after > before, "Economy.manager_multiplier_for(gallery) increases after assign (%f -> %f)" % [before, after])
	check(absf(after - 1.10) < 0.0001, "gallery mult = 1 + 0.10 * lvl1 * rank1")
	ManagerSystem.state("night_curator")["level"] = 10
	check(absf(eco.manager_multiplier_for("gallery") - 2.0) < 0.0001, "gallery mult scales with level")

	# --- exchange 5:1 same-rarity + keep-1 ----------------------------------------
	ManagerSystem.add_cards("barker_theo", 6)  # common promotions
	var ex_signal := {"fired": false}
	eb.manager_exchanged.connect(func(_f: String, _t: String, spent: int, gained: int) -> void:
		ex_signal["fired"] = spent == 5 and gained == 1)
	check(ManagerSystem.exchange("barker_theo", "archivist_mabel"), "exchange 5:1 same rarity")
	check(ManagerSystem.cards("barker_theo") == 1, "from keeps exactly 1 card")
	check(ManagerSystem.cards("archivist_mabel") == 1, "to gains 1 card")
	check(ex_signal["fired"], "manager_exchanged emitted (5 spent, 1 gained)")
	check(not ManagerSystem.exchange("barker_theo", "storyteller_june"), "keep-1 rule blocks 1-card trade")
	check(not ManagerSystem.exchange("barker_theo", "paleontologist_rex"), "cross-rarity exchange refused")
	check(not ManagerSystem.exchange("barker_theo", "barker_theo"), "self-exchange refused")

	# --- battle attack formula (SPEC §6) -------------------------------------------
	var nc_def: Dictionary = ManagerSystem.manager_def("night_curator")
	var atk1: float = ManagerSystem.battle_attack(nc_def, {"level": 1, "rank": 1})
	check(absf(atk1 - 150.0) < 0.001, "battle_attack lvl1 rank1 = 150")
	var atk2: float = ManagerSystem.battle_attack(nc_def, {"level": 11, "rank": 3})
	check(absf(atk2 - 150.0 * 2.2 * 1.7) < 0.01,
		"battle_attack uses the ten-rank audit ladder")

	_check_badge_data()
	_check_portrait_looks()
	_check_badge_contrast()
	_check_portrait_crop()
	await _check_badge_layout()

	print("DONE failures=", _failures)
	quit(0 if _failures == 0 else 1)

# --------------------------------------------------------------- ID badges

## The badge renders five data fields per manager. Any one of them missing is a
## hole in a card the player sees fourteen of, so the roster is checked whole
## rather than sampled.
func _check_badge_data() -> void:
	var DL: Node = root.get_node("DataLoader")
	var missing_post: Array = []
	var bad_traits: Array = []
	var long_bio: Array = []
	for mid in DL.managers.keys():
		var def: Dictionary = DL.managers[mid]
		if str(def.get("post", "")).strip_edges() == "":
			missing_post.append(mid)
		var traits: Array = def.get("traits", [])
		if traits.size() < 2:
			bad_traits.append(mid)
		else:
			for t in traits:
				if typeof(t) != TYPE_STRING or str(t).strip_edges() == "":
					bad_traits.append(mid)
		var bio: String = str(def.get("flavor", "")).strip_edges()
		if bio == "" or bio.length() > BIO_MAX_CHARS:
			long_bio.append("%s(%d)" % [mid, bio.length()])
	check(missing_post.is_empty(), "every manager has a `post` %s" % [missing_post])
	check(bad_traits.is_empty(), "every manager has >=2 non-empty traits %s" % [bad_traits])
	check(long_bio.is_empty(),
		"every bio is non-empty and <=%d chars %s" % [BIO_MAX_CHARS, long_bio])

## The portrait look must resolve into the cast's own palettes, wear the
## department uniform, and be different for every manager — fourteen identical
## faces is exactly the failure the badges replaced.
func _check_portrait_looks() -> void:
	var DL: Node = root.get_node("DataLoader")
	var Portrait: GDScript = load(PORTRAIT_PATH)
	var Character: GDScript = load(CHARACTER_PATH)
	var UI: GDScript = load(UI_PATH)
	var seen := {}
	var wrong_uniform: Array = []
	var off_palette: Array = []
	var not_staff: Array = []
	for mid in DL.managers.keys():
		var def: Dictionary = DL.managers[mid]
		var look: Dictionary = Portrait.look_for(def)
		var dept: Color = UI.DEPT_COLORS.get(str(def.get("specialty", "")), UI.LOCKED)
		if look["uniform"] != dept or look["shirt"] != dept:
			wrong_uniform.append(mid)
		if not bool(look["is_staff"]):
			not_staff.append(mid)
		if not (look["skin"] in Character.SKIN_TONES) or not (look["hair"] in Character.HAIR_COLORS):
			off_palette.append(mid)
		if int(look["hair_style"]) < 0 or int(look["hair_style"]) >= Character.HAIR_STYLES:
			off_palette.append(mid)
		if not (look["build"] in Character.BUILDS):
			off_palette.append(mid)
		var key := "%s|%s|%d|%f" % [look["skin"], look["hair"],
			int(look["hair_style"]), float(look["build"])]
		seen[key] = str(seen.get(key, "")) + mid + " "
	check(wrong_uniform.is_empty(), "every portrait wears its department uniform %s" % [wrong_uniform])
	check(not_staff.is_empty(), "every portrait is drawn as staff %s" % [not_staff])
	check(off_palette.is_empty(), "every look resolves inside the cast palettes %s" % [off_palette])
	var collisions: Array = []
	for k in seen.keys():
		if str(seen[k]).split(" ", false).size() > 1:
			collisions.append(seen[k])
	check(collisions.is_empty() and seen.size() == DL.managers.size(),
		"all %d portrait looks are distinct %s" % [DL.managers.size(), collisions])
	var keys := {}
	for mid in DL.managers.keys():
		keys[Portrait.portrait_key(DL.managers[mid])] = true
	check(keys.size() == DL.managers.size(), "one bake-cache key per manager")

## Rarity and department pills are solid colour with text on top. The kit's two
## body inks each fail on part of that palette, so the badge picks per colour —
## this proves the pick actually clears the legibility floor everywhere.
func _check_badge_contrast() -> void:
	var Badge: GDScript = load(BADGE_PATH)
	var UI: GDScript = load(UI_PATH)
	var worst := 99.0
	var worst_name := ""
	var tints := {}
	for k in UI.RARITY_COLORS.keys():
		tints["rarity/" + str(k)] = UI.RARITY_COLORS[k]
	for k in UI.DEPT_COLORS.keys():
		tints["dept/" + str(k)] = UI.DEPT_COLORS[k]
	tints["new"] = UI.ACCENT
	var hue_drift := 0.0
	for name in tints.keys():
		var tint: Color = tints[name]
		var fill: Color = Badge.legible_fill(tint)
		var c: float = Badge.contrast(Badge.ink_on(fill), fill)
		if c < worst:
			worst = c
			worst_name = str(name)
		hue_drift = maxf(hue_drift, absf(fill.h - tint.h))
	check(worst >= MIN_CONTRAST,
		"every badge pill clears %.1f:1 (worst %s at %.2f:1)" % [MIN_CONTRAST, worst_name, worst])
	check(hue_drift < 0.01, "deepening a pill never moves its hue (max drift %.4f)" % hue_drift)
	# Sanity that the helper is measuring, not returning a constant.
	check(Badge.contrast(Color.WHITE, Color.BLACK) > 20.0
		and Badge.contrast(Color.WHITE, Color.WHITE) < 1.01, "contrast() spans the real range")

## The portrait crop is a fixed window in character-local design px. If someone
## adds a taller hair style or a wider build, hair that overruns the window is
## silently guillotined — a defect nobody would see in a diff.
func _check_portrait_crop() -> void:
	var DL: Node = root.get_node("DataLoader")
	var Portrait: GDScript = load(PORTRAIT_PATH)
	var Character: GDScript = load(CHARACTER_PATH)
	var Baker: GDScript = load(BAKER_PATH)
	var crop: Rect2 = Baker.CROP
	var clipped: Array = []
	for mid in DL.managers.keys():
		var look: Dictionary = Portrait.look_for(DL.managers[mid])
		var build: float = float(look["build"])
		var r: float = Character.HEAD_R * (1.0 + (build - 1.0) * 0.45)
		var k: float = r / Character.HEAD_R
		var hair: Rect2 = Character.hair_bounds(int(look["hair_style"]))
		# Hair, plus the staff cap (crown crescent at r+1.0, lifted 1.6px) and
		# half an outline stroke on top of whichever reaches furthest.
		var pad: float = Character.OUTLINE_W * 0.5
		var top: float = Character.HEAD_Y + minf(hair.position.y * k, -1.6 - (r + 1.0)) - pad
		var side: float = maxf(absf(hair.position.x), absf(hair.end.x)) * k + pad
		# The near arm sits outside the torso and is the widest thing in frame.
		side = maxf(side, 8.3 * build + 1.2 + 2.5 + pad)
		if top < crop.position.y or side > crop.end.x or -side < crop.position.x:
			clipped.append("%s(top %.1f, side %.1f)" % [mid, top, side])
	check(clipped.is_empty(), "no badge photo clips its subject %s" % [clipped])
	# The window must cut the chest: above the shoulder line it is a floating
	# head, below the torso it is a full-body shot in a 112px square.
	check(crop.end.y > -25.0 and crop.end.y < -8.0,
		"crop bottom cuts the chest (%.1f)" % crop.end.y)
	check(Baker.TEX == Baker.SIZE * Baker.STORE and Baker.RENDER == Baker.TEX * Baker.SUPERSAMPLE,
		"portrait render chain is SIZE x STORE x SUPERSAMPLE")
	# The suites run without a rendering context. A bake attempted there would
	# either stall on a frame that never draws or cache a transparent read-back,
	# so the request has to be refused outright and the badge left holding its
	# placeholder — which is exactly what these tests then measure.
	var probe := Control.new()
	root.add_child(probe)
	Baker.request("test_headless_probe", Portrait.look_for(DL.managers.values()[0]), probe)
	check(not Baker.is_baked("test_headless_probe"), "headless never caches a portrait")
	probe.free()

## The whole badge is the tap target. The roster's previous rows were
## PanelContainers with a gui_input handler: a real Button that covers the card
## is what makes the tap land and show.
func _check_badge_layout() -> void:
	var DL: Node = root.get_node("DataLoader")
	var Badge: GDScript = load(BADGE_PATH)
	var UI: GDScript = load(UI_PATH)
	var host := Control.new()
	host.custom_minimum_size = Vector2(648, 1200)
	host.size = Vector2(648, 1200)
	root.add_child(host)
	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_FULL_RECT)
	host.add_child(box)
	var mid: String = str(DL.managers.keys()[0])
	var badge: Control = Badge.new()
	box.add_child(badge)
	badge.setup(mid, DL.managers[mid], {"level": 7, "rank": 2}, true, true)
	box.queue_sort()
	await process_frame
	await process_frame
	var tapped := {"id": ""}
	badge.tapped.connect(func(v: String) -> void: tapped["id"] = v)
	var hit: Button = null
	for c in badge.get_children():
		if c is Button:
			hit = c
	check(hit != null, "badge carries a real Button as its tap target")
	check(badge.size.y >= float(UI.TOUCH_MIN),
		"badge is at least one touch target tall (%.0f >= %d)" % [badge.size.y, UI.TOUCH_MIN])
	if hit != null:
		# The target must fill the card's whole content rect, not sit in it as a
		# chip. Measured against the stylebox rather than as a percentage: the two
		# engines lay this text out at slightly different heights, and a
		# percentage threshold turns that into a flaky assertion.
		var box_style: StyleBox = badge.get_theme_stylebox("panel")
		var want := badge.size - Vector2(
			box_style.get_margin(SIDE_LEFT) + box_style.get_margin(SIDE_RIGHT),
			box_style.get_margin(SIDE_TOP) + box_style.get_margin(SIDE_BOTTOM))
		check(hit.size.distance_to(want) < 1.0,
			"tap target fills the card's content rect (%s vs %s)" % [hit.size, want])
		var cover: float = (hit.size.x * hit.size.y) / maxf(badge.size.x * badge.size.y, 1.0)
		check(cover > 0.70, "tap target covers %.0f%% of the badge" % (cover * 100.0))
		hit.emit_signal("pressed")
		check(tapped["id"] == mid, "pressing the badge emits tapped(manager_id)")
	host.free()
