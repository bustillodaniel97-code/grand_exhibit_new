extends SceneTree
## test_cafe_seasons.gd — the Pop-Up Café's seasons (data/cafe_event.json
## "seasons", CafeSystem.season_at / theme, cafe_world weather).
##
## Proves: dates map to seasons on the local calendar, including a window that
## wraps the new year, and to none between seasons; an event keeps the season
## it opened in; the season renames the café and its stations and recolours
## it, keeping the museum's café otherwise; the diorama gets the season's
## weather (and none out of season); the seasonal names are translated.

var failures := 0

func check(ok: bool, message: String) -> void:
	if ok:
		print("  PASS ", message)
	else:
		failures += 1
		printerr("  FAIL ", message)

func _initialize() -> void:
	call_deferred("run")

## Noon local time on `month`/`day` of 2026.
func _local_noon(month: int, day: int) -> int:
	var bias := int(Time.get_time_zone_from_system().get("bias", 0)) * 60
	return Time.get_unix_time_from_datetime_dict({"year": 2026, "month": month, "day": day, "hour": 12, "minute": 0, "second": 0}) - bias

func _set_rep(gs: Node, level: int) -> void:
	var th: Array = root.get_node("DataLoader").core.get("reputation", {}).get("thresholds_mantissa", [])
	var BN: GDScript = load("res://scripts/core/big_number.gd")
	if th.size() >= level:
		gs.reputation_xp = BN.from_float(float(th[level - 1]))

func run() -> void:
	if not OS.has_environment("GRAND_EXHIBIT_TEST_RUN"):
		printerr("REFUSED: requires GRAND_EXHIBIT_TEST_RUN isolation"); quit(2); return
	var CS: GDScript = load("res://scripts/events/cafe_system.gd")
	var gs: Node = root.get_node("GameState")
	root.get_node("SaveSystem").set_process(false)
	root.get_node("Economy").set_process(false)
	gs.reset_to_new_game()
	gs.ready_flag = true

	check(CS.seasons().size() >= 4, "seasons are defined in data")
	var cases := [[12, 15, "frost_fair"], [1, 3, "frost_fair"], [1, 10, ""], [3, 25, "blossom"],
		[6, 1, ""], [8, 15, "summer_fete"], [10, 31, "harvest_moon"], [11, 30, ""]]
	for c in cases:
		var got := str(CS.season_at(_local_noon(int(c[0]), int(c[1]))).get("id", ""))
		check(got == str(c[2]), "%02d-%02d is %s" % [int(c[0]), int(c[1]), str(c[2]) if str(c[2]) != "" else "no season"])

	# An event keeps the season it opened in.
	_set_rep(gs, 4)
	var s: Dictionary = CS._raw()
	CS._open_new(s, 7, _local_noon(12, 20))
	check(str(s.get("season", "")) == "frost_fair", "an event opening on 20 December is a Frost Fair")
	var t: Dictionary = CS.theme()
	var base: Dictionary = (CS.config().get("themes", {}) as Dictionary).get(str(s["theme"]), {})
	check(str(t["name"]) == "Frost Fair Café" and str(t.get("weather", "")) == "snow", "the café is renamed and it snows")
	check(str((t["stations"] as Dictionary)["bar"]) == "Hot Chocolate Bar" and CS.station_name("kiosk") == "Snow Globe Stall",
		"its stations are seasonal")
	check(str((t["palette"] as Dictionary)["c_awning_a"]) == "#D83A3A", "and so are its colours")
	check(str(base.get("name", "")) != "Frost Fair Café", "the museum's own café is untouched in data")

	# The diorama gets the weather.
	var vp := SubViewport.new()
	vp.size = Vector2i(360, 640)
	vp.own_world_3d = true
	root.add_child(vp)
	var W: GDScript = load("res://scenes/events/cafe_world.gd")
	var world: Node3D = W.new()
	vp.add_child(world)
	await process_frame
	var snow := world.find_child("Weather", false, false) as CPUParticles3D
	check(snow != null and snow.amount > 0 and snow.emitting, "snow falls on the Frost Fair café")
	world.queue_free()
	await process_frame

	# Out of season: the museum's café, no weather.
	CS._open_new(s, 8, _local_noon(6, 10))
	check(str(s.get("season", "x")) == "" and str(CS.theme().get("name", "")) == str(base.get("name", "")),
		"a June event is the museum's own café")
	var world2: Node3D = W.new()
	vp.add_child(world2)
	await process_frame
	check(world2.find_child("Weather", false, false) == null, "with no weather")
	world2.queue_free()

	# Seasonal names are translated.
	CS._open_new(s, 9, _local_noon(10, 5))
	TranslationServer.set_locale("es")
	check(CS.station_name("case") == "Vitrina de tarta de calabaza", "seasonal stations speak Spanish")
	check(root.tr(str(CS.theme()["name"])) == "Café Luna de la Cosecha", "and so does the café's name")
	TranslationServer.set_locale("en")

	await create_timer(0.5).timeout
	print("RESULT: ", "OK" if failures == 0 else "FAILED (%d)" % failures)
	quit(1 if failures > 0 else 0)
