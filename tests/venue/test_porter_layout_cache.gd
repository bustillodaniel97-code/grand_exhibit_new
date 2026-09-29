extends SceneTree
## test_porter_layout_cache.gd — fits-memoization correctness regression.
##
## porter_layout.fits() is memoized, but configure() progressively repopulates
## `claimed` via pick() while fitting later docks. A cache entry stored under
## few claims must never be served once more docks are claimed: the stale True
## lets pick() place two courier docks on the identical anchor and heading.
## This test configures whispering_pines at full staff and requires zero
## duplicate claims, a reset guard, and cached==uncached agreement on a pose
## sample. It fails while the configure bypass is inactive and passes after.

var failures := 0
var checks := 0

func check(ok: bool, label: String) -> void:
	checks += 1
	if ok:
		print("PASS ", label)
	else:
		failures += 1
		printerr("FAIL ", label)

func _initialize() -> void:
	call_deferred("run")

func _duplicate_claims(layout: RefCounted) -> Array:
	var dups: Array = []
	for i in layout.claimed.size():
		for j in range(i + 1, layout.claimed.size()):
			var a: Dictionary = layout.claimed[i]
			var b: Dictionary = layout.claimed[j]
			if (a.at as Vector2).is_equal_approx(b.at as Vector2) \
					and (a.heading as Vector2).is_equal_approx(b.heading as Vector2):
				dups.append([i, j])
	return dups

func run() -> void:
	if not OS.has_environment("GRAND_EXHIBIT_TEST_RUN"):
		printerr("REFUSED: requires GRAND_EXHIBIT_TEST_RUN isolation")
		quit(2)
		return
	root.get_node("SaveSystem").set_process(false)
	var gs = root.get_node("GameState")
	gs.reset_to_new_game()
	gs.ready_flag = true
	seed(1201)
	var floor_node = load("res://scenes/venue/floor/venue_floor.tscn").instantiate()
	floor_node.set_size(Vector2(720, 760))
	root.add_child(floor_node)
	for n in root.get_children():
		n.process_mode = Node.PROCESS_MODE_DISABLED
	var vid := "whispering_pines"
	gs.current_venue = vid
	for dept in ["ticket", "archive", "gallery", "promotions"]:
		for track in ["staff", "speed", "value"]:
			gs.set_dept_level(vid, dept, track, 8)
	floor_node.retheme(vid)
	var layout = floor_node._porter_layout
	check(not bool(layout._configuring), "configure guard resets after configure")
	var dups := _duplicate_claims(layout)
	check(dups.is_empty(), "no duplicate courier docks share anchor and heading (got %d)" % dups.size())
	# Every claim must clear every earlier claim under the fits claims rule,
	# mirroring _fits_uncached: BODY_GAP separation or segment clearance.
	var overlap := 0
	for i in layout.claimed.size():
		for j in range(i + 1, layout.claimed.size()):
			var a: Dictionary = layout.claimed[i]
			var b: Dictionary = layout.claimed[j]
			var pair := Geometry2D.get_closest_points_between_segments(
				a.at, (a.at as Vector2) + (a.heading as Vector2) * layout.LENGTH,
				b.at, (b.at as Vector2) + (b.heading as Vector2) * layout.LENGTH)
			if (a.at as Vector2).distance_to(b.at) < layout.BODY_GAP \
					or (pair[0] as Vector2).distance_to(pair[1]) < layout.HALF_WIDTH * 2.0 + 0.12:
				overlap += 1
	check(overlap == 0, "every dock clears all earlier docks (got %d overlaps)" % overlap)
	# Cached fits must agree with uncached evaluation on a pose sample across
	# the venue for both claims settings. A stale entry from progressive
	# configuration disagrees exactly here.
	var mismatches := 0
	var probed := 0
	var bounds: Rect2 = floor_node._theme.bounds
	var headings: Array[Vector2] = [Vector2.DOWN, Vector2.RIGHT, Vector2.UP, Vector2.LEFT]
	var gx := 0
	while bounds.position.x + gx * 1.0 <= bounds.end.x:
		var gz := 0
		while bounds.position.y + gz * 1.0 <= bounds.end.y:
			var at := Vector2(bounds.position.x + gx * 1.0, bounds.position.y + gz * 1.0)
			for h in headings:
				for claims_flag in [true, false]:
					probed += 1
					if bool(layout.fits(at, h, claims_flag)) != bool(layout._fits_uncached(at, h, claims_flag)):
						mismatches += 1
			gz += 1
		gx += 1
	check(probed > 100, "pose sample covers the venue (%d probes)" % probed)
	check(mismatches == 0, "cached fits agrees with uncached on %d probes (got %d mismatches)" % [probed, mismatches])
	print("PORTER_LAYOUT_CACHE checks=", checks, " failures=", failures)
	quit(0 if failures == 0 else 1)
