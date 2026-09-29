extends RefCounted
## DailyGifts — the seven-day login calendar. No class_name.
##
## One gift per local calendar day. Progress never resets: a player who skips
## a few days picks up at the next gift, and after day 7 the week repeats.
## Rewards come from data/daily_gifts.json.
##
## State (GameState.event_state["daily_gifts"], saved with the game):
##   day    index of the next gift (0..6)
##   last   local date ("YYYY-MM-DD") of the last claim
##   total  gifts claimed ever

const BattleMath := preload("res://scripts/events/battle_math.gd")
const DigSystem := preload("res://scripts/digsite/dig_system.gd")
const MonoClock := preload("res://scripts/monetization/mono_clock.gd")
const KEY := "daily_gifts"

static var _cfg: Dictionary = {}

static func config() -> Dictionary:
	if _cfg.is_empty():
		var f := FileAccess.open("res://data/daily_gifts.json", FileAccess.READ)
		if f != null:
			var parsed: Variant = JSON.parse_string(f.get_as_text())
			if parsed is Dictionary:
				_cfg = parsed
	return _cfg

static func days() -> Array:
	return config().get("days", [])

static func _state() -> Dictionary:
	if not GameState.event_state.has(KEY):
		GameState.event_state[KEY] = {"day": 0, "last": "", "total": 0}
	return GameState.event_state[KEY]

## The player's local date for unix time `now` (default: MonoClock's guarded
## time, so winding the device clock forward doesn't hand out tomorrow's gift).
static func date_key(now: int = -1) -> String:
	if now < 0:
		now = MonoClock.now()
	var bias := int(Time.get_time_zone_from_system().get("bias", 0))
	return Time.get_date_string_from_unix_time(now + bias * 60)

static func day_index() -> int:
	return int(_state().get("day", 0)) % maxi(days().size(), 1)

static func available(now: int = -1) -> bool:
	return not days().is_empty() and str(_state().get("last", "")) != date_key(now)

static func total() -> int:
	return int(_state().get("total", 0))

## Short text for a day's gift ("5 gems", "20 min of income", ...).
static func describe(gift: Dictionary) -> String:
	var parts: Array = []
	if gift.has("gems"):
		parts.append("%d gems" % int(gift["gems"]))
	if gift.has("cash_minutes"):
		parts.append("%d min of income" % int(gift["cash_minutes"]))
	if gift.has("dig_energy"):
		parts.append("%d dig energy" % int(gift["dig_energy"]))
	if gift.has("boost_hours"):
		parts.append("x2 income %dh" % int(gift["boost_hours"]))
	if gift.has("cards_box"):
		parts.append(str(DataLoader.get_lootbox(str(gift["cards_box"])).get("name", "Manager case")))
	return " + ".join(PackedStringArray(parts))

## Claim today's gift. Returns what was granted ({} if already claimed today).
static func claim(now: int = -1) -> Dictionary:
	if not available(now):
		return {}
	var gift: Dictionary = days()[day_index()]
	var applied := {"day": day_index() + 1}
	if gift.has("gems"):
		GameState.add_gems(int(gift["gems"]))
		applied["gems"] = int(gift["gems"])
	if gift.has("cash_minutes"):
		var cash: BigNumber = Economy.current_cash_per_second().scale(60.0 * float(gift["cash_minutes"]))
		GameState.add_cash(cash)
		applied["cash"] = cash
	if gift.has("dig_energy"):
		DigSystem.add_energy(int(gift["dig_energy"]))
		applied["dig_energy"] = int(gift["dig_energy"])
	if gift.has("boost_hours"):
		var t: int = MonoClock.now()
		var until: int = maxi(t, int(GameState.boosts.get("income_x2_until", 0))) + int(gift["boost_hours"]) * 3600
		GameState.boosts["income_x2_until"] = until
		EventBus.boost_changed.emit(2.0, until - t)
		applied["boost_hours"] = int(gift["boost_hours"])
	if gift.has("cards_box"):
		var rng := RandomNumberGenerator.new()
		rng.randomize()
		var drawn: Dictionary = BattleMath.draw_cards(DataLoader.get_lootbox(str(gift["cards_box"])), DataLoader.managers, rng)
		for mid in drawn.keys():
			if GameState.managers_state.has(mid):
				GameState.managers_state[mid]["cards"] = int(GameState.managers_state[mid].get("cards", 0)) + int(drawn[mid])
				EventBus.manager_obtained.emit(mid, int(drawn[mid]))
		applied["cards"] = drawn
	var s := _state()
	s["day"] = (day_index() + 1) % days().size()
	s["last"] = date_key(now)
	s["total"] = total() + 1
	EventBus.daily_gift_claimed.emit(int(applied["day"]))
	return applied
