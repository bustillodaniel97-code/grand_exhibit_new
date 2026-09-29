extends RefCounted
## CafeSystem — the Pop-Up Café, the museum's timed event area. No class_name.
##
## Like Idle Bank Tycoon's event café: a small side business with its own
## currency (café coins), its own stations to upgrade and its own reward track,
## open for duration_hours and then closed for cooldown_hours. Each event is
## themed after the museum the player is in when it opens (data/cafe_event.json).
##
## Time: events repeat on a fixed cycle from `anchor`, the first moment the
## player could see the café (reputation unlock_rep). Coins settle lazily from
## the saved timestamp, so the café earns offline (capped) and never past the
## event's end.
##
## State (GameState.event_state["pop_up_cafe"], saved with the game):
##   anchor     unix time the cycle is measured from
##   cycle      which event the rest of the state belongs to
##   theme      venue id the café is themed after
##   coins      café coins (float; they reset every event)
##   levels     station id -> level (0 = closed)
##   t          unix time coins were last settled
##   claimed    reward indices already collected

const BattleMath := preload("res://scripts/events/battle_math.gd")
const KEY := "pop_up_cafe"

static var _cfg: Dictionary = {}

static func config() -> Dictionary:
	if _cfg.is_empty():
		var f := FileAccess.open("res://data/cafe_event.json", FileAccess.READ)
		if f != null:
			var parsed: Variant = JSON.parse_string(f.get_as_text())
			if parsed is Dictionary:
				_cfg = parsed
	return _cfg

static func stations() -> Array:
	return config().get("stations", [])

static func station(id: String) -> Dictionary:
	for s in stations():
		if str(s.get("id", "")) == id:
			return s
	return {}

static func rewards() -> Array:
	return config().get("rewards", [])

static func unlocked() -> bool:
	return GameState.rep_level() >= int(config().get("unlock_rep", 3))

static func _now() -> int:
	return ClockGuard.now()

static func _raw() -> Dictionary:
	if not GameState.event_state.has(KEY):
		GameState.event_state[KEY] = {}
	return GameState.event_state[KEY]

static func _cycle_len() -> int:
	return int(3600.0 * (float(config().get("duration_hours", 72)) + float(config().get("cooldown_hours", 48))))

static func _duration() -> int:
	return int(3600.0 * float(config().get("duration_hours", 72)))

## {"live", "cycle", "starts_at", "ends_at", "next_at"} for `now`.
static func window(now: int = -1) -> Dictionary:
	if now < 0:
		now = _now()
	var s := _raw()
	if not s.has("anchor"):
		return {"live": false, "cycle": -1, "starts_at": 0, "ends_at": 0, "next_at": 0}
	var anchor := int(s["anchor"])
	var n := _cycle_len()
	var since := maxi(0, now - anchor)
	var cycle := since / n
	var start := anchor + cycle * n
	var live := now - start < _duration()
	return {"live": live, "cycle": cycle, "starts_at": start, "ends_at": start + _duration(),
		"next_at": start + n}

static func is_live() -> bool:
	return unlocked() and bool(tick().get("live", false))

## Bring the state up to date: start the cycle clock on first unlock, open a
## fresh café when a new event starts, and settle coins. Returns window().
static func tick(now: int = -1) -> Dictionary:
	if now < 0:
		now = _now()
	var s := _raw()
	if not s.has("anchor"):
		if not unlocked():
			return window(now)
		s["anchor"] = now
	var w := window(now)
	if int(s.get("cycle", -1)) != int(w["cycle"]):
		if bool(w["live"]):
			_open_new(s, int(w["cycle"]), now)
		else:
			s["cycle"] = -2  # between events: nothing to show until the next opens
	elif bool(w["live"]) or int(s.get("t", now)) < int(w["ends_at"]):
		_settle(s, mini(now, int(w["ends_at"])))
	return w

static func _open_new(s: Dictionary, cycle: int, now: int) -> void:
	s["cycle"] = cycle
	s["theme"] = GameState.current_venue
	s["season"] = str(season_at(now).get("id", ""))
	s["coins"] = 0.0
	var levels := {}
	for st in stations():
		levels[str(st["id"])] = 1 if float(st.get("open_cost", 0)) <= 0.0 else 0
	s["levels"] = levels
	s["t"] = now
	s["claimed"] = []
	s["earned"] = 0.0

static func _settle(s: Dictionary, until: int) -> void:
	var last := int(s.get("t", until))
	if until <= last:
		return
	var dt := float(until - last)
	var cap := 3600.0 * float(config().get("offline_cap_hours", 8))
	var gain := rate() * minf(dt, cap)
	s["coins"] = float(s.get("coins", 0.0)) + gain
	s["earned"] = float(s.get("earned", 0.0)) + gain
	s["t"] = until

## The café the current event is themed after: the museum's café, dressed for
## the season the event opened in (name, stations, palette, weather).
static func theme() -> Dictionary:
	var themes: Dictionary = config().get("themes", {})
	var vid := str(_raw().get("theme", GameState.current_venue))
	var base: Dictionary = themes.get(vid, themes.get("whispering_pines", {}))
	var se := season()
	if se.is_empty():
		return base
	var t: Dictionary = base.duplicate(true)
	t["name"] = str(se.get("name", t.get("name", "")))
	var st: Dictionary = (t.get("stations", {}) as Dictionary)
	st.merge(se.get("stations", {}), true)
	t["stations"] = st
	t["palette"] = se.get("palette", t.get("palette", {}))
	t["weather"] = str(se.get("weather", ""))
	t["season"] = str(se.get("id", ""))
	return t

