extends RefCounted
## iap_catalog.gd — purchase layer over IAPService. Applies catalog grants on success.
##
## Usage: const IAPCat := preload("res://scripts/monetization/iap_catalog.gd")
## Flow: purchase(id) -> reserve a limit_per_day slot + claim the in-flight lock ->
## Analytics.iap_funnel("initiate") -> IAPService.purchase ->
## IAPService.iap_result(success, receipt) -> receipt token deduped -> apply_grants ->
## EventBus.iap_completed + Analytics.iap_funnel("complete").
##
## Two races this closes, both of which paid out real currency:
##  · limit_per_day was read at purchase() but only incremented after the async
##    round trip, so four taps on a limit-1 product all passed the check and granted
##    four times. The slot is now reserved up front and released only on failure.
##  · Nothing deduped the result. Play Billing re-delivers unacknowledged purchases
##    on the next query, so the same purchase token can arrive twice through no fault
##    of the player. Grants are now idempotent on the token.
##
## State (all under GameState.rv_state, day-rolled on MonoClock's guarded day so a
## device-clock change cannot reset a purchase limit):
##   rv_state["iap_<id>"]        = {count:int, day:"YYYY-MM-DD", ready_at:int}
##   rv_state["_iap_receipts"]   = Array[String] of redeemed purchase tokens

const MonoClock := preload("res://scripts/monetization/mono_clock.gd")
const Entitlements := preload("res://scripts/monetization/entitlements.gd")

## Redeemed-token ring. Bounded because it rides in the save file; a real client
## only needs enough history to cover the store's re-delivery window.
const RECEIPTS_KEY := "_iap_receipts"
const RECEIPTS_MAX := 64

static var _connected: bool = false
## product_id -> true while a purchase is in flight. Claimed synchronously in
## purchase(), which is what makes repeat taps inside the round trip a no-op.
static var _in_flight: Dictionary = {}

static func _ensure_connected() -> void:
	if _connected:
		return
	_connected = true
	IAPService.iap_result.connect(_on_iap_result)
	IAPService.restore_completed.connect(_on_restore_completed)

static func _today() -> String:
	return MonoClock.today()

## Daily purchase-count state for a product, with day rollover.
static func _limit_state(product_id: String) -> Dictionary:
	var key: String = "iap_" + product_id
	var today: String = _today()
	var st: Variant = GameState.rv_state.get(key, null)
	if typeof(st) != TYPE_DICTIONARY or str((st as Dictionary).get("day", "")) != today:
		st = {"count": 0, "day": today, "ready_at": 0}
		GameState.rv_state[key] = st
	return st

static func purchases_left_today(product_id: String) -> int:
	var def: Dictionary = DataLoader.get_iap(product_id)
	var limit: int = int(def.get("limit_per_day", 0))
	if limit <= 0:
		return -1  # unlimited
	return maxi(0, limit - int(_limit_state(product_id).get("count", 0)))

static func is_in_flight(product_id: String) -> bool:
	return bool(_in_flight.get(product_id, false))

## A non-consumable already owned cannot be bought again.
static func is_owned(product_id: String) -> bool:
	return str(DataLoader.get_iap(product_id).get("entitlement", "")) != "" \
		and Entitlements.owns(product_id)

## Why this product cannot be bought right now, or "" when it can.
static func blocked_reason(product_id: String) -> String:
	if is_in_flight(product_id):
		return "in_flight"
	if is_owned(product_id):
		return "owned"
	if purchases_left_today(product_id) == 0:
		return "daily_limit"
	return ""

static func blocked_message(product_id: String) -> String:
	match blocked_reason(product_id):
		"in_flight":
			return "Purchase already in progress"
		"owned":
			return "You already own this"
		"daily_limit":
			return "Daily purchase limit reached — back tomorrow"
		_:
			return ""

# ------------------------------------------------------------------- purchase

static func purchase(product_id: String) -> bool:
	_ensure_connected()
	var def: Dictionary = DataLoader.get_iap(product_id)
	if def.is_empty():
		push_warning("iap_catalog: unknown product " + product_id)
		return false
	var reason: String = blocked_reason(product_id)
	if reason != "":
		EventBus.toast_requested.emit(blocked_message(product_id))
		Analytics.iap_funnel("limit_blocked" if reason == "daily_limit" else "inflight_blocked",
			product_id, {"reason": reason})
		return false
	# Reserve BEFORE the async round trip. Released in _release() on any failure.
	_in_flight[product_id] = true
	_reserve_slot(product_id)
	Analytics.iap_funnel("initiate", product_id, {"price": str(def.get("price_usd", ""))})
	IAPService.purchase(product_id)
	return true

## Counted for every product, not just limited ones: the daily count is also what
## the store reads to say "bought today", and analytics wants it regardless.
static func _reserve_slot(product_id: String) -> void:
	var st: Dictionary = _limit_state(product_id)
	st["count"] = int(st.get("count", 0)) + 1

static func _release_slot(product_id: String) -> void:
	var st: Dictionary = _limit_state(product_id)
	st["count"] = maxi(0, int(st.get("count", 0)) - 1)

static func _on_iap_result(product_id: String, success: bool, receipt: Dictionary) -> void:
	_in_flight.erase(product_id)
	if not success:
		_release_slot(product_id)
		Analytics.iap_funnel("failed", product_id, {"reason": str(receipt.get("reason", "unknown"))})
		EventBus.toast_requested.emit("Purchase failed — please try again")
		return
	var token: String = str(receipt.get("purchase_token", ""))
	if not _redeem_receipt(token):
		# Re-delivery of something already granted. Acknowledge, grant nothing.
		Analytics.iap_funnel("duplicate_receipt", product_id, {"token": token})
		return
	var grants: Dictionary = apply_grants(product_id)
	if grants.is_empty() and str(DataLoader.get_iap(product_id).get("entitlement", "")) == "":
		_release_slot(product_id)
		return  # unknown product; nothing granted, nothing counted
	Entitlements.record_purchase(product_id)
	EventBus.iap_completed.emit(product_id)
	Analytics.iap_funnel("complete", product_id, {"order": str(receipt.get("order_id", ""))})

