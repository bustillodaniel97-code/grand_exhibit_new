extends RefCounted
## rv_placements.gd — rewarded-video placements owned by the monetization branch:
## "instant_cash", "free_gems", "income_x2".
## ("welcome_back"/"insight_rush"/"free_lootbox" live on other branches; they connect
## their own AdService.ad_result handlers and route by placement id, same as we do.)
##
## Usage: preload this script (no class_name per SPEC §1) and call the entry points:
##   const RV := preload("res://scripts/monetization/rv_placements.gd")
##   RV.instant_cash() / RV.free_gems() / RV.income_x2()
## Flow: entry point -> _begin() gate -> AdService.show_rewarded ->
## AdService.ad_result(success + reward_token) -> token redeemed -> grant ->
## EventBus.rv_reward_granted + Analytics.rv_impression.
##
## Every placement passes through ONE gate (`_begin`) which checks, together:
##   daily cap · cooldown · in-flight · ad availability
## They used to be checked in three different places, or not at all: instant_cash
## and income_x2 had no cap, no cooldown and no persisted state whatsoever, and
## nothing debounced the button, so three same-frame taps paid three rewards for
## at most one impression.
##
## Daily-cap state: GameState.rv_state[placement_id] = {count:int, day:"YYYY-MM-DD", ready_at:int}
## keyed on MonoClock's guarded day, so a device-clock change cannot roll it over.
## `ready_at` is the cooldown stamp — it was written and never read before.

const MonoClock := preload("res://scripts/monetization/mono_clock.gd")

const PLACEMENTS: Array[String] = ["instant_cash", "free_gems", "income_x2"]

## Per-day view caps and post-view cooldowns. Defaults live here because
## data/balance_core.json belongs to another track; monetization_tuning still wins
## when a key is present, so these can move into data with no code change.
const DEFAULT_CAPS := {"instant_cash": 10, "free_gems": 3, "income_x2": 8}
const DEFAULT_COOLDOWNS := {"instant_cash": 90, "free_gems": 60, "income_x2": 60}

static var _connected: bool = false
## Placement ids with a show in flight. Set synchronously at tap time — that is the
## whole point; anything async here is a race the player can win by tapping fast.
static var _in_flight: Dictionary = {}

static func _tuning() -> Dictionary:
	return DataLoader.core.get("monetization_tuning", {})

static func _today() -> String:
	return MonoClock.today()

## Day rollover helper: returns state for placement, resetting count on a new day.
static func _state(placement_id: String) -> Dictionary:
	var today: String = _today()
	var st: Variant = GameState.rv_state.get(placement_id, null)
	if typeof(st) != TYPE_DICTIONARY or str((st as Dictionary).get("day", "")) != today:
		st = {"count": 0, "day": today, "ready_at": 0}
		GameState.rv_state[placement_id] = st
	return st

static func _ensure_connected() -> void:
	if _connected:
		return
	_connected = true
	AdService.ad_result.connect(_on_ad_result)

# ------------------------------------------------------------------ cap / cooldown

static func daily_cap(placement_id: String) -> int:
	var key: String = placement_id + "_per_day"
	if placement_id == "free_gems":
		key = "free_gems_per_day"  # pre-existing tuning key name, kept
	return int(_tuning().get(key, DEFAULT_CAPS.get(placement_id, 5)))

static func cooldown_seconds(placement_id: String) -> int:
	return int(_tuning().get(placement_id + "_cooldown_seconds",
		DEFAULT_COOLDOWNS.get(placement_id, 60)))

static func views_left(placement_id: String) -> int:
	return maxi(0, daily_cap(placement_id) - int(_state(placement_id).get("count", 0)))

static func remaining_free_gems() -> int:
	return views_left("free_gems")

static func cooldown_left(placement_id: String) -> int:
	var ready_at: int = int(_state(placement_id).get("ready_at", 0))
	if ready_at <= 0:
		return 0
	return maxi(0, ready_at - MonoClock.now())

static func is_busy(placement_id: String = "") -> bool:
	if placement_id != "":
		return bool(_in_flight.get(placement_id, false))
	return not _in_flight.is_empty()

static func can_view(placement_id: String) -> bool:
	return blocked_reason(placement_id) == ""

## Why this placement cannot be watched right now, or "" when it can. The UI shows
## the reason instead of disabling the button — a disabled button reads as broken.
static func blocked_reason(placement_id: String) -> String:
	if is_busy(placement_id):
		return "in_flight"
	if views_left(placement_id) <= 0:
		return "daily_cap"
	if cooldown_left(placement_id) > 0:
		return "cooldown"
	return ""

static func blocked_message(placement_id: String) -> String:
	match blocked_reason(placement_id):
		"in_flight":
			return "Your ad is already loading"
		"daily_cap":
			return "No views left today — come back tomorrow"
		"cooldown":
			return TranslationServer.translate("Ad unavailable for another %s") % _fmt_short(cooldown_left(placement_id))
		_:
			return ""

static func _fmt_short(seconds: int) -> String:
	if seconds >= 60:
		return "%dm %02ds" % [seconds / 60, seconds % 60]
	return "%ds" % maxi(seconds, 0)

# ---------------------------------------------------------------- entry points

