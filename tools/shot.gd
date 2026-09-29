extends SceneTree
## Screenshot harness — boots the real game shell into an exact 720x1280
## SubViewport (display-independent) and captures it to PNG. Dev tool only;
## it lives outside tests/ so the suite glob never picks it up.
##
##   godot --path . -s tools/shot.gd -- out=/abs/x.png warm=3 cash=1e9 levels=8 \
##       open=res://scenes/managers/managers_screen.tscn tap=350,620
##
## Args (all optional, `key=value`):
##   out=PATH        target png, absolute or res://user:// (default user://shot.png).
##                   out2=/out3=... with at2=/at3=... capture a timed sequence.
##   warm=SECS       seconds of simulated play before the first capture (default 2)
##   sim=SECS        optional accelerated floor simulation after seeding; warm
##                   still renders live frames afterward. Art preview only,
##                   not a wall-clock performance or whole-economy benchmark.
##   cash=FLOAT      grant cash before warm-up (accepts 1e9 notation)
##   gems=INT        grant gems
##   levels=INT      buy this many upgrade levels per dept track before warm-up
##   days=INT        backdate first launch N days, to unlock day-gated features
##   venue=ID        switch to a venue (unlocks it first) — for previewing themes
##   open=RES_PATH   open a popup screen after warm-up
##   tap=X,Y         click at design-space (720x1280) coords after warm-up
##   wings=N         complete this museum's milestones and renovate its first N
##                   wings (floors / facade) before warm-up; with reveal=1 the
##                   renovations happen at capture time instead, to catch the
##                   renovation moment
##   floor=I         glide the 3D camera to floor I (0 = ground) before capture

const MAIN := "res://scenes/main.tscn"
const DESIGN := Vector2i(720, 1280)
const SETTLE := 0.6      # seconds allowed for open/close tweens to finish

var _args := {}
var _shots: Array = []          # [{t: float, path: String}]
var _t := 0.0
var _fired := false
var _tapped := false
var _done := false
var _vp: SubViewport = null


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := (a as String).split("=", true, 1)
		if kv.size() == 2:
			_args[kv[0]] = kv[1]

	_vp = SubViewport.new()
	_vp.size = DESIGN
	_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	# Mirror the shipping viewport setting. Compatibility ignores MSAA; world
	# edge smoothing is instead part of VenueFloor and therefore captured here.
	_vp.msaa_2d = ProjectSettings.get_setting(
		"rendering/anti_aliasing/quality/msaa_2d", 0) as Viewport.MSAA
	_vp.canvas_item_default_texture_filter = ProjectSettings.get_setting(
		"rendering/textures/canvas_textures/default_texture_filter", 1) as Viewport.DefaultCanvasItemTextureFilter
	_vp.handle_input_locally = true
	_vp.gui_embed_subwindows = true
	root.add_child(_vp)
	_vp.add_child((load(MAIN) as PackedScene).instantiate())

	var warm := float(_args.get("warm", "2.0"))
	_shots.append({"t": warm, "path": String(_args.get("out", "user://shot.png"))})
	for i in range(2, 6):
		if _args.has("out%d" % i):
			_shots.append({
				"t": float(_args.get("at%d" % i, str(warm + float(i - 1)))),
				"path": String(_args["out%d" % i]),
			})
	_shots.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["t"] < b["t"])
	call_deferred("_seed")


## Grant currency / levels so the floor renders a mature museum, not an empty one.
## Dev harnesses seed cash and levels into the LIVE GameState autoload. With
## SaveSystem's 20s autosave running, those doctored values were being written
## to the real user:// save, which then loaded into the next test run and turned
## the battery red (test_shell_smoke asserting a purchase moved a level that was
## already past it). A dev tool must never mutate the player's save.
func _isolate_from_save() -> void:
	var ss: Node = root.get_node_or_null("SaveSystem")
	if ss != null:
		ss.set_process(false)          # stop the autosave tick
		ss.autosave_interval_sec = 1 << 30


func _seed() -> void:
	_isolate_from_save()
	var gs: Node = root.get_node_or_null("GameState")
	if gs == null:
		return
	var BigNumber: GDScript = load("res://scripts/core/big_number.gd")
	if _args.has("cash"):
		gs.add_cash(BigNumber.from_float(float(_args["cash"])))
	if _args.has("gems"):
		gs.gems += int(_args["gems"])
	# Backdate first launch so day-gated features (Inspection Frenzy) unlock.
	if _args.has("days"):
		gs.first_launch_unix -= int(_args["days"]) * 86400
	if _args.has("venue"):
		var vid: String = String(_args["venue"])
		if vid not in root.get_node("DataLoader").venue_order():
			printerr("SHOT unknown venue: ",vid)
			_done=true;quit(2);return
		if vid not in gs.venues_unlocked:
			gs.venues_unlocked.append(vid)
		gs.current_venue = vid
		# The floor binds its theme at _ready and only re-themes on the prestige
		# signal, so a direct venue switch needs an explicit retheme to be visible.
		var floor_node: Node = _find_floor(root)
		if floor_node != null and floor_node.has_method("retheme"):
			floor_node.retheme(vid)
	var lv := int(_args.get("levels", "0"))
	if lv > 0:
		var venue: String = gs.current_venue
		for dept in ["ticket", "archive", "promotions", "gallery"]:
			for track in ["staff", "speed", "value"]:
				gs.set_dept_level(venue, dept, track,
					gs.dept_level(venue, dept, track) + lv)
	if _args.has("wings") and not bool(int(_args.get("reveal", "0"))):
		_renovate(int(_args["wings"]))
	if _args.has("sim"):
		var preview_floor: Node = _find_floor(root)
		var economy: Node = root.get_node_or_null("Economy")
		if preview_floor != null and economy != null:
			preview_floor.set_rates(economy.venue_rates(gs.current_venue))
			preview_floor.advance_sim(maxf(0.0,float(_args["sim"])))
			print("PREVIEW_SIM accelerated floor seconds=",_args["sim"])