# ------------------------------------------------------------------- seasons

static func seasons() -> Array:
	return config().get("seasons", [])

## "MM-DD" -> MMDD as an int (1201 for December 1st).
static func _md(s: String) -> int:
	var parts := s.split("-")
	if parts.size() != 2:
		return -1
	return int(parts[0]) * 100 + int(parts[1])

## The season `unix` falls in on the player's local calendar, or {}. A window
## may wrap the new year (from 12-01 to 01-06).
static func season_at(unix: int) -> Dictionary:
	var bias := int(Time.get_time_zone_from_system().get("bias", 0)) * 60
	var d := Time.get_datetime_dict_from_unix_time(unix + bias)
	var md := int(d["month"]) * 100 + int(d["day"])
	for se in seasons():
		var from := _md(str((se as Dictionary).get("from", "")))
		var to := _md(str((se as Dictionary).get("to", "")))
		if from < 0 or to < 0:
			continue
		var inside := (md >= from and md <= to) if from <= to else (md >= from or md <= to)
		if inside:
			return se
	return {}

## The season the current event opened in, or {}.
static func season() -> Dictionary:
	var id := str(_raw().get("season", ""))
	if id == "":
		return {}
	for se in seasons():
		if str((se as Dictionary).get("id", "")) == id:
			return se
	return {}

static func station_name(id: String) -> String:
	return str(TranslationServer.translate(str((theme().get("stations", {}) as Dictionary).get(id, id.capitalize()))))

static func coins() -> float:
	return float(_raw().get("coins", 0.0))

static func level(id: String) -> int:
	return int((_raw().get("levels", {}) as Dictionary).get(id, 0))

static func max_level() -> int:
	return int(config().get("max_level", 100))

static func income(id: String, lvl: int = -1) -> float:
	var st := station(id)
	var l := level(id) if lvl < 0 else lvl
	if st.is_empty() or l <= 0:
		return 0.0
	var every := int(config().get("milestone_every", 25))
	var mult := pow(float(config().get("milestone_mult", 1.5)), float(l / maxi(every, 1)))
	return float(st.get("base_income", 1.0)) * float(l) * mult

static func rate() -> float:
	var total := 0.0
	for st in stations():
		total += income(str(st["id"]))
	return total

## Price of the next level (or of opening a closed station).
static func cost(id: String) -> float:
	var st := station(id)
	var l := level(id)
	if l <= 0:
		return float(st.get("open_cost", 0.0))
	return float(st.get("base_cost", 10.0)) * pow(float(st.get("growth", 1.2)), float(l - 1))

static func can_buy(id: String) -> bool:
	return is_live() and level(id) < max_level() and coins() >= cost(id)

static func buy(id: String) -> bool:
	if not can_buy(id):
		return false
	var s := _raw()
	s["coins"] = coins() - cost(id)
	(s["levels"] as Dictionary)[id] = level(id) + 1
	return true

## Stars: one per station level bought (the reward track's currency).
static func stars() -> int:
	var n := 0
	for st in stations():
		n += level(str(st["id"]))
	return n

static func is_claimed(index: int) -> bool:
	return index in (_raw().get("claimed", []) as Array)

static func claimable(index: int) -> bool:
	if index < 0 or index >= rewards().size() or is_claimed(index):
		return false
	return stars() >= int((rewards()[index] as Dictionary).get("stars", 0))

static func any_claimable() -> bool:
	for i in rewards().size():
		if claimable(i):
			return true
	return false

## Collect reward `index`. Returns what was granted ({} if not claimable).
static func claim(index: int) -> Dictionary:
	if not claimable(index):
		return {}
	var r: Dictionary = rewards()[index]
	var applied := {"gems": 0, "cards": {}}
	var box_id := str(r.get("cards_box", ""))
	if box_id != "":
		var rng := RandomNumberGenerator.new()
		rng.randomize()
		var drawn: Dictionary = BattleMath.draw_cards(DataLoader.get_lootbox(box_id), DataLoader.managers, rng)
		applied["cards"] = drawn
		for mid in drawn.keys():
			if GameState.managers_state.has(mid):
				GameState.managers_state[mid]["cards"] = int(GameState.managers_state[mid].get("cards", 0)) + int(drawn[mid])
				EventBus.manager_obtained.emit(mid, int(drawn[mid]))
	var gems := int(r.get("gems", 0))
	if gems > 0:
		GameState.add_gems(gems)
		applied["gems"] = gems
	(_raw()["claimed"] as Array).append(index)
	return applied

## "2d 14h", "3h 05m", "4m 10s".
static func fmt_left(secs: int) -> String:
	secs = maxi(secs, 0)
	var d := secs / 86400
	var h := (secs % 86400) / 3600
	var mi := (secs % 3600) / 60
	if d > 0:
		return "%dd %dh" % [d, h]
	if h > 0:
		return "%dh %02dm" % [h, mi]
	return "%dm %02ds" % [mi, secs % 60]