## The one gate. Returns false (and explains by toast) when the view is not allowed.
static func _begin(placement_id: String) -> bool:
	_ensure_connected()
	var reason: String = blocked_reason(placement_id)
	if reason != "":
		EventBus.toast_requested.emit(blocked_message(placement_id))
		Analytics.ad_event("rv_blocked", placement_id, {"reason": reason})
		return false
	# Deliberately no is_ready() gate here. A placement that is still LOADING will
	# be filled by show_rewarded's own wait-with-timeout, and a genuine no-fill comes
	# back as ad_result(false) — one honest "Ad unavailable" toast, one code path.
	# Refusing on !is_ready would make the button dead for the first frames of a
	# session, which reads as a broken game.
	_in_flight[placement_id] = true
	AdService.show_rewarded(placement_id)
	return true

static func instant_cash() -> bool:
	return _begin("instant_cash")

static func free_gems() -> bool:
	return _begin("free_gems")

static func income_x2() -> bool:
	return _begin("income_x2")

# ------------------------------------------------------------------ state read

## Remaining stacked x2 income boost time (for UI stack timer).
static func income_x2_remaining_seconds() -> int:
	var until: int = int(GameState.boosts.get("income_x2_until", 0))
	return maxi(0, until - MonoClock.now())

## Cash amount an instant_cash view would grant right now (for UI label).
static func instant_cash_value() -> BigNumber:
	var minutes: float = float(_tuning().get("instant_cash_minutes", 15))
	return Economy.current_cash_per_second().scale(minutes * 60.0)

static func free_gems_amount() -> int:
	return int(_tuning().get("free_gems_amount", 5))

static func boost_hours_per_view() -> int:
	return int(_tuning().get("boost_hours_per_view", 2))

# -------------------------------------------------------------------- routing

static func _on_ad_result(placement_id: String, success: bool, context: Dictionary) -> void:
	if placement_id not in PLACEMENTS:
		return  # other placements are owned/handled by other branches
	_in_flight.erase(placement_id)
	if not success:
		EventBus.toast_requested.emit("Ad unavailable — try again soon")
		return
	# A success signal is not a reward. AdService mints a one-shot token when an ad
	# actually completes; redeeming it is what authorises the grant, so a replayed
	# or forged ad_result pays nothing.
	if not AdService.consume_reward_token(str(context.get("reward_token", "")), placement_id):
		Analytics.ad_event("rv_rejected", placement_id, {"reason": "unverified_reward"})
		return
	# Re-check the cap at grant time. Between tap and reward a day can roll over,
	# and another surface may have spent the last view.
	if views_left(placement_id) <= 0:
		Analytics.ad_event("rv_rejected", placement_id, {"reason": "daily_cap"})
		EventBus.toast_requested.emit(blocked_message(placement_id))
		return
	_count_view(placement_id)
	match placement_id:
		"instant_cash":
			_grant_instant_cash(context)
		"free_gems":
			_grant_free_gems(context)
		"income_x2":
			_grant_income_x2(context)

static func _count_view(placement_id: String) -> void:
	var st: Dictionary = _state(placement_id)
	st["count"] = int(st.get("count", 0)) + 1
	st["ready_at"] = MonoClock.now() + cooldown_seconds(placement_id)

# --------------------------------------------------------------------- grants
# Public wrappers simulate one fully-verified view (used by tests and by any
# non-ad path that legitimately owes the same reward). They consume cap and
# cooldown exactly as a real view does — that is the point: there is no path to a
# grant that skips the cap.

static func grant_instant_cash(context: Dictionary = {}) -> bool:
	if views_left("instant_cash") <= 0:
		EventBus.toast_requested.emit(blocked_message("instant_cash"))
		return false
	_count_view("instant_cash")
	_grant_instant_cash(context)
	return true

static func grant_free_gems(context: Dictionary = {}) -> bool:
	if views_left("free_gems") <= 0:
		EventBus.toast_requested.emit(blocked_message("free_gems"))
		return false
	_count_view("free_gems")
	_grant_free_gems(context)
	return true

static func grant_income_x2(context: Dictionary = {}) -> bool:
	if views_left("income_x2") <= 0:
		EventBus.toast_requested.emit(blocked_message("income_x2"))
		return false
	_count_view("income_x2")
	_grant_income_x2(context)
	return true

static func _grant_instant_cash(context: Dictionary) -> void:
	var amount: BigNumber = instant_cash_value()
	GameState.add_cash(amount)
	_after_grant("instant_cash", {"amount": amount.to_save()}.merged(context))

static func _grant_free_gems(context: Dictionary) -> void:
	var amount: int = free_gems_amount()
	GameState.add_gems(amount)
	_after_grant("free_gems", {"gems": amount}.merged(context))

## Stacks: extends from the current boost end (not from now), hard-capped at
## boost_cap_hours measured from now. See SPEC §8 ("2h stack, cap 8h").
static func _grant_income_x2(context: Dictionary) -> void:
	var now: int = MonoClock.now()
	var per_view: int = boost_hours_per_view() * 3600
	var cap: int = int(_tuning().get("boost_cap_hours", 8)) * 3600
	var base: int = maxi(now, int(GameState.boosts.get("income_x2_until", 0)))
	var new_until: int = mini(base + per_view, now + cap)
	GameState.boosts["income_x2_until"] = new_until
	EventBus.boost_changed.emit(2.0, new_until - now)
	_after_grant("income_x2", {"until": new_until}.merged(context))

static func _after_grant(placement_id: String, context: Dictionary) -> void:
	EventBus.rv_reward_granted.emit(placement_id, context)
	Analytics.rv_impression(placement_id)
