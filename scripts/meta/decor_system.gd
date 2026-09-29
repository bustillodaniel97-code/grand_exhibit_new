extends RefCounted
## DecorSystem — static decor purchase/grant/query logic (SPEC §6.3, §7). No class_name.
##
## BUYING IS PER MUSEUM. PLACING IS FREE ONCE BOUGHT, IN THAT MUSEUM.
##
##   · venue_state[vid].decor_bought — designs paid for in THIS building. A new
##     museum starts empty and stocks its own shelves at its own prices. That is
##     the genre convention (Idle Bank Tycoon rebuilds a new bank from nothing)
##     and it is what makes each venue read as a new setting instead of a reskin.
##   · venue_state[vid].decor[str(slot)] — what is currently STANDING, in slots
##     0..venue.decor_slots-1. Putting a piece in storage frees its slot and
##     costs nothing to undo, because you already paid for it here.
##   · GameState.decor_owned — the historical record across all museums. Not an
##     entitlement: it drives cross-venue SET bonuses (SPEC §7) and lets the shop
##     say "you had this in the Aquarium" so a re-purchase reads as restocking a
##     new hall rather than being charged twice for one object.
##
## The defect this replaced was worse than a pricing question: ownership used to
## be implied by placement, so the next museum showed an empty floor AND a shop
## that looked identical to the one you had just cleared, with no way to tell a
## rule from a bug. Whatever the price rule, the screen has to say it out loud.

## Buy a design for THIS museum and stand it up.
##
## Charges unless the player already bought this piece in this same building —
## in which case it is in local storage and re-placing is free. A piece bought in
## an EARLIER museum confers nothing here: the new hall stocks its own decor.
## event_exclusive pieces are never buyable and arrive via grant_event_decor().
##
## Returns false when the id is unknown or event-exclusive, when the piece is
## already standing here, when every slot is full, or when it cannot be afforded.
static func buy_decor(venue_id: String, decor_id: String) -> bool:
	var def: Dictionary = DataLoader.get_decor(decor_id)
	if def.is_empty() or bool(def.get("event_exclusive", false)):
		return false
	if not stocked_here(venue_id, decor_id) or not unlocked_here(venue_id, decor_id):
		return false
	if owned(venue_id, decor_id):
		return false
	var slot: int = first_free_slot(venue_id)
	if slot < 0:
		return false
	# Charge only if it was not already bought IN THIS MUSEUM. The slot check
	# above stays FIRST so an unaffordable-or-full attempt never takes money.
	if not bought_here(venue_id, decor_id):
		var gems_cost: int = int(def.get("cost_gems", 0))
		if gems_cost > 0:
			if not GameState.spend_gems(gems_cost):
				return false
		else:
			if not GameState.spend_cash(cash_cost(decor_id, venue_id)):
				return false
	_place(venue_id, slot, decor_id)
	return true

# ----------------------------------------------------------------- stock + unlocks
## Themed pieces (a `venues` list) are stocked only by their own museum; the
## rest of the catalogue is sold everywhere. Idle Bank Tycoon themes decor to
## each bank; an aquarium should sell a reef tank, not the Oak Bench only.
static func stocked_here(venue_id: String, decor_id: String) -> bool:
	var venues: Array = DataLoader.get_decor(decor_id).get("venues", [])
	return venues.is_empty() or venue_id in venues

## Themed pieces unlock with this museum's goal milestones, and the shop shows
## them (locked) ahead of time so the next reward is always in view.
static func unlocked_here(venue_id: String, decor_id: String) -> bool:
	var need := int(DataLoader.get_decor(decor_id).get("req_milestones", 0))
	return (GameState.venue_state(venue_id).get("milestones", []) as Array).size() >= need

static func lock_reason(venue_id: String, decor_id: String) -> String:
	if unlocked_here(venue_id, decor_id):
		return ""
	return "Unlocks at goal milestone %d" % int(DataLoader.get_decor(decor_id).get("req_milestones", 0))

# ----------------------------------------------------------------- price + levels
## Decor priced in THIS museum's economy: the authored price is in museum-one
## units and scales by the venue's cost_mult x 10^cost_exp, the same scale its
## upgrades use. Flat prices made the whole catalogue free after museum one.
static func cash_cost(decor_id: String, venue_id: String = "") -> BigNumber:
	var vid := venue_id if venue_id != "" else GameState.current_venue
	var def: Dictionary = DataLoader.get_decor(decor_id)
	var v: Dictionary = DataLoader.get_venue(vid)
	return BigNumber.from_parts(float(def.get("cost_cash_m", 0.0)) * float(v.get("cost_mult", 1.0)),
		int(def.get("cost_cash_e", 0)) + int(v.get("cost_exp", 0)))

const MAX_LEVEL := 10

## Placed decor levels up like a station (Idle Bank Tycoon's decorations are
## department items with levels): each level raises its income bonus and its
## decor points, and pays reputation.
static func level(venue_id: String, decor_id: String) -> int:
	return int((GameState.venue_state(venue_id).get("decor_levels", {}) as Dictionary).get(decor_id, 1))

