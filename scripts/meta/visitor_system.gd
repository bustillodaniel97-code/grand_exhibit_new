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
