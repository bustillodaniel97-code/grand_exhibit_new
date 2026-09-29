extends RefCounted
## reminders.gd — what the game tells a player who has put the phone down, and
## when. Pure planning: autoload/platform_services.gd hands the plan to the
## phone's notification scheduler when the app goes to the background and
## cancels it when the player comes back.
##
## The rules, and why:
##  · Only things that are really waiting: the vault full (offline earnings stop
##    at the cap), the next Daily Gift, the Pop-Up Café opening or about to
##    close, a full dig-energy bar. No "we miss you".
##  · Nothing at night: anything due between 22:00 and 08:00 local time moves
##    to 08:00.
##  · At most MAX_PER_BREAK per absence, MIN_GAP apart, none sooner than
##    MIN_DELAY (the player has only just left).
##  · Nothing when the player turned notifications off in Settings.
##  · Written when the app is backgrounded, so the text is in the player's
##    current language.

const MonoClock := preload("res://scripts/monetization/mono_clock.gd")
const DailyGifts := preload("res://scripts/meta/daily_gifts.gd")
const CafeSystem := preload("res://scripts/events/cafe_system.gd")
const DigSystem := preload("res://scripts/digsite/dig_system.gd")

const MIN_DELAY := 15 * 60
const MIN_GAP := 60 * 60
const MAX_PER_BREAK := 4
const QUIET_FROM_HOUR := 22
const QUIET_TO_HOUR := 8
const CAFE_LAST_CALL := 2 * 3600
## A gift left unclaimed gets one nudge this long after the player leaves.
const GIFT_NUDGE := 3 * 3600
## Tomorrow's gift is announced at this local hour.
const GIFT_HOUR := 9

## Stable ids per kind, so a new plan replaces the old one instead of stacking.
const IDS := {"vault": 101, "gift": 102, "cafe_open": 103, "cafe_closing": 104, "dig": 105}

static func enabled() -> bool:
	return bool(GameState.settings.get("notifications", true))

static func _t(s: String) -> String:
	return str(TranslationServer.translate(s))

## Local-time offset in seconds (the device's time zone).
static func _bias() -> int:
	return int(Time.get_time_zone_from_system().get("bias", 0)) * 60

## `at` moved out of the quiet hours (22:00–08:00 local) to 08:00.
static func out_of_quiet_hours(at: int, bias: int = -2147483648) -> int:
	var b := _bias() if bias == -2147483648 else bias
	var local := at + b
	var day_start := local - posmod(local, 86400)
	var hour := posmod(local, 86400) / 3600
	if hour >= QUIET_FROM_HOUR:
		return day_start + 86400 + QUIET_TO_HOUR * 3600 - b
	if hour < QUIET_TO_HOUR:
		return day_start + QUIET_TO_HOUR * 3600 - b
	return at

## The next local `hour`:00 after `now`.
static func next_local_hour(now: int, hour: int, bias: int = -2147483648) -> int:
	var b := _bias() if bias == -2147483648 else bias
	var local := now + b
	var target := local - posmod(local, 86400) + hour * 3600
	if target <= local:
		target += 86400
	return target - b

static func _venue_name() -> String:
	return _t(str(DataLoader.get_venue(GameState.current_venue).get("name", "")))

## Every candidate, before quiet hours, spacing and the cap.
static func candidates(now: int) -> Array:
	var out: Array = []
	# The vault: offline earnings stop at the cap.
	var cap_h: float = float((DataLoader.core.get("economy", {}) as Dictionary).get("offline_cap_hours", 4))
	out.append({"key": "vault", "at": now + int(cap_h * 3600.0),
		"title": _t("Your vault is full"),
		"body": _t("%s has earned all it can hold while you were away. Come and collect it!") % _venue_name()})
	# The Daily Gift: a nudge if today's is still waiting, else tomorrow morning's.
	if not DailyGifts.days().is_empty():
		if DailyGifts.available(now):
			out.append({"key": "gift", "at": now + GIFT_NUDGE,
				"title": _t("Your Daily Gift is waiting"),
				"body": _t("Today's gift is still wrapped. Tap to claim it.")})
		else:
			var day := DailyGifts.day_index() + 1
			out.append({"key": "gift", "at": next_local_hour(now, GIFT_HOUR),
				"title": _t("A new Daily Gift is ready"),
				"body": _t("Day %d: %s") % [day, DailyGifts.describe(DailyGifts.days()[day - 1])]})
	# The Pop-Up Café: last call before it closes, or the next opening.
	if CafeSystem.unlocked():
		var w := CafeSystem.window(now)
		var theme := _t(str(CafeSystem.theme().get("name", "The Pop-Up Café")))
		if bool(w.get("live", false)):
			var last_call := int(w["ends_at"]) - CAFE_LAST_CALL
			if last_call > now:
				out.append({"key": "cafe_closing", "at": last_call,
					"title": _t("The café closes in 2 hours"),
					"body": _t("%s packs up soon. Spend your café coins while you can.") % theme})
		elif int(w.get("next_at", 0)) > now:
			out.append({"key": "cafe_open", "at": int(w["next_at"]),
				"title": _t("The Pop-Up Café is open!"),
				"body": _t("%s is serving for a few days. Come and earn café coins.") % theme})
	# The dig site: energy back to full.
	if GameState.feature_unlocked("dig"):
		var missing := DigSystem.max_energy() - DigSystem.energy()
		if missing > 0:
			out.append({"key": "dig", "at": now + DigSystem.next_energy_in() + (missing - 1) * DigSystem.regen_seconds(),
				"title": _t("Your dig site is ready"),
				"body": _t("Energy is full. There are artifacts waiting to be uncovered.")})
	return out

## The notifications to schedule for an absence starting `now`:
## [{id, key, at, title, body}], soonest first.
static func plan(now: int = -1) -> Array:
	if now < 0:
		now = MonoClock.now()
	if not enabled() or not GameState.ready_flag:
		return []
	var items: Array = []
	for c in candidates(now):
		var at := out_of_quiet_hours(int(c["at"]))
		if at < now + MIN_DELAY:
			continue
		var item: Dictionary = (c as Dictionary).duplicate()
		item["at"] = at
		item["id"] = int(IDS.get(str(c["key"]), 199))
		items.append(item)
	items.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a["at"]) < int(b["at"]))
	var out: Array = []
	var last := -MIN_GAP
	for item in items:
		if out.size() >= MAX_PER_BREAK:
			break
		if int(item["at"]) - last < MIN_GAP:
			continue
		out.append(item)
		last = int(item["at"])
	return out