static func upgrade_cost(venue_id: String, decor_id: String) -> BigNumber:
	var def: Dictionary = DataLoader.get_decor(decor_id)
	var base := cash_cost(decor_id, venue_id)
	if base.is_zero():  # gem and reward pieces level with cash too
		var v: Dictionary = DataLoader.get_venue(venue_id)
		base = BigNumber.from_parts(5.0 * float(v.get("cost_mult", 1.0)) * maxf(1.0, float(def.get("cost_gems", 60)) / 60.0),
			3 + int(v.get("cost_exp", 0)))
	return base.scale(pow(2.4, float(level(venue_id, decor_id))))

static func can_upgrade(venue_id: String, decor_id: String) -> bool:
	return placed_slot(venue_id, decor_id) >= 0 and level(venue_id, decor_id) < MAX_LEVEL

static func upgrade(venue_id: String, decor_id: String) -> bool:
	if not can_upgrade(venue_id, decor_id):
		return false
	if not GameState.spend_cash(upgrade_cost(venue_id, decor_id)):
		return false
	var vs: Dictionary = GameState.venue_state(venue_id)
	var lv: Dictionary = vs.get("decor_levels", {})
	lv[decor_id] = level(venue_id, decor_id) + 1
	vs["decor_levels"] = lv
	GameState.add_reputation(BigNumber.from_float(3.0 + float(lv[decor_id])))
	EventBus.decor_purchased.emit(venue_id, decor_id)
	return true

## Income multiplier of a placed piece at its level: the authored bonus grows
## by 60% of itself per level (oak bench +3% -> +19% at level 10).
static func piece_mult(venue_id: String, decor_id: String) -> float:
	var base := float(DataLoader.get_decor(decor_id).get("income_mult", 1.0)) - 1.0
	return 1.0 + base * (1.0 + 0.6 * float(level(venue_id, decor_id) - 1))

## Stand up a piece already bought in THIS museum — the storage round trip.
## Free, because it was paid for here. Returns false if it was never bought in
## this building, is already standing, or there is no free slot.
static func place_decor(venue_id: String, decor_id: String) -> bool:
	if not bought_here(venue_id, decor_id):
		return false
	if owned(venue_id, decor_id):
		return false
	var slot: int = first_free_slot(venue_id)
	if slot < 0:
		return false
	_place(venue_id, slot, decor_id)
	return true

## Take a piece off this venue's floor, freeing its slot. The DESIGN stays owned
## — no refund, no loss. Without this, free placement would be a one-way trap:
## the first six designs a player placed would hold the slots forever.
static func remove_decor(venue_id: String, decor_id: String) -> bool:
	var vs: Dictionary = GameState.venue_state(venue_id)
	var placed: Dictionary = vs.get("decor", {})
	for key in placed.keys():
		if str(placed[key]) == decor_id:
			placed.erase(key)
			vs["decor"] = placed
			EventBus.decor_purchased.emit(venue_id, decor_id)
			Analytics.log_event("decor_removed",
				{"venue": venue_id, "decor": decor_id, "slot": int(key)})
			return true
	return false

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
	# Anything standing here was, by definition, acquired here — including event
	# grants. Recorded locally so storage can undo it for free, and globally so
	# set bonuses and the "you had this before" hint keep working.
	var bought: Array = vs.get("decor_bought", [])
	if decor_id not in bought:
		bought.append(decor_id)
	vs["decor_bought"] = bought
	GameState.unlock_decor_design(decor_id)
	EventBus.decor_purchased.emit(venue_id, decor_id)
	Analytics.log_event("decor_placed", {"venue": venue_id, "decor": decor_id, "slot": slot})

## Paid for in THIS museum: it is either standing here or in local storage.
static func bought_here(venue_id: String, decor_id: String) -> bool:
	return decor_id in GameState.venue_state(venue_id).get("decor_bought", [])

## Bought in some EARLIER museum but not this one — the shop shows this as a
## familiar piece being restocked, not as a second charge for one object.
static func owned_previously(venue_id: String, decor_id: String) -> bool:
	return GameState.owns_decor_design(decor_id) and not bought_here(venue_id, decor_id)

static func owned(venue_id: String, decor_id: String) -> bool:
	for slot in GameState.venue_state(venue_id).get("decor", {}).values():
		if str(slot) == decor_id:
			return true
	return false

## Which slot this piece occupies in this venue, or -1.
static func placed_slot(venue_id: String, decor_id: String) -> int:
	var placed: Dictionary = GameState.venue_state(venue_id).get("decor", {})
	for key in placed.keys():
		if str(placed[key]) == decor_id:
			return int(key)
	return -1