func _renovate(n: int) -> void:
	var gs: Node = root.get_node("GameState")
	var dl: Node = root.get_node("DataLoader")
	var ws: GDScript = load("res://scripts/meta/wing_system.gd")
	var BigNumber: GDScript = load("res://scripts/core/big_number.gd")
	var vid: String = gs.current_venue
	var ids: Array = []
	for ms in dl.milestones.get(vid, []):
		ids.append(str(ms["id"]))
	gs.venue_state(vid)["milestones"] = ids
	for _i in n:
		var w: Dictionary = ws.next_wing(vid)
		if w.is_empty():
			break
		gs.add_cash(ws.price(vid, str(w["id"])).add(BigNumber.from_float(1.0)))
		print("SHOT renovate ", w["id"], " ok=", ws.renovate(vid, str(w["id"])))


func _find_floor(n: Node) -> Node:
	if n.name == "VenueFloor":
		return n
	for c in n.get_children():
		var r: Node = _find_floor(c)
		if r != null:
			return r
	return null


func _process(delta: float) -> bool:
	if _done:
		return true
	_t += delta
	if _shots.is_empty():
		return true
	if _t < float(_shots[0]["t"]):
		return false
	# Three staged beats, because doing them in one frame does not work:
	#   warm            -> open the popup
	#   warm + SETTLE   -> deliver the tap (the screen has laid out by now; tapping
	#                      in the open frame hits a zero-size rect and does nothing)
	#   warm + 2*SETTLE -> capture (open/close tweens have finished)
	if not _fired:
		_fired = true
		_fire_open()
		for s in _shots:
			s["t"] = float(s["t"]) + SETTLE * 2.0
		return false
	if not _tapped and _t >= float(_shots[0]["t"]) - SETTLE:
		_tapped = true
		_fire_zoom()
		_fire_tap()
		return false
	var next: Dictionary = _shots.pop_front()
	_capture(String(next["path"]))
	if _shots.is_empty():
		_done = true
		quit(0)
	return false


func _fire_open() -> void:
	var Popups: GDScript = load("res://scripts/ui/popup_manager.gd")
	if bool(int(_args.get("clear", "1"))):
		for _i in 4:
			Popups.close_top()
	if _args.has("open"):
		Popups.open(String(_args["open"]), {})
	if _args.has("wings") and bool(int(_args.get("reveal", "0"))):
		_renovate(int(_args["wings"]))
	if _args.has("floor"):
		var fl: Node = _find_floor(root)
		if fl != null and fl.has_method("go_to_floor"):
			fl.go_to_floor(int(_args["floor"]))


## Drive the venue camera through the REAL input path, not by poking the field.
##
## `zoom=2.0 at=360,700` pinches to 2x about that point. Sending a magnify gesture
## rather than setting _user_zoom is deliberate: it exercises the focal-point
## correction, which is the part that gets a pinch wrong (the museum slides out
## from under your fingers) and the part a screenshot can actually show.
func _fire_zoom() -> void:
	if not _args.has("zoom"):
		return
	var focus: Vector2 = Vector2(DESIGN) * 0.5
	if _args.has("at"):
		var xy: PackedStringArray = String(_args["at"]).split(",")
		if xy.size() == 2:
			focus = Vector2(float(xy[0]), float(xy[1]))
	var want: float = maxf(float(_args["zoom"]), 0.05)
	# In steps, the way fingers deliver it.
	var steps := 8
	var per: float = pow(want, 1.0 / float(steps))
	for _i in steps:
		var ev := InputEventMagnifyGesture.new()
		ev.factor = per
		ev.position = focus
		_vp.push_input(ev, true)


func _fire_tap() -> void:
	if _args.has("tap"):
		var xy: PackedStringArray = String(_args["tap"]).split(",")
		if xy.size() == 2:
			var p := Vector2(float(xy[0]), float(xy[1]))
			for pressed in [true, false]:
				var ev := InputEventMouseButton.new()
				ev.button_index = MOUSE_BUTTON_LEFT
				ev.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
				ev.pressed = pressed
				ev.position = p
				ev.global_position = p
				_vp.push_input(ev, true)


func _report_clumps() -> void:
	var f: Node = _find_floor(root)
	if f != null and f.has_method("clump_report"):
		print("CLUMPS ", f.clump_report())
		print("CENSUS ", f.state_census())
		var outdoors: Array = []
		for person in f._plaza.people:
			outdoors.append({"activity":f._plaza.activities[person.activity_index].kind,
				"state":person.state,"position":str(person.pos),"seated":person.node.seated})
		print("PLAZA_CENSUS ",outdoors)


func _capture(path: String) -> void:
	_report_clumps()
	var img: Image = _vp.get_texture().get_image()
	var target := path
	if not path.is_absolute_path():
		target = ProjectSettings.globalize_path("res://").path_join(path)
	var err := img.save_png(target)
	print("SHOT ", target, " ", img.get_width(), "x", img.get_height(), " err=", err)
