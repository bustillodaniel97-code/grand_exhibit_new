extends RefCounted
## DecorSystem — static decor purchase/grant/query logic (SPEC §6.3, §7). No class_name.
## Pieces are placed into per-venue slot indices 0..venue.decor_slots-1, stored as
## venue_state[vid].decor[str(slot)] = decor_id. Set bonuses (all pieces owned across
## ALL venues) are computed by Economy.decor_set_multiplier() — we only manage ownership.

## Buy a decor piece with cash or gems (per def). event_exclusive pieces are NOT
## buyable — they arrive via grant_event_decor(). Returns false when unaffordable,
## already owned in this venue, or all slots are full.
static func buy_decor(venue_id: String, decor_id: String) -> bool:
	var def: Dictionary = DataLoader.get_decor(decor_id)
	if def.is_empty() or bool(def.get("event_exclusive", false)):
		return false
	if owned(venue_id, decor_id):
		return false
	var slot: int = first_free_slot(venue_id)
	if slot < 0:
		return false
	var gems_cost: int = int(def.get("cost_gems", 0))
	if gems_cost > 0:
		if not GameState.spend_gems(gems_cost):
			return false
	else:
		var cost := BigNumber.from_parts(float(def.get("cost_cash_m", 0.0)), int(def.get("cost_cash_e", 0)))
		if not GameState.spend_cash(cost):
			return false
	_place(venue_id, slot, decor_id)
	return true

## Grant an event_exclusive (or any) piece, bypassing cost. venue_id "" = current venue.
static func grant_event_decor(decor_id: String, venue_id: String = "") -> bool:
	if venue_id == "":
		venue_id = GameState.current_venue
	var def: Dictionary = DataLoader.get_decor(decor_id)
	if def.is_empty():
		return false
	if owned(venue_id, decor_id):
		return false
	var slot: int = first_free_slot(venue_id)
	if slot < 0:
		return false
	_place(venue_id, slot, decor_id)
	return true

static func _place(venue_id: String, slot: int, decor_id: String) -> void:
	var vs: Dictionary = GameState.venue_state(venue_id)
	var placed: Dictionary = vs.get("decor", {})
	placed[str(slot)] = decor_id
	vs["decor"] = placed
	EventBus.decor_purchased.emit(venue_id, decor_id)
	Analytics.log_event("decor_placed", {"venue": venue_id, "decor": decor_id, "slot": slot})

static func owned(venue_id: String, decor_id: String) -> bool:
	for slot in GameState.venue_state(venue_id).get("decor", {}).values():
		if str(slot) == decor_id:
			return true
	return false

## Owned in ANY venue (set completion is cross-venue, SPEC §7).
static func owned_anywhere(decor_id: String) -> bool:
	for vid in GameState.venues_state.keys():
		for slot in GameState.venues_state[vid].get("decor", {}).values():
			if str(slot) == decor_id:
				return true
	return false

static func set_progress(set_id: String) -> Dictionary:
	var set_def: Dictionary = DataLoader.decor_sets.get(set_id, {})
	var pieces: Array = set_def.get("pieces", [])
	var have: int = 0
	for pid in pieces:
		if owned_anywhere(str(pid)):
			have += 1
	return {"have": have, "total": pieces.size(),
		"complete": pieces.size() > 0 and have >= pieces.size(),
		"bonus_mult": float(set_def.get("bonus_mult", 1.0)),
		"name": str(set_def.get("name", set_id))}

## --------------------------------------------------------------- satisfaction
## Decor feeds two of the three venue-rating inputs (Economy.venue_satisfaction):
## DECOR POINTS (how impressive the venue looks) and REST SEATS (whether the
## crowd has anywhere to sit). They are separate fields on purpose — a bench run
## is real decor but it is not a showpiece, and a chandelier seats nobody, so the
## player is trading slots between "looks good" and "holds the crowd".

## Decor points for one piece. Defaults to its income bonus in percent so the 18
## pre-satisfaction pieces score sensibly without a data edit; rest-area pieces
## override it because their income bonus is deliberately small.
static func piece_decor_points(decor_id: String) -> float:
	var def: Dictionary = DataLoader.get_decor(decor_id)
	if def.has("decor_score"):
		return float(def["decor_score"])
	var per_mult: float = float(DataLoader.core.get("satisfaction", {}).get("decor", {})
		.get("score_from_income_mult", 100.0))
	return maxf(0.0, (float(def.get("income_mult", 1.0)) - 1.0) * per_mult)

static func piece_rest_seats(decor_id: String) -> int:
	return int(DataLoader.get_decor(decor_id).get("rest_seats", 0))

static func venue_decor_points(venue_id: String) -> float:
	var total: float = 0.0
	for did in GameState.venue_state(venue_id).get("decor", {}).values():
		total += piece_decor_points(str(did))
	return total

## Seats provided by placed decor. The venue's own free floor seating is added by
## Economy (satisfaction.rest.base_seats) — it is a rating constant, not a piece.
static func venue_rest_seats(venue_id: String) -> int:
	var total: int = 0
	for did in GameState.venue_state(venue_id).get("decor", {}).values():
		total += piece_rest_seats(str(did))
	return total

static func first_free_slot(venue_id: String) -> int:
	var total: int = int(DataLoader.get_venue(venue_id).get("decor_slots", 0))
	var placed: Dictionary = GameState.venue_state(venue_id).get("decor", {})
	for i in range(total):
		if not placed.has(str(i)):
			return i
	return -1

static func slots_used(venue_id: String) -> int:
	return GameState.venue_state(venue_id).get("decor", {}).size()

static func slots_total(venue_id: String) -> int:
	return int(DataLoader.get_venue(venue_id).get("decor_slots", 0))

## Affordability check for UI (does not spend).
static func can_afford(decor_id: String) -> bool:
	var def: Dictionary = DataLoader.get_decor(decor_id)
	var gems_cost: int = int(def.get("cost_gems", 0))
	if gems_cost > 0:
		return GameState.gems >= gems_cost
	var cost := BigNumber.from_parts(float(def.get("cost_cash_m", 0.0)), int(def.get("cost_cash_e", 0)))
	return GameState.cash.gte(cost)

static func cost_text(decor_id: String) -> String:
	var def: Dictionary = DataLoader.get_decor(decor_id)
	var gems_cost: int = int(def.get("cost_gems", 0))
	if gems_cost > 0:
		return "%d Gems" % gems_cost
	var cost := BigNumber.from_parts(float(def.get("cost_cash_m", 0.0)), int(def.get("cost_cash_e", 0)))
	return "%s Cash" % cost.to_notation()
