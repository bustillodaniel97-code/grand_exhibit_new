extends SceneTree
## test_cart_separation.gd — already-overlapping carts must separate, never
## traverse. The runtime guard's first cut skipped any pair that was already
## intersecting, which let a step deepen or walk through the intersection.
## The guard now allows only steps that never deepen the overlap and end
## strictly farther apart.
##
## Three focused cases on real staged porters (whispering_pines):
##  1. ESCAPE: an overlapping pair given separating routes separates fully.
##     This must not regress into a wedge: both carts run the guard, so the
##     pair has to come apart.
##  2. NO TRAVERSAL: an overlapping pair driven into each other must not
##     deepen the overlap or swap sides, however long it is driven.
##  3. GUARD UNIT: cart_conflict rejects a deepening step and accepts a
##     separating one directly, so the predicate itself is pinned.
## Fails on the blanket-skip guard (case 2 traverses), passes on the
## separation-aware guard.

const Geometry := preload("res://scenes/venue/floor/cart_traffic_geometry.gd")

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

func _pen(a, b) -> float:
	return Geometry.penetration(a.pos, a.heading, b.pos, b.heading)

## Plant a porter at `pos` facing `heading` with one straight translation
## step to `to`. Route steps are the dispatch's step dictionaries, the same
## shape _porter_move and cart_clear/cart_conflict consume.
func _stage(p, pos: Vector2, heading: Vector2, to: Vector2) -> void:
	p.pos = pos
	p.heading = heading
	p.route_job = null
	p.route_retry = 0.0
	p.motion_step = {}
	p.route_cursor = 0
	p.route_steps = [{"at": to, "heading": heading, "turn": false, "reverse": false}]
	p.target = to
	p.dock = {"at": to, "heading": heading}
	p.staged = true

func run() -> void:
	if not OS.has_environment("GRAND_EXHIBIT_TEST_RUN"):
		printerr("REFUSED: requires GRAND_EXHIBIT_TEST_RUN isolation")
		quit(2)
		return
	root.get_node("SaveSystem").set_process(false)
	var gs = root.get_node("GameState")
	gs.reset_to_new_game()
	gs.ready_flag = true
	var floor_node = load("res://scenes/venue/floor/venue_floor.tscn").instantiate()
	root.add_child(floor_node)
	for n in root.get_children():
		n.process_mode = Node.PROCESS_MODE_DISABLED
	var vid := "whispering_pines"
	gs.current_venue = vid
	for dept in ["ticket", "archive", "gallery", "promotions"]:
		for track in ["staff", "speed", "value"]:
			gs.set_dept_level(vid, dept, track, 8)
	floor_node.retheme(vid)
	# Direct set_dept_level does not emit department_upgraded (the UI purchase
	# path does), and retheme early-returns when the theme is unchanged, so the
	# cast is refreshed explicitly here as the signal handler would.
	floor_node._cast_key = ""
	floor_node._refresh_cast()
	check(floor_node._porters.size() >= 2, "venue stages at least two couriers")
	if floor_node._porters.size() < 2:
		quit(1)
		return
	var a = floor_node._porters[0]
	var b = floor_node._porters[1]
	# Overlapping head-on pair on the store-room apron (same height, clear of
	# furniture). Bodies are ~0.88 long, so 0.40 apart is a real intersection.
	var a0 := Vector2(9.50, 1.50)
	var b0 := Vector2(9.90, 1.50)
	# 1. Escape: each pulls away from the other.
	_stage(a, a0, Vector2.RIGHT, Vector2(8.60, 1.50))
	_stage(b, b0, Vector2.LEFT, Vector2(10.80, 1.50))
	var start_pen := _pen(a, b)
	check(start_pen > 0.0, "fixture pair starts intersecting (depth=%.3f)" % start_pen)
	for i in 200:
		floor_node._porter_move(a, 0.05)
		floor_node._porter_move(b, 0.05)
	check(_pen(a, b) == 0.0, "separating pair reaches zero overlap (depth=%.3f)" % _pen(a, b))
	check(a.pos.distance_to(Vector2(8.60, 1.50)) < 0.02, "escaping cart reaches its own side")
	check(b.pos.distance_to(Vector2(10.80, 1.50)) < 0.02, "other escaping cart reaches its own side")
	# 2. No traversal: each is driven toward and past the other. Neither may
	# deepen the overlap or swap sides no matter how long it is driven.
	_stage(a, a0, Vector2.RIGHT, Vector2(10.60, 1.50))
	_stage(b, b0, Vector2.LEFT, Vector2(8.80, 1.50))
	var p0 := _pen(a, b)
	var deepest := p0
	var swapped := false
	for i in 400:
		floor_node._porter_move(a, 0.05)
		floor_node._porter_move(b, 0.05)
		deepest = maxf(deepest, _pen(a, b))
		if a.pos.x > b.pos.x:
			swapped = true
	check(p0 > 0.0, "adversarial fixture starts intersecting (depth=%.3f)" % p0)
	check(not swapped, "neither cart traverses through the other (no side swap)")
	check(deepest <= p0 + 0.0001, "overlap never deepens (start %.3f, deepest %.3f)" % [p0, deepest])
	# 3. Guard unit: the predicate itself.
	_stage(a, a0, Vector2.RIGHT, Vector2(10.60, 1.50))
	_stage(b, b0, Vector2.LEFT, Vector2(8.80, 1.50))
	var deepening := {"at": Vector2(9.70, 1.50), "heading": Vector2.RIGHT, "turn": false, "reverse": false}
	var separating := {"at": Vector2(9.30, 1.50), "heading": Vector2.RIGHT, "turn": false, "reverse": false}
	check(floor_node._crowd_traffic.cart_conflict(a, deepening), "guard rejects a deepening step")
	check(not floor_node._crowd_traffic.cart_conflict(a, separating), "guard accepts a separating step")
	# 4. Rotation while overlapping: a turn in place neither translates nor
	# approaches, so it must stay legal; and it must not move the cart.
	var turned := Vector2(0.0, 1.0)
	var turn_step := {"at": a.pos, "heading": turned, "turn": true, "reverse": false}
	check(not floor_node._crowd_traffic.cart_conflict(a, turn_step),
		"guard accepts an in-place turn while overlapping")
	var before_turn: Vector2 = a.pos
	a.route_steps = [turn_step]
	a.route_cursor = 0
	a.motion_step = {}
	for i in 40:
		floor_node._porter_move(a, 0.05)
	check(a.pos.distance_to(before_turn) < 0.0001,
		"in-place turn leaves the overlapping cart in place")
	check(a.heading.is_equal_approx(turned), "in-place turn completes its heading")
	print("CART_SEPARATION checks=", checks, " failures=", failures)
	quit(0 if failures == 0 else 1)
