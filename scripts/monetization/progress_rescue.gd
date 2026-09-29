extends RefCounted
## progress_rescue.gd — a contextual rewarded-ad offer for a player who is stuck.
##
## THE DESIGN CONSTRAINT, first, because everything else follows from it: the
## zero-ad campaign must stay completable. This offer is a shortcut past a dull
## stretch, never a toll gate. It is therefore:
##
##   · OPT-IN. Nothing here shows an ad. `eligible()` answers a question the UI
##     asked; the player taps, and only then does an ad play.
##   · HONEST. `preview()` states the exact reward before the ad, in the same
##     units the player will receive it.
##   · VERIFIED. `claim()` grants only against a redeemed AdService reward token.
##     A forged or replayed `ad_result` pays nothing.
##   · RARE. Cooldown, dismissal snooze and a daily cap, all data-driven.
##
## WHEN IT FIRES. "Stuck" is not "poor" — an idle game is supposed to make you
## wait. Stuck means the cheapest thing the player could actually buy is further
## than `stuck_eta_seconds` away at their CURRENT income. That deliberately does
## not fire during normal play, when something is always a minute or two off.
##
## WHAT IT NEVER DOES. It does not fire for a player with zero income (they have
## a different problem and cash will not fix it), and it does not fire at all for
## a recent payer — dangling an ad at someone who just bought the ad-free-ish
## experience is the fastest way to make a purchase feel worthless.
##
## State: GameState.rv_state["progress_rescue"] =
##   {last_offer: int, snoozed_until: int, day: String, offers_today: int}

const MonoClock := preload("res://scripts/monetization/mono_clock.gd")
const Entitlements := preload("res://scripts/monetization/entitlements.gd")

const STATE_KEY := "progress_rescue"

static func cfg() -> Dictionary:
	return DataLoader.core.get("progress_rescue", {})

static func _st() -> Dictionary:
	var st: Variant = GameState.rv_state.get(STATE_KEY, null)
	if typeof(st) != TYPE_DICTIONARY:
		st = {"last_offer": 0, "snoozed_until": 0, "day": "", "offers_today": 0}
		GameState.rv_state[STATE_KEY] = st
	# Roll the daily counter here rather than on a timer: the app is routinely
	# killed and resumed across a date boundary, and a counter that only resets
	# while running would leak offers.
	var today: String = MonoClock.today()
	if str(st.get("day", "")) != today:
		st["day"] = today
		st["offers_today"] = 0
	return st

static func placement() -> String:
	return str(cfg().get("placement", "instant_cash"))

# ------------------------------------------------------------------ stuckness

## Seconds until the player can afford the cheapest upgrade available to them,
## at current income. INF when nothing is buyable or income is zero.
##
## The item is the upgrade atom (see docs/IBT_MECHANICS_AUDIT.md), so the
## cheapest actionable purchase is the cheapest item upgrade on the floor.
static func cheapest_upgrade_eta(venue_id: String) -> float:
	var cheapest: BigNumber = null
	for dept_id in DataLoader.core.get("departments", {}).keys():
		var items: Array = GameState.dept_items(venue_id, str(dept_id))
		for i in items.size():
			var cost: BigNumber = Economy.item_upgrade_cost(venue_id, str(dept_id), i)
			if cost == null:
				continue
			if cheapest == null or cost.lt(cheapest):
				cheapest = cost
	if cheapest == null:
		return INF
	if GameState.cash.gte(cheapest):
		return 0.0
	var cps: BigNumber = Economy.current_cash_per_second()
	var rate: float = cps.to_float_approx()
	if rate <= 0.0:
		return INF
	var short: float = cheapest.to_float_approx() - GameState.cash.to_float_approx()
	if short <= 0.0:
		return 0.0
	return short / rate

# ----------------------------------------------------------------- eligibility

