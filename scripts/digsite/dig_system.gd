extends RefCounted
## DigSystem — the Dig Site mini game's state and rewards. No class_name.
##
## Each museum has an excavation site themed on its collection
## (data/dig_sites.json). Swings cost energy, which refills over time, from an
## ad, or for gems. Digging turns up coins (a slice of museum income), gems and
## energy crystals; recovering the site's artifact adds it to THAT museum's
## collection, which raises its income (x quality) and completes toward a set.
##
## State (GameState.dig_state, saved with the game):
##   energy, energy_t   stored energy and the unix time it was last settled
##   sites              venue -> current site dict (DigLogic)
##   collection         venue -> {artifact id: best quality 1..3}
##   swings             lifetime swings (stats / quests)

const DigLogic := preload("res://scripts/digsite/dig_logic.gd")

static var _cfg: Dictionary = {}

static func config() -> Dictionary:
	if _cfg.is_empty():
		var f := FileAccess.open("res://data/dig_sites.json", FileAccess.READ)
		if f != null:
			var parsed: Variant = JSON.parse_string(f.get_as_text())
			if parsed is Dictionary:
				_cfg = parsed
	return _cfg

static func site_def(venue_id: String) -> Dictionary:
	var sites: Dictionary = config().get("sites", {})
	return sites.get(venue_id, sites.get("whispering_pines", {}))

static func artifacts(venue_id: String) -> Array:
	return site_def(venue_id).get("artifacts", [])

static func artifact(venue_id: String, art_id: String) -> Dictionary:
	for a in artifacts(venue_id):
		if str(a.get("id", "")) == art_id:
			return a
	return {}

static func _state() -> Dictionary:
	var s: Dictionary = GameState.dig_state
	if not s.has("energy"):
		s["energy"] = float((config().get("energy", {}) as Dictionary).get("start", 30))
		s["energy_t"] = _now()
		s["sites"] = {}
		s["collection"] = {}
		s["swings"] = 0
	return s

static func _now() -> int:
	return int(Time.get_unix_time_from_system())

# ----------------------------------------------------------------- energy

static func max_energy() -> int:
	return int((config().get("energy", {}) as Dictionary).get("max", 30))

static func regen_seconds() -> int:
	return maxi(1, int((config().get("energy", {}) as Dictionary).get("regen_seconds", 150)))

## Bank regenerated energy up to the cap. Time past the cap is not banked.
static func settle_energy() -> void:
	var s := _state()
	var e := float(s["energy"])
	var now := _now()
	var elapsed := maxi(0, now - int(s.get("energy_t", now)))
	if e >= float(max_energy()):
		s["energy_t"] = now
		return
	var gained := elapsed / regen_seconds()
	if gained > 0:
		e = minf(float(max_energy()), e + float(gained))
		s["energy_t"] = int(s["energy_t"]) + gained * regen_seconds() if e < float(max_energy()) else now
		s["energy"] = e

static func energy() -> int:
	settle_energy()
	return int(_state()["energy"])

## Seconds until the next point of energy (0 when full).
static func next_energy_in() -> int:
	settle_energy()
	var s := _state()
	if float(s["energy"]) >= float(max_energy()):
		return 0
	return regen_seconds() - (_now() - int(s["energy_t"])) % regen_seconds()

static func add_energy(n: int) -> void:
	settle_energy()
	var s := _state()
	# Refills may overfill a little (a crystal found at full energy is not wasted).
	s["energy"] = float(s["energy"]) + float(n)

static func refill_with_gems() -> bool:
	var cost := int((config().get("energy", {}) as Dictionary).get("gem_refill_cost", 20))
	if energy() >= max_energy() or not GameState.spend_gems(cost):
		return false
	_state()["energy"] = float(max_energy())
	return true

static func ad_refill_amount() -> int:
	return int((config().get("energy", {}) as Dictionary).get("ad_refill", 15))

# ----------------------------------------------------------------- sites

## The museum's current site, created on first visit. Sites persist until
## their artifact is recovered, so a half-dug pit waits for your energy.
static func current_site(venue_id: String) -> Dictionary:
	var sites: Dictionary = _state()["sites"]
	if not sites.has(venue_id):
		sites[venue_id] = _new_site(venue_id)
	return sites[venue_id]

## Start the next site once the current one is recovered.
static func next_site(venue_id: String) -> Dictionary:
	var sites: Dictionary = _state()["sites"]
	sites[venue_id] = _new_site(venue_id)
	return sites[venue_id]

