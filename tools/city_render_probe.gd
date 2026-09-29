extends SceneTree
## city_render_probe.gd — why is (or isn't) the surrounding city drawing?
## Reports the state of the city node and its district design for one venue.
## Diagnostic only; isolated profile.

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var xdg := OS.get_environment("XDG_DATA_HOME")
	if OS.get_environment("GRAND_EXHIBIT_TEST_RUN") != "1" or not xdg.begins_with("/tmp/grand-audit-world"):
		printerr("AUDIT_REFUSED: requires GRAND_EXHIBIT_TEST_RUN=1 and XDG_DATA_HOME=/tmp/grand-audit-world")
		quit(2)
		return
	root.get_node("SaveSystem").set_process(false)
	var gs = root.get_node("GameState")
	gs.reset_to_new_game()
	gs.ready_flag = true
	var f = load("res://scenes/venue/floor/venue_floor.tscn").instantiate()
	f.size = Vector2(720, 760)
	root.add_child(f)
	for n in root.get_children():
		n.process_mode = Node.PROCESS_MODE_DISABLED
	gs.current_venue = "whispering_pines"
	f.retheme("whispering_pines")
	await process_frame
	await process_frame
	var city = f._city
	print("CITY_PROBE city_null=", city == null)
	if city == null:
		quit(0)
		return
	print("CITY_PROBE visible=", city.visible, " modulate=", city.modulate,
		" z=", city.z_index, " parent=", city.get_parent().name if city.get_parent() != null else "none")
	print("CITY_PROBE style=", city.style, " venue_id=", city.venue_id,
		" band=", city._band, " fp=", city._fp)
	var design: Dictionary = city.district.design
	print("CITY_PROBE design_empty=", design.is_empty(), " keys=", design.keys().slice(0, 8))
	if not design.is_empty():
		print("CITY_PROBE ground_col=", design.get("ground"), " identity=", design.get("identity"))
	print("CITY_PROBE lawn_pal=", city._pal.get("lawn", "missing"),
		" ground_cnt=", city._ground_plane_calls if "_ground_plane_calls" in city else "n/a")
	# Compare with the venue theme's surround, which selects the district.
	print("CITY_PROBE theme_surround=", f._theme.surround,
		" floor_visible=", f.visible, " floor_size=", f.size,
		" canvas_pos=", f._canvas.position, " canvas_scale=", f._canvas.scale)
	# Names of city children in draw order.
	var kids: Array = []
	for c in city.get_children():
		kids.append("%s(vis=%s,z=%d)" % [c.name, str(c.visible), c.z_index if c is Node2D else 0])
	print("CITY_PROBE children=", kids)
	quit(0)
