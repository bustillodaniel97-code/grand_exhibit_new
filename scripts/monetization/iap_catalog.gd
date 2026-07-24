extends RefCounted
## iap_catalog.gd — purchase layer over IAPService. Applies catalog grants on success.
##
## Usage: const IAPCat := preload("res://scripts/monetization/iap_catalog.gd")
## Flow: purchase(id) -> limit_per_day check (state in GameState.rv_state["iap_"+id]
## with day rollover) -> Analytics.iap_funnel("initiate") -> IAPService.purchase ->
## IAPService.iap_result(success) -> apply_grants -> EventBus.iap_completed +
## Analytics.iap_funnel("complete"). Debug build: IAPService always succeeds (SPEC §8).

static var _connected: bool = false

static func _ensure_connected() -> void:
	if _connected:
		return
	_connected = true
	IAPService.iap_result.connect(_on_iap_result)

static func _today() -> String:
	return Time.get_date_string_from_unix_time(ClockGuard.now())

## Daily purchase-count state for a product, with day rollover.
static func _limit_state(product_id: String) -> Dictionary:
	var key: String = "iap_" + product_id
	var today: String = _today()
	var st: Dictionary = GameState.rv_state.get(key, {})
	if str(st.get("day", "")) != today:
		st = {"count": 0, "day": today, "ready_at": 0}
		GameState.rv_state[key] = st
	return st

static func purchases_left_today(product_id: String) -> int:
	var def: Dictionary = DataLoader.get_iap(product_id)
	var limit: int = int(def.get("limit_per_day", 0))
	if limit <= 0:
		return -1  # unlimited
	return maxi(0, limit - int(_limit_state(product_id).get("count", 0)))

# ------------------------------------------------------------------- purchase

static func purchase(product_id: String) -> bool:
	_ensure_connected()
	var def: Dictionary = DataLoader.get_iap(product_id)
	if def.is_empty():
		push_warning("iap_catalog: unknown product " + product_id)
		return false
	var left: int = purchases_left_today(product_id)
	if left == 0:
		EventBus.toast_requested.emit("Daily purchase limit reached")
		Analytics.iap_funnel("limit_blocked", product_id)
		return false
	Analytics.iap_funnel("initiate", product_id)
	IAPService.purchase(product_id)
	return true

static func _on_iap_result(product_id: String, success: bool) -> void:
	if not success:
		Analytics.iap_funnel("failed", product_id)
		EventBus.toast_requested.emit("Purchase failed — please try again")
		return
	var grants: Dictionary = apply_grants(product_id)
	if grants.is_empty():
		return  # unknown product; nothing granted, nothing counted
	var st: Dictionary = _limit_state(product_id)
	st["count"] = int(st.get("count", 0)) + 1
	EventBus.iap_completed.emit(product_id)
	Analytics.iap_funnel("complete", product_id)

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
