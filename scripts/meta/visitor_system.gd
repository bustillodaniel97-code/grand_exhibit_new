extends RefCounted
## VisitorSystem — who walks into the museum, by reputation. No class_name.
##
## Reputation unlocks new kinds of visitor (data/visitor_types.json): locals and
## little explorers from the start, then students, tourists, art critics and the
## VIPs (collectors, celebrities, royal patrons). The 3D crowd draws each new
## visitor from the unlocked types by weight and dresses them to match.
##
## VIPs pay tips. While a tip is ready, the next VIP to arrive carries a bubble;
## tapping it pays `tip_seconds` of current income. Then `vip_cooldown_s` must
## pass before another VIP brings one. A VIP who leaves untapped takes nothing
## with them: the tip stays ready for the next.
##
## State (GameState.visitors_state, saved with the game):
##   met        type id -> visitors of that type who have walked in
##   tips       lifetime tips collected
##   tip_ready  unix time the next tip becomes available
##   request    the VIP request in play, or absent (see below)
##
## VIP requests ("VIP tips as quests"): now and then a VIP's bubble is a wish
## instead of a tip, "A collector would love to see the Nature Hall's value at
## level 12". Tapping it accepts; reaching the level before it expires pays
## `tip_mult` times that VIP's tip plus a few gems. The target is the lowest
## upgradeable speed/value track in the museum, `levels_ahead` above where it
## stands, so it always points at something worth doing. One at a time;
## letting it lapse costs nothing. Tuning: visitor_types.json "requests".

static var _cfg: Dictionary = {}

static func config() -> Dictionary:
	if _cfg.is_empty():
		var f := FileAccess.open("res://data/visitor_types.json", FileAccess.READ)
		if f != null:
			var parsed: Variant = JSON.parse_string(f.get_as_text())
			if parsed is Dictionary:
				_cfg = parsed
	return _cfg

static func types() -> Array:
	return config().get("types", [])

static func type_def(id: String) -> Dictionary:
	for t in types():
		if str(t.get("id", "")) == id:
			return t
	return {}

static func is_unlocked(id: String, rep: int = -1) -> bool:
	var t := type_def(id)
	if t.is_empty():
		return false
	return (GameState.rep_level() if rep < 0 else rep) >= int(t.get("rep", 1))

static func unlocked(rep: int = -1) -> Array:
	var r := GameState.rep_level() if rep < 0 else rep
	var out: Array = []
	for t in types():
		if r >= int(t.get("rep", 1)):
			out.append(t)
	return out

## Types that first appear at exactly reputation `level` (the level-up toast).
static func unlocked_at(level: int) -> Array:
	var out: Array = []
	for t in types():
		if int(t.get("rep", 1)) == level:
			out.append(t)
	return out

static func is_vip(id: String) -> bool:
	return bool(type_def(id).get("vip", false))

## Weighted pick among the unlocked types; `roll` in [0, 1).
static func pick(roll: float, rep: int = -1) -> Dictionary:
	var pool := unlocked(rep)
	if pool.is_empty():
		return {}
	var total := 0.0
	for t in pool:
		total += float(t.get("weight", 1.0))
	var at := roll * total
	for t in pool:
		at -= float(t.get("weight", 1.0))
		if at < 0.0:
			return t
	return pool[pool.size() - 1]

## Dress a base look (random outfit from the crowd) as this type.
static func dress(look: Dictionary, t: Dictionary, rng: RandomNumberGenerator) -> Dictionary:
	if t.is_empty() or str(t.get("id", "")) == "local":
		return look
	var acc: Array = []
	for a in t.get("acc", []):
		acc.append(str(a))
	for choice in t.get("acc_any", []):
		var opts: Array = choice
		if not opts.is_empty():
			acc.append(str(opts[rng.randi() % opts.size()]))
	look["acc"] = acc
	var colors: Dictionary = t.get("colors", {})
	for role in colors.keys():
		var opts: Array = colors[role]
		if not opts.is_empty():
			look[role] = str(opts[rng.randi() % opts.size()])
	if t.has("scale"):
		look["scale"] = float(t["scale"])
		if str(look.get("hair", "")) == "#E8E4DC":
			look["hair"] = "#5A3A22"  # no grey-haired little explorers
	elif look.has("scale"):
		look.erase("scale")
	look["type"] = str(t.get("id", ""))
	return look

static func _state() -> Dictionary:
	var s: Dictionary = GameState.visitors_state
	if not s.has("met"):
		s["met"] = {}
		s["tips"] = 0
		s["tip_ready"] = 0
	return s

static func note_arrival(id: String) -> void:
	var met: Dictionary = _state()["met"]
	met[id] = int(met.get(id, 0)) + 1

static func met_count(id: String) -> int:
	return int((_state()["met"] as Dictionary).get(id, 0))

static func tips_collected() -> int:
	return int(_state().get("tips", 0))

static func cooldown() -> int:
	return int(config().get("vip_cooldown_s", 90))

static func tip_ready() -> bool:
	return ClockGuard.now() >= int(_state().get("tip_ready", 0))

static func seconds_to_tip() -> int:
	return maxi(0, int(_state().get("tip_ready", 0)) - ClockGuard.now())

static func tip_value(id: String) -> BigNumber:
	var secs := float(type_def(id).get("tip_seconds", 0))
	return Economy.current_cash_per_second().scale(secs)

