extends Node
## PlatformServices — the one door to whichever storefront this build ships on.
##
## Game code calls this, never a store SDK: unlock achievements, report stats,
## and (later) cloud saves and the overlay. The backend is chosen at runtime:
##   "steam"  GodotSteam GDExtension present (Engine singleton "Steam"); builds
##            exported from the Steam presets carry the "steam" feature tag.
##   "epic"   an EOS plugin singleton ("EOS" / "IEOS") on "epic" builds.
##   "none"   everything else (mobile, Microsoft Store, dev runs): achievements
##            are still tracked and saved locally, so wiring a store later
##            back-fills what the player already earned.
## Store SDK calls go through call() on the singleton, so this script compiles
## and runs without any plugin installed. docs/PLATFORMS.md has the setup.
##
## Achievements are data (data/achievements.json): each names the EventBus
## signal that re-checks it and a counter; counters derive from game state
## where possible and only "upgrades" is counted here.

signal achievement_unlocked(id: String, def: Dictionary)

var backend := "none"
var _store: Object = null
var _defs: Array = []

func _ready() -> void:
	_defs = _load_defs()
	_detect_backend()
	var signals := {}
	for d in _defs:
		signals[str(d.get("on", ""))] = true
	for sig in signals.keys():
		if sig != "" and EventBus.has_signal(sig):
			EventBus.connect(sig, _on_event.unbind(_arg_count(sig)))
	# Counters only events can know.
	EventBus.department_upgraded.connect(func(_v: String, _d: String, _t: String, _l: int) -> void: _bump("upgrades"))
	EventBus.item_upgraded.connect(func(_v: String, _d: String, _i: int, _l: int) -> void: _bump("upgrades"))
	EventBus.vip_tipped.connect(func(type_id: String, _amount: Variant) -> void:
		if type_id == "royal":
			_bump("royal_tips")
		_bump("vip_tips"))
	# Catch up once the save is loaded (and mirror to a newly attached store).
	var t := get_tree().create_timer(2.0)
	t.timeout.connect(func() -> void:
		check_all()
		sync_store())

func _arg_count(sig: String) -> int:
	for s in EventBus.get_signal_list():
		if str(s["name"]) == sig:
			return (s["args"] as Array).size()
	return 0

func _load_defs() -> Array:
	var f := FileAccess.open("res://data/achievements.json", FileAccess.READ)
	if f == null:
		return []
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	return (parsed as Dictionary).get("achievements", []) if parsed is Dictionary else []

func _detect_backend() -> void:
	if Engine.has_singleton("Steam") and (OS.has_feature("steam") or OS.has_feature("editor")):
		_store = Engine.get_singleton("Steam")
		var ok := true
		if _store.has_method("steamInitEx"):
			var res: Variant = _store.call("steamInitEx", false)
			ok = res is Dictionary and int((res as Dictionary).get("status", 1)) == 0
		elif _store.has_method("steamInit"):
			_store.call("steamInit")
		backend = "steam" if ok else "none"
	elif OS.has_feature("epic"):
		for name in ["EOS", "IEOS"]:
			if Engine.has_singleton(name):
				_store = Engine.get_singleton(name)
				backend = "epic"
				break
	if backend == "none":
		_store = null

func _process(_delta: float) -> void:
	if backend == "steam" and _store != null and _store.has_method("run_callbacks"):
		_store.call("run_callbacks")

# ----------------------------------------------------------------- achievements

func definitions() -> Array:
	return _defs

func unlocked() -> Array:
	return _state().get("unlocked", [])

func is_unlocked(id: String) -> bool:
	return id in unlocked()

func _state() -> Dictionary:
	var s: Dictionary = GameState.achievements_state
	if not s.has("unlocked"):
		s["unlocked"] = []
		s["counters"] = {}
	return s

func _bump(counter: String) -> void:
	var c: Dictionary = _state()["counters"]
	c[counter] = int(c.get(counter, 0)) + 1
	check_all()

func _on_event() -> void:
	check_all()

## Current value of an achievement counter, derived from game state.
func counter(name: String) -> int:
	match name:
		"milestones":
			var n := 0
			for vs in GameState.venues_state.values():
				n += (vs as Dictionary).get("milestones", []).size()
			return n
		"wings":
			var w := 0
			for vs in GameState.venues_state.values():
				w += (vs as Dictionary).get("wings", []).size()
			return w
		"best_grandeur":
			var best := 1
			for vs in GameState.venues_state.values():
				best = maxi(best, 1 + (vs as Dictionary).get("wings", []).size())
			return best
		"artifacts", "perfect_artifacts", "sets":
			var col: Dictionary = GameState.dig_state.get("collection", {})
			var total := 0
			var perfect := 0
			var sets := 0
			for vid in col.keys():
				var arts: Dictionary = col[vid]
				total += arts.size()
				for q in arts.values():
					if int(q) >= 3:
						perfect += 1
				if arts.size() >= 5:
					sets += 1
			return {"artifacts": total, "perfect_artifacts": perfect, "sets": sets}[name]
		"museums":
			return GameState.venues_unlocked.size()
		"managers":
			var m := 0
			for st in GameState.managers_state.values():
				if int((st as Dictionary).get("cards", 0)) > 0 or str((st as Dictionary).get("assigned_to", "")) != "":
					m += 1
			return m
		"rep":
			return GameState.rep_level()
	return int((_state()["counters"] as Dictionary).get(name, 0))

func check_all() -> void:
	if not GameState.ready_flag:
		return
	for d in _defs:
		var id := str(d.get("id", ""))
		if id == "" or is_unlocked(id):
			continue
		if counter(str(d.get("count", ""))) >= int(d.get("need", 1)):
			unlock(id)

## Record an achievement and mirror it to the storefront.
func unlock(id: String) -> void:
	if is_unlocked(id):
		return
	(_state()["unlocked"] as Array).append(id)
	var def := {}
	for d in _defs:
		if str(d.get("id", "")) == id:
			def = d
	if backend == "steam" and _store != null:
		_store.call("setAchievement", id)
		_store.call("storeStats")
	elif backend == "epic" and _store != null and _store.has_method("unlock_achievement"):
		_store.call("unlock_achievement", id)
	achievement_unlocked.emit(id, def)
	EventBus.toast_requested.emit("Achievement: %s" % str(def.get("name", id)))
	Analytics.log_event("achievement", {"id": id, "backend": backend})

## Resync every locally earned achievement to the store (first launch on a new
## storefront, or after the player earned some offline).
func sync_store() -> void:
	if backend == "none":
		return
	for id in unlocked():
		if backend == "steam":
			_store.call("setAchievement", str(id))
		elif backend == "epic" and _store.has_method("unlock_achievement"):
			_store.call("unlock_achievement", str(id))
	if backend == "steam":
		_store.call("storeStats")
