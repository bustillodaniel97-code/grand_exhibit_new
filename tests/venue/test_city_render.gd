extends SceneTree
## test_city_render.gd — the surround must stay drawable.
##
## 8649a58f set `_city.z_index = -1` so district walkers could not be covered
## by their own ground. A negative relative index draws the whole city BEFORE
## the venue background instead: grass, roads, blocks, sidewalks, transit stops
## and business frontage vanished on every platform, and no existing suite
## noticed because they all assert simulation state, not renderability.
##
## This pins the invariants that were silently violated: the city is a visible
## child of the canvas at a non-negative relative z, its district design is
## loaded, and its visible band is sane. Fails on 8649a58f..5af8d91b^, passes
## after.

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
	var floor_node = load("res://scenes/venue/floor/venue_floor.tscn").instantiate()
	floor_node.size = Vector2(720, 760)
	root.add_child(floor_node)
	for n in root.get_children():
		n.process_mode = Node.PROCESS_MODE_DISABLED
	gs.current_venue = "whispering_pines"
	floor_node.retheme("whispering_pines")
	await process_frame
	await process_frame
	var city = floor_node._city
	check(city != null, "venue builds a city node")
	if city == null:
		print("CITY_RENDER checks=", checks, " failures=", failures)
		quit(1)
		return
	check(city.visible, "city node is visible")
	check(city.z_index >= 0,
		"city keeps a non-negative relative z_index (got %d; a negative value hides the surround behind the venue background)" % city.z_index)
	check(city.get_parent() == floor_node._canvas, "city is a direct child of the floor canvas")
	var design: Dictionary = city.district.design
	check(not design.is_empty(), "district design is loaded")
	check(str(city.style) != "", "city style follows the venue surround")
	var band: Rect2 = city._band
	check(band.size.x > 1.0 and band.size.y > 1.0,
		"visible band is reported to the city (got %s)" % str(band))
	print("CITY_RENDER checks=", checks, " failures=", failures)
	quit(0 if failures == 0 else 1)
