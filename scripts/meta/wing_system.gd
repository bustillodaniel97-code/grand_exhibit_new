extends RefCounted
## WingSystem — the parts of a museum that open while you play it. No class_name.
##
## Idle Bank Tycoon grows a bank mid-level: rooms that are not open yet are
## visibly there but derelict, the next one always shows what it needs, and
## renovating it is the reward. Here a WING is usually a whole floor (2F, 3F),
## or the exterior (the gilded facade). Data: data/wings.json.
##
## State lives in venue_state[vid]:
##   wings        ids renovated in this museum, in the order they were bought
##
## Effects are read by Economy (income_multiplier, track_max_level, max_staff)
## and by PrestigeSystem (every wing must be open before the museum is complete).
## The grandeur tier (Humble -> Legendary) is 1 + wings renovated and is what the
## 3D exterior dresses itself from.

const STATUS_OPEN := "open"
const STATUS_READY := "ready"     # requirements met, can be bought
const STATUS_LOCKED := "locked"   # requirements not met yet

static var _data: Dictionary = {}
static var _cache: Dictionary = {}  # vid -> Array of wing defs

static func data() -> Dictionary:
	if _data.is_empty():
		var f := FileAccess.open("res://data/wings.json", FileAccess.READ)
		if f != null:
			var parsed: Variant = JSON.parse_string(f.get_as_text())
			if parsed is Dictionary:
				_data = parsed
	return _data

## Every wing of a venue in unlock order, core ground floor excluded.
static func wings(venue_id: String) -> Array:
	if _cache.has(venue_id):
		return _cache[venue_id]
	var authored: Variant = data().get("venues", {}).get(venue_id)
	var out: Array = []
	if authored is Array:
		out = (authored as Array).duplicate(true)
	else:
		out = _auto_wings(venue_id)
	_cache[venue_id] = out
	return out

## Venues without authored wings: one per upper storey of their theme, then the
## gilded facade. The storeys already exist in the 2D data; this makes them
## unlock in order instead of being open from the first second.
static func _auto_wings(venue_id: String) -> Array:
	var auto: Dictionary = data().get("auto", {})
	var theme: Dictionary = DataLoader.get_venue(venue_id).get("theme", {})
	var by_level := {}
	for room in theme.get("rooms", []):
		var lv := int((room as Dictionary).get("level", 0))
		if lv >= 1:
			if not by_level.has(lv):
				by_level[lv] = []
			(by_level[lv] as Array).append(str(room.get("id", "")))
	var names: Array = auto.get("floor_names", [])
	var reqs: Array = auto.get("req_milestones_by_floor", [0, 1, 2, 3])
	var secs: Array = auto.get("price_seconds_by_floor", [0, 300, 600, 900])
	var mins: Array = auto.get("min_cost_by_floor", [[0, 0], [2, 3], [1, 6], [1, 8]])
	var levels: Array = by_level.keys()
	levels.sort()
	var out: Array = []
	for lv in levels:
		var i := mini(int(lv), names.size() - 1)
		out.append({
			"id": "floor_%d" % int(lv), "name": str(names[i]), "floor": int(lv),
			"label": "%dF" % (int(lv) + 1), "rooms": by_level[lv],
			"req_milestones": int(reqs[mini(int(lv), reqs.size() - 1)]),
			"price_seconds": float(secs[mini(int(lv), secs.size() - 1)]),
			"min_cost": mins[mini(int(lv), mins.size() - 1)],
			"income_mult": float(auto.get("income_mult", 1.4)),
			"staff_bonus": auto.get("staff_bonus", {}),
			"cap_bonus_frac": float(auto.get("cap_bonus_frac", 0.25)),
			"blurb": "Open the %s: more rooms, more exhibits, more visitors." % str(names[i]).to_lower(),
		})
	var facade: Dictionary = (auto.get("facade", {}) as Dictionary).duplicate(true)
	if not facade.is_empty():
		out.append(facade)
	return out

static func wing(venue_id: String, wing_id: String) -> Dictionary:
	for w in wings(venue_id):
		if str(w.get("id", "")) == wing_id:
			return w
	return {}

# ----------------------------------------------------------------- state

static func renovated(venue_id: String) -> Array:
	return GameState.venue_state(venue_id).get("wings", [])

static func is_open(venue_id: String, wing_id: String) -> bool:
	return wing_id in renovated(venue_id)

static func requirement_met(venue_id: String, w: Dictionary) -> bool:
	var done: int = (GameState.venue_state(venue_id).get("milestones", []) as Array).size()
	return done >= int(w.get("req_milestones", 0))

static func status(venue_id: String, wing_id: String) -> String:
	if is_open(venue_id, wing_id):
		return STATUS_OPEN
	var w := wing(venue_id, wing_id)
	if w.is_empty():
		return STATUS_LOCKED
	return STATUS_READY if requirement_met(venue_id, w) else STATUS_LOCKED

