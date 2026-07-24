extends RefCounted
## rv_placements.gd — rewarded-video placements owned by the monetization branch:
## "instant_cash", "free_gems", "income_x2".
## ("welcome_back"/"insight_rush"/"free_lootbox" live on other branches; they connect
## their own AdService.ad_result handlers and route by placement id, same as we do.)
##
## Usage: preload this script (no class_name per SPEC §1) and call the entry points:
##   const RV := preload("res://scripts/monetization/rv_placements.gd")
##   RV.instant_cash() / RV.free_gems() / RV.income_x2()
## Flow: entry point -> AdService.show_rewarded -> AdService.ad_result(success) ->
## grant -> EventBus.rv_reward_granted + Analytics.rv_impression.
## Daily-cap state: GameState.rv_state[placement_id] = {count:int, day:"YYYY-MM-DD", ready_at:int}
## with automatic day rollover (count resets when the calendar day changes).

static var _connected: bool = false

static func _tuning() -> Dictionary:
	return DataLoader.core.get("monetization_tuning", {})

static func _today() -> String:
	return Time.get_date_string_from_unix_time(ClockGuard.now())

## Day rollover helper: returns state for placement, resetting count on a new day.
static func _state(placement_id: String) -> Dictionary:
	var today: String = _today()
	var st: Dictionary = GameState.rv_state.get(placement_id, {})
	if str(st.get("day", "")) != today:
		st = {"count": 0, "day": today, "ready_at": 0}
		GameState.rv_state[placement_id] = st
	return st

static func _ensure_connected() -> void:
	if _connected:
		return
	_connected = true
	AdService.ad_result.connect(_on_ad_result)

# ---------------------------------------------------------------- entry points

static func instant_cash() -> void:
	_ensure_connected()
	AdService.show_rewarded("instant_cash")

static func free_gems() -> void:
	_ensure_connected()
	if remaining_free_gems() <= 0:
		EventBus.toast_requested.emit("No free gems left today — come back tomorrow")
		return
	AdService.show_rewarded("free_gems")

static func income_x2() -> void:
	_ensure_connected()
	AdService.show_rewarded("income_x2")

# ------------------------------------------------------------------ state read

static func remaining_free_gems() -> int:
	var cap: int = int(_tuning().get("free_gems_per_day", 3))
	return maxi(0, cap - int(_state("free_gems").get("count", 0)))

static func can_view(placement_id: String) -> bool:
	match placement_id:
		"free_gems":
			return remaining_free_gems() > 0
		_:
			return true

## Remaining stacked x2 income boost time (for UI stack timer).
static func income_x2_remaining_seconds() -> int:
	var until: int = int(GameState.boosts.get("income_x2_until", 0))
	return maxi(0, until - ClockGuard.now())

## Cash amount an instant_cash view would grant right now (for UI label).
static func instant_cash_value() -> BigNumber:
	var minutes: float = float(_tuning().get("instant_cash_minutes", 15))
	return Economy.current_cash_per_second().scale(minutes * 60.0)

# -------------------------------------------------------------------- routing

static func _on_ad_result(placement_id: String, success: bool, context: Dictionary) -> void:
	if placement_id not in ["instant_cash", "free_gems", "income_x2"]:
		return  # other placements are owned/handled by other branches
	if not success:
		EventBus.toast_requested.emit("Ad unavailable — try again soon")
		return
	match placement_id:
		"instant_cash":
			grant_instant_cash(context)
		"free_gems":
			grant_free_gems(context)
		"income_x2":
			grant_income_x2(context)

# --------------------------------------------------------------------- grants
# Public so tests can simulate a successful ad directly.

static func grant_instant_cash(context: Dictionary = {}) -> void:
	var amount: BigNumber = instant_cash_value()
	GameState.add_cash(amount)
	_after_grant("instant_cash", {"amount": amount.to_save()}.merged(context))

static func grant_free_gems(context: Dictionary = {}) -> void:
	var st: Dictionary = _state("free_gems")
	var cap: int = int(_tuning().get("free_gems_per_day", 3))
	if int(st.get("count", 0)) >= cap:
		EventBus.toast_requested.emit("No free gems left today — come back tomorrow")
		return
	st["count"] = int(st["count"]) + 1
	var amount: int = int(_tuning().get("free_gems_amount", 5))
	GameState.add_gems(amount)
	_after_grant("free_gems", {"gems": amount}.merged(context))

## Stacks: extends from the current boost end (not from now), hard-capped at
## boost_cap_hours measured from now. See SPEC §8 ("2h stack, cap 8h").
static func grant_income_x2(context: Dictionary = {}) -> void:
	var now: int = ClockGuard.now()
	var per_view: int = int(_tuning().get("boost_hours_per_view", 2)) * 3600
	var cap: int = int(_tuning().get("boost_cap_hours", 8)) * 3600
	var base: int = maxi(now, int(GameState.boosts.get("income_x2_until", 0)))
	var new_until: int = mini(base + per_view, now + cap)
	GameState.boosts["income_x2_until"] = new_until
	EventBus.boost_changed.emit(2.0, new_until - now)
	_after_grant("income_x2", {"until": new_until}.merged(context))

static func _after_grant(placement_id: String, context: Dictionary) -> void:
	EventBus.rv_reward_granted.emit(placement_id, context)
	Analytics.rv_impression(placement_id)
