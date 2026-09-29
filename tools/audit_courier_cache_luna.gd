extends SceneTree
## Independent bounded check for fits-cache correctness during progressive claims.
func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var xdg := OS.get_environment("XDG_DATA_HOME")
	if OS.get_environment("GRAND_EXHIBIT_TEST_RUN") != "1" or not xdg.begins_with("/tmp/grand-courier-verify-luna"):
		printerr("AUDIT_REFUSED: use isolated /tmp/grand-courier-verify-luna* profile")
		quit(2)
		return
	root.get_node("SaveSystem").set_process(false)
	var gs = root.get_node("GameState")
	gs.reset_to_new_game()
	gs.ready_flag = true
	var f = load("res://scenes/venue/floor/venue_floor.tscn").instantiate()
	f.size = Vector2(720, 760)
	root.add_child(f)
	for n in root.get_children(): n.process_mode = Node.PROCESS_MODE_DISABLED
	gs.current_venue = "whispering_pines"
	for dept in ["ticket", "archive", "gallery", "promotions"]:
		for track in ["staff", "speed", "value"]: gs.set_dept_level(gs.current_venue, dept, track, 8)
	f.retheme(gs.current_venue)
	var l = f._porter_layout
	print("CACHE_GUARD configured_flag=", l._configuring, " cache_entries=", l._fit_cache.size(), " claims=", l.claimed.size())
	var collisions := _collisions(l)
	print("CACHED_LAYOUT collisions=", collisions, " cache_hits=", l._fit_hits, " misses=", l._fit_misses)
	# Same owner/theme/geometry; force the intended bypass to compare equivalent
	# configuration output without memoized fits.
	l._configuring = true
	l.configure(f)
	var uncached_collisions := _collisions(l)
	print("UNCACHED_LAYOUT collisions=", uncached_collisions, " cache_entries=", l._fit_cache.size())
	quit(0)

func _collisions(l: RefCounted) -> int:
	var collisions := 0
	for i in l.claimed.size():
		for j in range(i + 1, l.claimed.size()):
			var a: Dictionary = l.claimed[i]; var b: Dictionary = l.claimed[j]
			var pts = Geometry2D.get_closest_points_between_segments(a.at, a.at + a.heading * l.LENGTH, b.at, b.at + b.heading * l.LENGTH)
			if a.at.is_equal_approx(b.at) and a.heading.is_equal_approx(b.heading):
				collisions += 1
	return collisions
