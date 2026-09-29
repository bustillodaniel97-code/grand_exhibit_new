extends SceneTree
## Interactive QA session. Funds only the isolated profile; normal gameplay runs.
func _initialize() -> void:call_deferred("run")
func run() -> void:
	if not OS.has_environment("GRAND_EXHIBIT_TEST_RUN") or OS.get_environment("XDG_DATA_HOME").is_empty():
		printerr("Funded playtest requires an isolated test profile.");quit(2);return
	var gs: Node=root.get_node("GameState")
	var saves: Node=root.get_node("SaveSystem")
	if not saves.load_game():gs.reset_to_new_game()
	gs.ready_flag=true
	gs.cash=load("res://scripts/core/big_number.gd").from_parts(9.99,300)
	gs.gems=1000000
	if not saves.save_now():printerr("Could not prepare playtest save.");quit(2);return
	root.add_child(load("res://scenes/main.tscn").instantiate())
	var picker: Node=load("res://tools/playtest_venue_picker.gd").new()
	picker.name="PlaytestVenuePicker";root.add_child(picker)
	root.title="Grand Exhibit — Funded Playtest | F6: choose museum"
	print("FUNDED PLAYTEST READY: cash=",gs.cash.to_notation()," gems=",gs.gems," venue=",gs.current_venue," save=",saves.save_path())
	await create_timer(3).timeout
	var args:=OS.get_cmdline_user_args()
	if not args.is_empty():
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(args[0])