## True the first time a purchase token is seen. An empty token (a direct
## apply_grants call, or a stub with no receipt) is always allowed through — the
## dedupe protects against store re-delivery, not against internal callers.
static func _redeem_receipt(token: String) -> bool:
	if token == "":
		return true
	var seen: Variant = GameState.rv_state.get(RECEIPTS_KEY, null)
	if typeof(seen) != TYPE_ARRAY:
		seen = []
		GameState.rv_state[RECEIPTS_KEY] = seen
	var arr: Array = seen
	if token in arr:
		return false
	arr.append(token)
	while arr.size() > RECEIPTS_MAX:
		arr.remove_at(0)
	return true

static func _on_restore_completed(product_ids: Array) -> void:
	var added: int = Entitlements.restore(product_ids)
	Analytics.iap_funnel("restore", "", {"restored": added, "reported": product_ids.size()})
	if added > 0:
		EventBus.toast_requested.emit("Purchases restored")
	else:
		EventBus.toast_requested.emit("Nothing to restore")

static func restore_purchases() -> void:
	_ensure_connected()
	IAPService.restore_purchases()

# --------------------------------------------------------------------- grants
# Public so tests can simulate a successful purchase directly.
# Returns a summary Dictionary ({} when the product id is unknown).

static func apply_grants(product_id: String) -> Dictionary:
	var def: Dictionary = DataLoader.get_iap(product_id)
	if def.is_empty():
		push_warning("iap_catalog: unknown product " + product_id)
		return {}
	var g: Dictionary = def.get("grants", {})
	var summary: Dictionary = {}
	var gems: int = int(g.get("gems", 0))
	if gems > 0:
		GameState.add_gems(gems)
		summary["gems"] = gems
	var cash_seconds: float = float(g.get("cash_seconds", 0))
	if cash_seconds > 0.0:
		var cash_amount: BigNumber = Economy.current_cash_per_second().scale(cash_seconds)
		GameState.add_cash(cash_amount)
		summary["cash"] = cash_amount.to_save()
		summary["cash_seconds"] = cash_seconds
	var insight_m: float = float(g.get("insight_m", 0.0))
	if insight_m > 0.0:
		var insight_amount := BigNumber.from_parts(insight_m, int(g.get("insight_e", 0)))
		GameState.add_insight(insight_amount)
		summary["insight"] = insight_amount.to_save()
	var box_id: String = str(g.get("box", ""))
	if box_id != "":
		summary["box"] = draw_box(box_id)
	return summary

## Local card-draw helper over shared data (DataLoader.lootboxes + DataLoader.managers).
## The managers branch owns the full lootbox opening screen; this is a minimal,
## self-contained draw used only for IAP bundle "box" grants, per mission brief:
## - draws box.cards_total cards; each card rolls a rarity via box.rarity_weights,
##   then picks uniformly among managers of that rarity (fallback: any manager).
## - also applies the box's flat gems_bonus / insight_bonus_m bonuses.
## - cards land directly in GameState.managers_state and lootbox_opened is emitted.
static func draw_box(box_id: String) -> Dictionary:
	var box: Dictionary = DataLoader.get_lootbox(box_id)
	if box.is_empty():
		push_warning("iap_catalog: unknown box " + box_id)
		return {}
	var weights: Dictionary = box.get("rarity_weights", {})
	var by_rarity: Dictionary = {}
	for mid in DataLoader.managers.keys():
		var r: String = str(DataLoader.managers[mid].get("rarity", "common"))
		if not by_rarity.has(r):
			by_rarity[r] = []
		by_rarity[r].append(mid)
	var all_ids: Array = DataLoader.managers.keys()
	var cards: Dictionary = {}
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var total: int = int(box.get("cards_total", 1))
	for i in range(total):
		var rarity: String = _roll_rarity(weights, rng)
		var pool: Array = by_rarity.get(rarity, [])
		if pool.is_empty():
			pool = all_ids
		if pool.is_empty():
			break
		var mid: String = str(pool[rng.randi_range(0, pool.size() - 1)])
		cards[mid] = int(cards.get(mid, 0)) + 1
	var results: Dictionary = {"box_id": box_id, "cards": cards}
	for mid in cards.keys():
		if not GameState.managers_state.has(mid):
			GameState.managers_state[mid] = {"cards": 0, "level": 1, "rank": 1, "assigned_to": ""}
		GameState.managers_state[mid]["cards"] = int(GameState.managers_state[mid]["cards"]) + int(cards[mid])
		EventBus.manager_obtained.emit(mid, int(cards[mid]))
	var gems_bonus: int = int(box.get("gems_bonus", 0))
	if gems_bonus > 0:
		GameState.add_gems(gems_bonus)
		results["gems"] = gems_bonus
	var insight_bonus: float = float(box.get("insight_bonus_m", 0.0))
	if insight_bonus > 0.0:
		var b := BigNumber.from_float(insight_bonus)
		GameState.add_insight(b)
		results["insight"] = b.to_save()
	EventBus.lootbox_opened.emit(box_id, results)
	return results

static func _roll_rarity(weights: Dictionary, rng: RandomNumberGenerator) -> String:
	var roll: float = rng.randf()
	var acc: float = 0.0
	for rarity in ["legendary", "epic", "rare", "common"]:
		acc += float(weights.get(rarity, 0.0))
		if roll <= acc:
			return rarity
	return "common"
