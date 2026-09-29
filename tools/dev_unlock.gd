extends SceneTree
## dev_unlock.gd — write a fully-unlocked save so every venue, decor piece and
## feature can be inspected immediately. DEV TOOL ONLY.
##
## Lives outside tests/ so the suite glob never picks it up, and it refuses to
## run unless --editor-pid is absent... no: it refuses nothing, because it is
## meant to be destructive. It BACKS UP the existing save first, every time.
##
##   godot --headless --path . -s tools/dev_unlock.gd -- venue=infinite_museum
##   godot --headless --path . -s tools/dev_unlock.gd -- venue=sunspire decor=none
##   godot --headless --path . -s tools/dev_unlock.gd -- restore
##
## Args (all optional, `key=value`):
##   venue=ID     which venue to be standing in (default: keep current)
##   cash=FLOAT   cash to grant, accepts 1e30 notation (default 1e33)
##   gems=INT     gems to grant (default 500000)
##   levels=INT   upgrade every department track to this level (default: each
##                venue's own track_level_cap, which is what opens its gate)
##   days=INT     backdate first launch N days, unlocking day-gated features (default 30)
##   decor=none   do NOT pre-own the decor catalogue (default: own everything)
##   milestones=none  do NOT pre-earn milestones (default: earn them all, so the
##                completion gate is open in every venue)
##   place=all    also PLACE decor into every venue's slots (default: own only,
##                so the slots stay empty and placement can be exercised by hand)
##   restore      put back the most recent backup this tool made, and exit
##
## THE IMPORTANT CAVEAT: close the game before running this. A running instance
## autosaves every 20 seconds and will overwrite whatever this writes.

const BACKUP_DIR := "user://dev_backups"

var _args := {}

func _init() -> void:
	call_deferred("_run")

func _arg(key: String, def: String = "") -> String:
	return str(_args.get(key, def))

