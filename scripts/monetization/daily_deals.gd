extends RefCounted
## daily_deals.gd — rotating shelf of discounted-ish daily items from store_iap.json
## (tag == "daily"). SPEC §8: shelf of daily_deal_slots items, auto-refresh every
## daily_deal_refresh_hours hours, force refresh daily_deal_force_max x/day at
## daily_deal_force_cost gems each.
##
## State lives in GameState.daily_deals:
##   {refresh_at:int, force_used:int, day:"YYYY-MM-DD", items:Array[String]}
## Auto-refresh selection is pseudo-random but deterministic per refresh bucket
## (seeded by the bucket index), so reopening the store within one bucket is stable.

const MonoClock := preload("res://scripts/monetization/mono_clock.gd")

static func _tuning() -> Dictionary:
	return DataLoader.core.get("monetization_tuning", {})

## Guarded day, not the system clock: the force-refresh allowance used to reset
## with a single device-clock change, and so did the shelf.
static func _today() -> String:
	return MonoClock.today()

static func _interval_seconds() -> int:
	return int(_tuning().get("daily_deal_refresh_hours", 4)) * 3600

static func _slots() -> int:
	return int(_tuning().get("daily_deal_slots", 3))

static func _pool() -> Array:
	var pool: Array = []
	for pid in DataLoader.iap_products.keys():
		if str(DataLoader.iap_products[pid].get("tag", "")) == "daily":
			pool.append(pid)
	pool.sort()
	return pool

## Returns the shelf (Array of product ids), refreshing first when due.
static func shelf() -> Array:
	_ensure_fresh()
	return GameState.daily_deals.get("items", [])

static func refresh_at() -> int:
	_ensure_fresh()
	return int(GameState.daily_deals.get("refresh_at", 0))

static func seconds_until_refresh() -> int:
	return maxi(0, refresh_at() - MonoClock.now())

static func force_refreshes_left() -> int:
	_rollover_force_day()
	var cap: int = int(_tuning().get("daily_deal_force_max", 3))
	return maxi(0, cap - int(GameState.daily_deals.get("force_used", 0)))

static func force_cost() -> int:
	return int(_tuning().get("daily_deal_force_cost", 10))

## Paid re-roll. Spends gems, respects the daily cap, rerolls immediately.
static func force_refresh() -> bool:
	_rollover_force_day()
	if force_refreshes_left() <= 0:
		EventBus.toast_requested.emit("No refreshes left today")
		return false
	if not GameState.spend_gems(force_cost()):
		EventBus.toast_requested.emit("Not enough gems")
		return false
	GameState.daily_deals["force_used"] = int(GameState.daily_deals.get("force_used", 0)) + 1
	_reroll(-1)  # -1 = non-deterministic shuffle (player-paid)
	EventBus.daily_deals_refreshed.emit()
	return true

# ------------------------------------------------------------------ internals

static func _rollover_force_day() -> void:
	if str(GameState.daily_deals.get("day", "")) != _today():
		GameState.daily_deals["day"] = _today()
		GameState.daily_deals["force_used"] = 0

static func _ensure_fresh() -> void:
	_rollover_force_day()
	var now: int = MonoClock.now()
	if int(GameState.daily_deals.get("refresh_at", 0)) <= now or GameState.daily_deals.get("items", []).is_empty():
		var bucket: int = int(now / _interval_seconds())
		_reroll(bucket)
		GameState.daily_deals["refresh_at"] = (bucket + 1) * _interval_seconds()
		EventBus.daily_deals_refreshed.emit()

## bucket >= 0: deterministic pick seeded by the time bucket (stable within bucket).
## bucket < 0:  fully random pick (force refresh).
static func _reroll(bucket: int) -> void:
	var pool: Array = _pool()
	var rng := RandomNumberGenerator.new()
	if bucket >= 0:
		rng.seed = hash("grand_exhibit_daily_%d" % bucket)
	else:
		rng.randomize()
	var items: Array = []
	var available: Array = pool.duplicate()
	var n: int = mini(_slots(), available.size())
	for i in range(n):
		var idx: int = rng.randi_range(0, available.size() - 1)
		items.append(available[idx])
		available.remove_at(idx)
	GameState.daily_deals["items"] = items
