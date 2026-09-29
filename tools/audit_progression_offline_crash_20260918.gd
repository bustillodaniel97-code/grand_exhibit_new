extends SceneTree

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var xdg := OS.get_environment("XDG_DATA_HOME")
	if OS.get_environment("GRAND_EXHIBIT_TEST_RUN") != "1" or not xdg.begins_with("/tmp/grand-audit-progression"):
		print("ABORT: diagnostic requires GRAND_EXHIBIT_TEST_RUN=1 and isolated XDG_DATA_HOME under /tmp/grand-audit-progression")
		quit(2)
	var ss: Node = get_root().get_node("SaveSystem")
	var gs: Node = get_root().get_node("GameState")
	var cg: Node = get_root().get_node("ClockGuard")
	var mode := OS.get_cmdline_user_args()[0] if OS.get_cmdline_user_args().size() > 0 else "seed"
	var dl: Node = get_root().get_node("DataLoader")
	dl.reload_all()
	gs.reset_to_new_game()
	gs.ready_flag = true
	if mode == "seed":
		gs.cash = BigNumber.zero()
		gs.last_seen_unix = cg.now() - 3600
		var state: Dictionary = gs.to_save_dict()
		var envelope: Dictionary = {"version": 6, "saved_at": gs.last_seen_unix,
			"checksum": ss._checksum(JSON.stringify(state)), "state": state}
		var f := FileAccess.open(ss.save_path(), FileAccess.WRITE)
		f.store_string(JSON.stringify(envelope))
		f.close()
		var first: Dictionary = ss.compute_offline_and_apply()
		print("FIRST amount=%s seconds=%d cash=%s last_seen=%d" % [first.amount.to_notation(), first.seconds, gs.cash.to_notation(), gs.last_seen_unix])
		# Finite window lets a harness interrupt before autosave without leaving a
		# forgotten Godot process if the harness itself fails.
		await create_timer(8.0).timeout
		quit()
	else:
		var loaded: bool = ss.load_game()
		var second: Dictionary = ss.compute_offline_and_apply()
		print("SECOND loaded=%s amount=%s seconds=%d cash=%s last_seen=%d" % [loaded, second.amount.to_notation(), second.seconds, gs.cash.to_notation(), gs.last_seen_unix])
		quit()