## Pay a VIP's tip. Returns the amount (zero if not a VIP or not ready).
static func collect_tip(id: String) -> BigNumber:
	if not is_vip(id) or not tip_ready():
		return BigNumber.zero()
	var amount := tip_value(id)
	GameState.add_cash(amount)
	var s := _state()
	s["tips"] = int(s.get("tips", 0)) + 1
	s["tip_ready"] = ClockGuard.now() + cooldown()
	EventBus.vip_tipped.emit(id, amount)
	return amount

# ------------------------------------------------------------------ requests

const REQUEST_TRACKS: Array[String] = ["speed", "value"]

static func request_config() -> Dictionary:
	return config().get("requests", {})

## Whether the VIP now arriving with a ready bubble brings a wish rather than a
## tip (`roll` in [0, 1)). Never while another request is in play.
static func wants_request(roll: float) -> bool:
	if not active_request().is_empty():
		return false
	return roll < float(request_config().get("chance", 0.0))

## The request in play, or {} (an expired one is cleared here).
static func active_request() -> Dictionary:
	var s := _state()
	var r: Variant = s.get("request", null)
	if not r is Dictionary or (r as Dictionary).is_empty():
		return {}
	if ClockGuard.now() >= int((r as Dictionary).get("until", 0)):
		s.erase("request")
		Analytics.log_event("vip_request_expired", {"type": str((r as Dictionary).get("type", ""))})
		return {}
	return r

## The target for a new request in `venue_id`: the lowest speed/value track
## that still has room, `levels_ahead` above where it stands.
static func pick_target(venue_id: String) -> Dictionary:
	var ahead := maxi(1, int(request_config().get("levels_ahead", 3)))
	var best: Dictionary = {}
	for dept in DataLoader.core.get("departments", {}).keys():
		for track in REQUEST_TRACKS:
			var lv := GameState.dept_level(venue_id, str(dept), track)
			var cap := Economy.track_max_level(venue_id, track)
			if lv >= cap:
				continue
			if best.is_empty() or lv < int(best["level"]):
				best = {"dept": str(dept), "track": track, "level": lv, "target": mini(lv + ahead, cap)}
	return best

## Accept the wish of the VIP of type `type_id`: it becomes the request in
## play, and the VIP bubble goes on its cooldown as a tip would.
static func accept_request(type_id: String) -> Dictionary:
	if not is_vip(type_id) or not tip_ready() or not active_request().is_empty():
		return {}
	var target := pick_target(GameState.current_venue)
	if target.is_empty():
		return {}
	var now := ClockGuard.now()
	var r := {
		"type": type_id, "venue": GameState.current_venue,
		"dept": target["dept"], "track": target["track"], "target": int(target["target"]),
		"from": now, "until": now + int(request_config().get("duration_s", 900)),
	}
	var s := _state()
	s["request"] = r
	s["tip_ready"] = now + cooldown()
	Analytics.log_event("vip_request_accepted", {"type": type_id, "dept": r["dept"], "track": r["track"]})
	return r

static func request_level(r: Dictionary) -> int:
	return GameState.dept_level(str(r.get("venue", "")), str(r.get("dept", "")), str(r.get("track", "")))

static func request_seconds_left(r: Dictionary) -> int:
	return maxi(0, int(r.get("until", 0)) - ClockGuard.now())

## The reward for meeting request `r`: {cash, gems}.
static func request_reward(r: Dictionary) -> Dictionary:
	var type_id := str(r.get("type", ""))
	var mult := float(request_config().get("tip_mult", 5))
	var gems := int((request_config().get("gems", {}) as Dictionary).get(type_id, 0))
	return {"cash": tip_value(type_id).scale(mult), "gems": gems}

## Pay the request in play if its target is reached. Returns the reward
## ({type, cash, gems}) or {} when there is nothing to pay.
static func check_request() -> Dictionary:
	var r := active_request()
	if r.is_empty() or request_level(r) < int(r.get("target", 0)):
		return {}
	var reward := request_reward(r)
	var cash: BigNumber = reward["cash"]
	GameState.add_cash(cash)
	GameState.add_gems(int(reward["gems"]))
	var s := _state()
	s.erase("request")
	s["tips"] = int(s.get("tips", 0)) + 1
	s["requests"] = int(s.get("requests", 0)) + 1
	EventBus.vip_tipped.emit(str(r["type"]), cash)
	Analytics.log_event("vip_request_met", {"type": str(r["type"]), "gems": int(reward["gems"])})
	return {"type": str(r["type"]), "cash": cash, "gems": int(reward["gems"])}

static func requests_met() -> int:
	return int(_state().get("requests", 0))

## "A collector would love to see the Nature Hall's value at level 12."
static func request_text(r: Dictionary) -> String:
	var who := str(TranslationServer.translate(str(type_def(str(r.get("type", ""))).get("one", "A VIP"))))
	var dept := DataLoader.venue_dept_name(str(r.get("venue", "")), str(r.get("dept", "")))
	var template := str(TranslationServer.translate("%s would love to see %s's value at level %d")) \
		if str(r.get("track", "")) == "value" \
		else str(TranslationServer.translate("%s would love to see %s's speed at level %d"))
	return template % [who, dept, int(r.get("target", 0))]

## Short line for the on-screen chip: "Nature Hall value 10/12 · 8:41".
static func request_chip_text(r: Dictionary) -> String:
	var dept := DataLoader.venue_dept_name(str(r.get("venue", "")), str(r.get("dept", "")))
	var left := request_seconds_left(r)
	var template := str(TranslationServer.translate("%s value %d/%d · %d:%02d")) \
		if str(r.get("track", "")) == "value" \
		else str(TranslationServer.translate("%s speed %d/%d · %d:%02d"))
	return template % [dept, request_level(r), int(r.get("target", 0)), left / 60, left % 60]