## The design is unlocked account-wide (set completion is cross-venue, SPEC §7).
## Falls back to a placement scan so state written directly into venues_state —
## legacy saves mid-migration, and tests that poke the dict — still reads as owned.
static func owned_anywhere(decor_id: String) -> bool:
	if GameState.owns_decor_design(decor_id):
		return true
	for vid in GameState.venues_state.keys():
		for slot in GameState.venues_state[vid].get("decor", {}).values():
			if str(slot) == decor_id:
				return true
	return false

## slot_theme -> the venue roles its pieces may stand in, best first.
##
## VenueFloor._decor_room_anchors walks this same list and takes the first role
## the venue actually has, so "gallery" falling through to "exhibit" happens in
## exactly one place. Keeping the rule here is what lets the Decor screen promise
## "this goes in the Grand Gallery" and be right — the old screen said nothing
## about destination, and a piece that lands somewhere unexpected is
## indistinguishable to the player from one that never spawned at all.
static func destination_roles(slot_theme: String) -> Array:
	match slot_theme:
		"hall":
			return ["gallery", "exhibit", "lobby"]
		"entrance":
			return ["lobby"]
		"garden":
			return ["lobby"]
	return ["lobby"]

## The room dict a piece will stand in, resolved against this venue's authored
## rooms. Empty when the venue has none of the candidate roles.
static func destination_room(venue_id: String, slot_theme: String) -> Dictionary:
	var theme: Variant = DataLoader.get_venue(venue_id).get("theme", {})
	if not (theme is Dictionary):
		return {}
	var rooms: Array = (theme as Dictionary).get("rooms", [])
	for want in destination_roles(slot_theme):
		for room in rooms:
			if room is Dictionary and str((room as Dictionary).get("role", "")) == want:
				return room as Dictionary
	return {}

## Player-facing destination for a piece in this venue — the authored room name
## where the venue supplies one, and an honest label for the two lobby edges
## where it does not. Entrance and garden pieces share the lobby room but occupy
## its front and rear edges, so they are named apart rather than both reading
## "Lobby" and looking like a bug.
static func destination_room_name(venue_id: String, decor_id: String) -> String:
	# The venue's authored anchor for THIS slot is where the piece actually goes,
	# so the room is resolved from that point rather than from the slot_theme.
	# Naming it any other way is a promise the floor does not keep, and a piece
	# that turns up somewhere unexpected is indistinguishable from a bug.
	var slot: int = placed_slot(venue_id, decor_id)
	if slot < 0:
		slot = first_free_slot(venue_id)
	var by_anchor: String = _room_name_at_slot(venue_id, slot)
	if by_anchor != "":
		return by_anchor

	var slot_theme: String = str(DataLoader.get_decor(decor_id).get("slot_theme", "hall"))
	if slot_theme == "entrance":
		return "Entrance"
	if slot_theme == "garden":
		return "Grounds"
	var room: Dictionary = destination_room(venue_id, slot_theme)
	var authored: String = str(room.get("name", ""))
	if authored != "":
		return authored.capitalize()
	return "Grand Gallery"

## Which authored room contains this venue's anchor for `slot`, by name.
## "" when the venue authors no anchor for that slot, or no room covers it.
static func _room_name_at_slot(venue_id: String, slot: int) -> String:
	if slot < 0:
		return ""
	var theme: Variant = DataLoader.get_venue(venue_id).get("theme", {})
	if not (theme is Dictionary):
		return ""
	var t: Dictionary = theme
	var anchors: Array = t.get("decor_anchors", [])
	if slot >= anchors.size():
		return ""
	var pt: Variant = anchors[slot]
	if not (pt is Array) or (pt as Array).size() < 2:
		return ""
	var p := Vector2(float(pt[0]), float(pt[1]))
	# Rects and anchors are both authored pre-`layout_spread`, so containment can
	# be tested in raw grid space without reapplying the venue's expansion.
	for entry in t.get("rooms", []):
		if not (entry is Dictionary):
			continue
		var room: Dictionary = entry
		var r: Array = room.get("rect", [])
		if r.size() < 4:
			continue
		var rect := Rect2(float(r[0]), float(r[1]), float(r[2]), float(r[3]))
		if not rect.has_point(p):
			continue
		var named: String = str(room.get("name", ""))
		if named != "":
			return named.capitalize()
		match str(room.get("role", "")):
			"lobby":
				return "Entrance Hall"
			"link":
				continue  # a corridor is not a destination worth naming
			_:
				return str(room.get("role", "")).capitalize()
	return ""

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
		# Levels add a quarter of the piece's points each.
		total += piece_decor_points(str(did)) * (1.0 + 0.25 * float(level(venue_id, str(did)) - 1))
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
	return GameState.cash.gte(cash_cost(decor_id))

static func cost_text(decor_id: String) -> String:
	var def: Dictionary = DataLoader.get_decor(decor_id)
	var gems_cost: int = int(def.get("cost_gems", 0))
	if gems_cost > 0:
		return "%d Gems" % gems_cost
	return "%s Cash" % cash_cost(decor_id).to_notation()