## Uncollected artifacts first (rarest last), then the lowest-quality one so
## a cracked find can be re-dug for three stars.
static func _new_site(venue_id: String) -> Dictionary:
	var owned: Dictionary = collection(venue_id)
	var pool: Array = []
	for a in artifacts(venue_id):
		if not owned.has(str(a["id"])):
			pool.append(a)
	var order := {"common": 0, "rare": 1, "epic": 2}
	pool.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(order.get(str(a.get("rarity", "common")), 0)) < int(order.get(str(b.get("rarity", "common")), 0)))
	var pick: Dictionary = pool[0] if not pool.is_empty() else {}
	if pick.is_empty():
		var worst := 4
		for a in artifacts(venue_id):
			var q := int(owned.get(str(a["id"]), 0))
			if q < worst:
				worst = q
				pick = a
	var s := _state()
	var seed_value := hash("%s:%d:%d" % [venue_id, int(s.get("swings", 0)), _now()])
	return DigLogic.generate(venue_id, pick, config(), seed_value)

## Swing at a cell. Spends energy only when something was actually dug.
## Returns DigLogic.dig's result plus {energy, reward_cash (BigNumber), gems}.
static func swing(venue_id: String, x: int, y: int, tool: String) -> Dictionary:
	var site := current_site(venue_id)
	var cost := int((config().get("tools", {}) as Dictionary).get(tool, {}).get("cost", 1))
	if energy() < cost:
		return {"ok": false, "reason": "energy"}
	var res: Dictionary = DigLogic.dig(site, x, y, tool, config())
	if not bool(res["ok"]):
		return res
	var s := _state()
	s["energy"] = float(s["energy"]) - float(cost)
	if float(s["energy"]) < float(max_energy()) and float(s["energy"]) + float(cost) >= float(max_energy()):
		s["energy_t"] = _now()  # the regen clock starts when you drop below full
	s["swings"] = int(s.get("swings", 0)) + 1
	var find: Dictionary = res["find"]
	if not find.is_empty():
		match str(find["kind"]):
			"coins":
				var secs := float((config().get("finds", {}) as Dictionary).get("coin_income_seconds", 30))
				var rate: BigNumber = Economy.venue_rates(venue_id).get("banked_per_s", BigNumber.zero())
				var cash := rate.scale(secs)
				if cash.lt(BigNumber.from_float(5.0)):
					cash = BigNumber.from_float(5.0)
				GameState.add_cash(cash)
				res["reward_cash"] = cash
			"gems":
				GameState.add_gems(int(find["amount"]))
				res["gems"] = int(find["amount"])
			"crystals":
				add_energy(int(find["amount"]))
	if bool(res["complete"]):
		res.merge(_recover(venue_id, site))
	return res

static func _recover(venue_id: String, site: Dictionary) -> Dictionary:
	var art_id := str(site["artifact"])
	var q := DigLogic.quality(site)
	var col: Dictionary = collection(venue_id)
	var first := not col.has(art_id)
	var better := q > int(col.get(art_id, 0))
	if better:
		col[art_id] = q
	var def := artifact(venue_id, art_id)
	var gems := 0
	if first:
		gems = int((config().get("rewards", {}) as Dictionary).get("gems_by_rarity", {}).get(str(def.get("rarity", "common")), 5))
		GameState.add_gems(gems)
	EventBus.artifact_recovered.emit(venue_id, art_id, q)
	Analytics.log_event("artifact_recovered", {"venue": venue_id, "artifact": art_id, "quality": q, "first": first})
	return {"artifact": art_id, "quality": q, "first": first, "improved": better, "bonus_gems": gems}

# ----------------------------------------------------------------- collection

static func collection(venue_id: String) -> Dictionary:
	var all: Dictionary = _state()["collection"]
	if not all.has(venue_id):
		all[venue_id] = {}
	return all[venue_id]

static func set_complete(venue_id: String) -> bool:
	return collection(venue_id).size() >= artifacts(venue_id).size() and not artifacts(venue_id).is_empty()

## The museum's collection bonus: each artifact adds income_bonus x quality/3,
## and the full set adds set_bonus on top.
static func income_mult(venue_id: String) -> float:
	if not GameState.dig_state.has("collection"):
		return 1.0
	var rew: Dictionary = config().get("rewards", {})
	var per := float(rew.get("income_bonus", 0.04))
	var bonus := 0.0
	for q in (GameState.dig_state["collection"] as Dictionary).get(venue_id, {}).values():
		bonus += per * float(q) / 3.0
	if set_complete(venue_id):
		bonus += float(rew.get("set_bonus", 0.15))
	return 1.0 + bonus