func _run() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := (a as String).split("=", true, 1)
		if kv.size() == 2:
			_args[kv[0]] = kv[1]
		else:
			_args[str(a)] = "1"

	var GS: Node = root.get_node_or_null("GameState")
	var SS: Node = root.get_node_or_null("SaveSystem")
	var DL: Node = root.get_node_or_null("DataLoader")
	var MS: GDScript = load("res://scripts/managers/manager_system.gd") as GDScript
	if GS == null or SS == null or DL == null:
		printerr("dev_unlock: autoloads missing — run with --path <repo>")
		quit(2)
		return
	SS.set_process(false)  # never let the autosave clock race this write

	DirAccess.make_dir_recursive_absolute(BACKUP_DIR)

	if _args.has("restore"):
		_restore(SS)
		return

	_backup(SS)

	GS.reset_to_new_game()
	GS.ready_flag = true

	var order: Array = DL.venue_order()
	# Every venue unlocked and NONE closed: the ladder's one-way rule is a
	# progression constraint, not something a dev harness should have to respect.
	GS.venues_unlocked = order.duplicate()
	GS.venues_closed = []

	var venue: String = _arg("venue", "")
	if venue != "" and venue in order:
		GS.current_venue = venue
	elif venue != "":
		printerr("dev_unlock: unknown venue '%s'; known: %s" % [venue, ", ".join(order)])

	GS.cash = _big(_arg("cash", "1e33"))
	GS.gems = int(_arg("gems", "500000"))
	GS.insight = _big("1e12")
	# Reputation past the last authored threshold, so every feature gate opens.
	var thresholds: Array = DL.core.get("reputation", {}).get("thresholds_mantissa", [])
	var top: float = float(thresholds[-1]) if not thresholds.is_empty() else 1.0e12
	GS.reputation_xp = BigNumber.from_float(top * 10.0)
	# Backdate the first launch so day-gated events (Inspection) are available.
	GS.first_launch_unix = int(Time.get_unix_time_from_system()) \
		- int(_arg("days", "30")) * 86400
	GS.last_seen_unix = int(Time.get_unix_time_from_system())

	# Default to each venue's own cap, not a flat number: the caps run
	# [15,25,40,60,80,100,...], so a fixed 30 leaves every venue past the third
	# short of its operations gate and the "complete museum" button dead.
	var levels: int = int(_arg("levels", "0"))
	for vid in order:
		for dept_id in DL.core.get("departments", {}).keys():
			for track in ["staff", "speed", "value"]:
				# Never exceed the venue's own cap; going over it produces states
				# the real game cannot reach and misleads a balance read.
				var cap: int = int(DL.get_venue(str(vid)).get("track_level_cap", 15))
				GS.set_dept_level(str(vid), str(dept_id), track,
					cap if levels <= 0 else mini(levels, cap))

	# Every manager owned, ranked and levelled, so the carousel and the
	# assignment sheet both have something real to show.
	for mid in DL.managers.keys():
		MS.add_cards(str(mid), 500)
		var st: Dictionary = MS.state(str(mid))
		st["level"] = 20
		st["rank"] = 3

	# Grant every venue's milestone chain, so the completion gate is actually
	# reachable in each one. Without this, maxing every station still leaves the
	# progress bar short and the "complete museum" button dead, because the gate
	# is milestones AND capped operations — not levels alone. That is the
	# "I maxed everything and I'm still stuck in the aquarium" symptom.
	if _arg("milestones", "all") != "none":
		for vid in order:
			var chain: Array = DL.milestones.get(str(vid), [])
			var earned: Array = []
			for m in chain:
				earned.append(str((m as Dictionary).get("id", "")))
			GS.venue_state(str(vid))["milestones"] = earned

	var decor_ids: Array = []
	for did in DL.decor.keys():
		decor_ids.append(str(did))
	decor_ids.sort()

	if _arg("decor", "all") != "none":
		# Own every DESIGN but leave the slots empty by default: that is the
		# interesting state to inspect, because it is the one where placement,
		# destination text and the reveal can all be exercised by hand.
		GS.decor_owned = decor_ids.duplicate()

	if _arg("place", "") == "all":
		var DS: GDScript = load("res://scripts/meta/decor_system.gd") as GDScript
		for vid in order:
			for did in decor_ids:
				if DS.first_free_slot(str(vid)) < 0:
					break
				DS.place_decor(str(vid), str(did))

	SS.save_now()

	print("dev_unlock: wrote %s" % SS.save_path())
	print("  venue      : %s  (of %d unlocked)" % [GS.current_venue, GS.venues_unlocked.size()])
	print("  cash/gems  : %s / %d" % [GS.cash.to_notation(), GS.gems])
	print("  rep level  : %d" % GS.rep_level())
	print("  dept levels: %s" % ("each venue's cap" if levels <= 0 else str(levels)))
	print("  managers   : %d owned" % DL.managers.size())
	print("  decor      : %d designs owned, placed=%s"
		% [(GS.decor_owned as Array).size(), _arg("place", "no")])
	var PS: GDScript = load("res://scripts/meta/prestige_system.gd") as GDScript
	print("  gate here  : %s" % ("OPEN — you can complete this museum now"
		if PS.gate_met(GS.current_venue) else "blocked: " + PS.block_reason()))
	print("")
	print("  switch venue: -s tools/dev_unlock.gd -- venue=<id>")
	print("  venues: %s" % ", ".join(order))
	print("  undo   : -s tools/dev_unlock.gd -- restore")
	quit(0)

func _big(text: String) -> BigNumber:
	return BigNumber.from_float(float(text))

## Timestamped, so repeated runs never destroy the first (real) backup.
func _backup(SS: Node) -> void:
	var src: String = SS.save_path()
	if not FileAccess.file_exists(src):
		print("dev_unlock: no existing save to back up")
		return
	var stamp: String = Time.get_datetime_string_from_system().replace(":", "-")
	var dst: String = "%s/save-%s.json" % [BACKUP_DIR, stamp]
	var data: String = FileAccess.get_file_as_string(src)
	var f := FileAccess.open(dst, FileAccess.WRITE)
	if f:
		f.store_string(data)
		f.close()
		print("dev_unlock: backed up -> %s" % dst)

func _restore(SS: Node) -> void:
	var dir := DirAccess.open(BACKUP_DIR)
	if dir == null:
		printerr("dev_unlock: no backups")
		quit(1)
		return
	var names: Array = []
	for n in dir.get_files():
		if n.ends_with(".json"):
			names.append(n)
	if names.is_empty():
		printerr("dev_unlock: no backups")
		quit(1)
		return
	names.sort()
	var newest: String = "%s/%s" % [BACKUP_DIR, names[-1]]
	var data: String = FileAccess.get_file_as_string(newest)
	var f := FileAccess.open(SS.save_path(), FileAccess.WRITE)
	if f:
		f.store_string(data)
		f.close()
	print("dev_unlock: restored %s -> %s" % [newest, SS.save_path()])
	quit(0)
