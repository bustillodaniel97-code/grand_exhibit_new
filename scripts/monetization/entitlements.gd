extends RefCounted
## entitlements.gd — what the player owns forever, as opposed to what they consumed.
##
## Consumables (gems, cash packs) are spent on arrival and need no record. A
## non-consumable — here the ad-free upgrade — has to survive a reinstall, which
## means it needs both a local record and a restore path (IAPService.restore_purchases).
##
## Also the one place that knows whether this player has ever paid, which is what
## gates the first-purchase offer. Storing it as a count rather than a bool keeps
## the "starter offer" surface honest: it disappears the moment it is used.
##
## State: GameState.rv_state["entitlements"] =
##   {owned: Array[String], purchases: int, first_purchase_unix: int}

const MonoClock := preload("res://scripts/monetization/mono_clock.gd")

const STATE_KEY := "entitlements"

static func _st() -> Dictionary:
	var st: Variant = GameState.rv_state.get(STATE_KEY, null)
	if typeof(st) != TYPE_DICTIONARY:
		st = {"owned": [], "purchases": 0, "first_purchase_unix": 0}
		GameState.rv_state[STATE_KEY] = st
	if not st.has("owned"):
		st["owned"] = []
	return st

static func owns(product_id: String) -> bool:
	return product_id in _st().get("owned", [])

## The ad-free upgrade. Every ad surface asks this before it costs the player time.
static func no_ads() -> bool:
	for pid in _st().get("owned", []):
		if str(DataLoader.get_iap(str(pid)).get("entitlement", "")) == "no_ads":
			return true
	return false

static func purchase_count() -> int:
	return int(_st().get("purchases", 0))

static func has_ever_purchased() -> bool:
	return purchase_count() > 0

## Called by iap_catalog on every verified completion.
static func record_purchase(product_id: String) -> void:
	var st: Dictionary = _st()
	st["purchases"] = int(st.get("purchases", 0)) + 1
	if int(st.get("first_purchase_unix", 0)) <= 0:
		st["first_purchase_unix"] = MonoClock.now()
	var def: Dictionary = DataLoader.get_iap(product_id)
	if str(def.get("entitlement", "")) != "" and not owns(product_id):
		(st["owned"] as Array).append(product_id)

## Re-apply entitlements the store says the account owns (restore flow). Only
## non-consumables come back this way — consumables were already delivered.
static func restore(product_ids: Array) -> int:
	var st: Dictionary = _st()
	var added: int = 0
	for pid in product_ids:
		var id: String = str(pid)
		if str(DataLoader.get_iap(id).get("entitlement", "")) == "":
			continue
		if not owns(id):
			(st["owned"] as Array).append(id)
			added += 1
	return added

## Remove entitlements Play no longer reports — a refund, chargeback or
## developer revocation. The counterpart to restore(): reconciliation has to be
## able to move in BOTH directions, or refunding the ad-free upgrade is a way to
## keep it for free. Purchase COUNT is left alone on purpose; the player really
## did once buy something, and first-purchase offers should not reappear.
static func withdraw(product_ids: Array) -> int:
	var st: Dictionary = _st()
	var owned: Array = st.get("owned", [])
	var removed: int = 0
	for pid in product_ids:
		var id: String = str(pid)
		var at: int = owned.find(id)
		if at >= 0:
			owned.remove_at(at)
			removed += 1
	return removed
