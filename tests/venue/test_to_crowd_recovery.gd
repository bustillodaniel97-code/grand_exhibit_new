extends SceneTree
## test_to_crowd_recovery.gd — cart-blocked crowd admission must recover.
##
## Evidence: a scale-4 soak held a grand_river visitor in to_crowd for ~45
## sim-minutes 0.3 tiles from its slot (pos 14.46,14.71, target 14.0,14.45,
## one path point left). Short indoor hops skip nav routing, visitors never
## block each other, and only a parked porter cart on the slot explains a
## permanent stop: direct steps fail visitor_clear every tick while detours
## cannot rejoin a covered target. Pre-fix, to_crowd has no timeout (unlike
## rest, which gives up after REST_TRAVEL_LIMIT), so the stall is forever.
## This test parks a staged porter on an assigned crowd slot and requires
## the guest to reach the crowd (via a re-held clear slot) instead of
## waiting out the run. Fails pre-fix, passes post-fix.

const Character := preload("res://scenes/venue/floor/character.gd")

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

func run() -> void:
 if not OS.has_environment("GRAND_EXHIBIT_TEST_RUN"):
  printerr("REFUSED: requires GRAND_EXHIBIT_TEST_RUN isolation")
  quit(2)
  return
 root.get_node("SaveSystem").set_process(false)
 var gs = root.get_node("GameState")
 gs.reset_to_new_game()
 gs.ready_flag = true
 seed(20260919)
 var VF = load("res://scenes/venue/floor/venue_floor.gd")
 var floor_node = load("res://scenes/venue/floor/venue_floor.tscn").instantiate()
 root.add_child(floor_node)
 for n in root.get_children():
  n.process_mode = Node.PROCESS_MODE_DISABLED
 var vid := "grand_river"
 gs.current_venue = vid
 floor_node.retheme(vid)
 floor_node.set_rates(root.get_node("Economy").venue_rates(vid))
 check(not floor_node._porters.is_empty(), "venue stages porters")
 var v = VF.Visitor.new()
 v.node = Character.new()
 v.node.set_look_slot(0)
 floor_node._canvas.add_child(v.node)
 v.pos = Vector2(8.0, 2.0)
 v.speed = 1.0
 floor_node._place(v.node, v.pos)
 floor_node._visitors.append(v)
 check(floor_node._hold_in_lobby(v), "guest is admitted to a crowd slot")
 check(v.state == "to_crowd", "guest walks to the crowd (state=%s)" % v.state)
 var blocked_slot: Vector2 = v.target
 # Park a staged porter cart directly on the assigned slot, as a stuck
 # courier would after a long idle session. Only visitor updates run, so
 # the cart never moves on its own. Stand the guest 0.3 tiles out, mirroring
 # the soak evidence (pos 14.46,14.71 vs target 14.0,14.45).
 var cart = floor_node._porters[0]
 cart.pos = blocked_slot
 cart.target = blocked_slot
 cart.staged = true
 floor_node._place(cart.node, cart.pos)
 v.pos = blocked_slot + Vector2(0.21, 0.21)
 v.path = [blocked_slot]
 floor_node._place(v.node, v.pos)
 floor_node._crowd_traffic.begin_step()
 check(not floor_node._crowd_traffic.visitor_clear(v, v.target),
  "the parked cart actually blocks the slot approach")
 var arrived := false
 var reheld := false
 for tick in 1800:
  floor_node._crowd_traffic.begin_step()
  floor_node._update_visitors(0.05)
  if v.state == "crowd":
   arrived = true
   break
  if not v.target.is_equal_approx(blocked_slot):
   reheld = true
 check(arrived, "cart-blocked guest reaches the crowd instead of stalling 90 sim-sec (state=%s)" % v.state)
 check(reheld or v.state == "crowd", "guest re-holds a clear slot rather than waiting on a covered one")
 print("TO_CROWD_RECOVERY checks=", checks, " failures=", failures)
 quit(0 if failures == 0 else 1)