## Should the UI show the rescue affordance right now?
##
## Returns {ok: bool, reason: String, eta: float, reward: BigNumber}. `reason` is
## for telemetry and tests, not for the player — a player who is not eligible is
## shown nothing at all, not an explanation of why they cannot have help.
static func eligible(venue_id: String = "") -> Dictionary:
	if venue_id == "":
		venue_id = GameState.current_venue
	var c: Dictionary = cfg()
	var out := {"ok": false, "reason": "", "eta": 0.0, "reward": BigNumber.zero()}
	if c.is_empty():
		out["reason"] = "not_configured"
		return out

	var now: int = MonoClock.now()
	var st: Dictionary = _st()

	# A player who just paid is not shown an ad offer.
	var ents: Dictionary = GameState.rv_state.get("entitlements", {})
	var first_purchase: int = int(ents.get("first_purchase_unix", 0))
	if Entitlements.has_ever_purchased() and first_purchase > 0 \
			and now - first_purchase < int(c.get("suppress_after_purchase_seconds", 86400)):
		out["reason"] = "recent_purchase"
		return out
	if Entitlements.no_ads():
		out["reason"] = "no_ads_entitlement"
		return out

	if MonoClock.elapsed_since(GameState.first_launch_unix) < int(c.get("min_session_seconds", 300)):
		out["reason"] = "session_too_short"
		return out
	if now < int(st.get("snoozed_until", 0)):
		out["reason"] = "snoozed"
		return out
	if now - int(st.get("last_offer", 0)) < int(c.get("cooldown_seconds", 900)):
		out["reason"] = "cooldown"
		return out
	if int(st.get("offers_today", 0)) >= int(c.get("max_offers_per_day", 3)):
		out["reason"] = "daily_cap"
		return out

	var cps: BigNumber = Economy.current_cash_per_second()
	if bool(c.get("require_positive_income", true)) and cps.to_float_approx() <= 0.0:
		# No income is a different problem; handing over 15 minutes of nothing
		# would be an insulting reward and would not unstick anything.
		out["reason"] = "no_income"
		return out

	var eta: float = cheapest_upgrade_eta(venue_id)
	out["eta"] = eta
	if eta < float(c.get("stuck_eta_seconds", 600)):
		out["reason"] = "not_stuck"
		return out

	out["reward"] = reward_amount()
	out["ok"] = true
	out["reason"] = "stuck"
	return out

## The exact reward, so the UI can show it BEFORE the ad rather than after.
static func reward_amount() -> BigNumber:
	var seconds: float = float(cfg().get("reward_seconds_of_income", 900))
	return Economy.current_cash_per_second().scale(seconds)

static func preview(venue_id: String = "") -> Dictionary:
	var e: Dictionary = eligible(venue_id)
	return {
		"available": bool(e["ok"]),
		"amount": e["reward"] as BigNumber,
		"amount_text": (e["reward"] as BigNumber).to_notation(),
		"minutes": int(float(cfg().get("reward_seconds_of_income", 900)) / 60.0),
		"eta_seconds": float(e["eta"]),
	}

# ---------------------------------------------------------------------- flow

## Record that the offer was actually put in front of the player. Called when the
## affordance is SHOWN, so the cooldown measures offers seen rather than ads
## watched — otherwise declining would cost nothing and the prompt would return
## immediately, which is the nagging pattern this cap exists to prevent.
static func mark_offered() -> void:
	var st: Dictionary = _st()
	st["last_offer"] = MonoClock.now()
	st["offers_today"] = int(st.get("offers_today", 0)) + 1
	Analytics.log_event("rescue_offered", {"today": st["offers_today"]})

## "Not now". Longer than the cooldown on purpose: a player who actively said no
## is telling you something a timer is not.
static func dismiss() -> void:
	var st: Dictionary = _st()
	st["snoozed_until"] = MonoClock.now() + int(cfg().get("dismiss_snooze_seconds", 1800))
	Analytics.log_event("rescue_dismissed", {})

## Grant the reward. ONLY from a verified rewarded-ad callback: the token is
## minted by AdService at show time and redeemable exactly once, so a replayed or
## forged ad_result pays nothing.
static func claim(context: Dictionary) -> bool:
	var token: String = str(context.get("reward_token", ""))
	if not AdService.consume_reward_token(token, placement()):
		Analytics.log_event("rescue_rejected", {"reason": "bad_token"})
		return false
	var amount: BigNumber = reward_amount()
	if amount.to_float_approx() <= 0.0:
		return false
	GameState.add_cash(amount)
	Analytics.log_event("rescue_granted", {"amount": amount.to_notation()})
	return true