## "Complete 2 goals" style text for the next thing the player must do.
static func requirement_text(venue_id: String, w: Dictionary) -> String:
	var need := int(w.get("req_milestones", 0))
	var done: int = (GameState.venue_state(venue_id).get("milestones", []) as Array).size()
	if done >= need:
		return "Ready to renovate"
	return "Reach goal milestone %d (%d / %d)" % [need, done, need]

## The next wing that is not open yet, or {} when the museum is fully built.
static func next_wing(venue_id: String) -> Dictionary:
	for w in wings(venue_id):
		if not is_open(venue_id, str(w.get("id", ""))):
			return w
	return {}

## Price of renovating: price_seconds of this museum's current banked income,
## never below the wing's floor. A museum's income can grow a thousandfold in
## minutes, so a price fixed when the wing unlocked was trivial by the time the
## player looked at it; a live price is always "about N minutes of saving".
static func price(venue_id: String, wing_id: String) -> BigNumber:
	var w := wing(venue_id, wing_id)
	if w.is_empty():
		return BigNumber.zero()
	var venue: Dictionary = DataLoader.get_venue(venue_id)
	var mc: Array = w.get("min_cost", [1, 3])
	var floor_cost := BigNumber.from_parts(float(mc[0]) * float(venue.get("cost_mult", 1.0)),
		int(mc[1]) + int(venue.get("cost_exp", 0)))
	var rates: Dictionary = Economy.venue_rates(venue_id)
	var income: BigNumber = rates.get("banked_per_s", BigNumber.zero())
	var by_income: BigNumber = income.scale(float(w.get("price_seconds", 300.0)))
	return by_income if floor_cost.lt(by_income) else floor_cost

## Pay for and open a wing. Returns false when it is already open, its
## requirement is not met, or it cannot be afforded.
static func renovate(venue_id: String, wing_id: String) -> bool:
	if status(venue_id, wing_id) != STATUS_READY:
		return false
	# Wings open in order: the building grows floor by floor.
	var nxt := next_wing(venue_id)
	if str(nxt.get("id", "")) != wing_id:
		return false
	if not GameState.spend_cash(price(venue_id, wing_id)):
		return false
	var vs: Dictionary = GameState.venue_state(venue_id)
	var done: Array = vs.get("wings", [])
	done.append(wing_id)
	vs["wings"] = done
	# Renovation is a big purchase; it counts toward the player's level.
	GameState.add_reputation(BigNumber.from_float(25.0 * float(done.size())))
	EventBus.wing_renovated.emit(venue_id, wing_id)
	Analytics.log_event("wing_renovated", {"venue": venue_id, "wing": wing_id,
		"tier": grandeur_tier(venue_id)})
	return true

# ----------------------------------------------------------------- effects

static func income_mult(venue_id: String) -> float:
	var mult := 1.0
	for id in renovated(venue_id):
		mult *= float(wing(venue_id, str(id)).get("income_mult", 1.0))
	return mult

static func staff_bonus(venue_id: String, dept_id: String) -> int:
	var n := 0
	for id in renovated(venue_id):
		n += int((wing(venue_id, str(id)).get("staff_bonus", {}) as Dictionary).get(dept_id, 0))
	return n

## Extra speed/value track levels from renovated wings. `base_cap` is the
## venue's own track_level_cap, which cap_bonus_frac is taken from.
static func cap_bonus(venue_id: String, base_cap: int) -> int:
	var n := 0
	for id in renovated(venue_id):
		var w := wing(venue_id, str(id))
		if w.has("cap_bonus"):
			n += int(w["cap_bonus"])
		else:
			n += int(round(float(base_cap) * float(w.get("cap_bonus_frac", 0.0))))
	return n

static func all_open(venue_id: String) -> bool:
	return next_wing(venue_id).is_empty()

static func open_count(venue_id: String) -> int:
	return renovated(venue_id).size()

# ----------------------------------------------------------------- grandeur

static func grandeur_names() -> Array:
	return data().get("grandeur", [])

## 1 (Humble) .. 5 (Legendary): one step per renovated wing.
static func grandeur_tier(venue_id: String) -> int:
	return clampi(1 + open_count(venue_id), 1, maxi(grandeur_names().size(), 1))

static func grandeur_name(venue_id: String) -> String:
	var names := grandeur_names()
	var t := grandeur_tier(venue_id)
	return str((names[t - 1] as Dictionary).get("name", "")) if t - 1 < names.size() else ""

## Upper floors with a 3D layout, in floor order (for the 3D view).
static func floor_layouts(venue_id: String) -> Array:
	var out: Array = []
	for w in wings(venue_id):
		if (w as Dictionary).has("layout"):
			out.append(w)
	return out
