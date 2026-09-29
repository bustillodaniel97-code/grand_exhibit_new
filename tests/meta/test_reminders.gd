extends SceneTree
## test_reminders.gd — local notifications: what's planned (reminders.gd), how
## it reaches the phone's scheduler (local_notifications.gd, against a fake of
## the godot-notification-scheduler singleton) and when PlatformServices does it.
##
## Proves: quiet hours move reminders to 08:00; the vault-full reminder lands at
## the offline cap; an unclaimed gift gets a nudge, a claimed one announces
## tomorrow's at 09:00; the café's last call and next opening; the dig site's
## full-energy time; nothing sooner than 15 min, 1 h apart, 4 at most; nothing
## when switched off; each kind has a fixed id so a new plan replaces the old;
## backgrounding schedules, returning cancels; no permission, no reminders;
## permission is asked once, after the first Daily Gift.

var failures := 0
var R: GDScript
var LN: GDScript

func check(ok: bool, message: String) -> void:
	if ok:
		print("  PASS ", message)
	else:
		failures += 1
		printerr("  FAIL ", message)

func _initialize() -> void:
	call_deferred("run")

class FakeScheduler:
	extends Object
	var inits := 0
	var channels: Array = []
	var scheduled: Array = []
	var cancelled: Array = []
	var permission := true
	var asked := 0
	var badge := -1
	func initialize() -> void:
		inits += 1
	func create_notification_channel(d: Dictionary) -> int:
		channels.append(d)
		return OK
	func schedule(d: Dictionary) -> int:
		scheduled.append(d)
		return OK
	func cancel(id: int) -> int:
		cancelled.append(id)
		return OK
	func set_badge_count(n: int) -> int:
		badge = n
		return OK
	func has_post_notifications_permission() -> bool:
		return permission
	func request_post_notifications_permission() -> int:
		asked += 1
		return OK

## Unix time of `hour`:00 local on the day of `base`.
func _local_at(base: int, hour: int) -> int:
	var bias: int = R._bias()
	var local := base + bias
	return local - posmod(local, 86400) + hour * 3600 - bias

func _keys(plan: Array) -> Array:
	var out: Array = []
	for p in plan:
		out.append(str((p as Dictionary)["key"]))
	return out

func _find(list: Array, key: String) -> Dictionary:
	for p in list:
		if str((p as Dictionary)["key"]) == key:
			return p
	return {}

func run() -> void:
	if not OS.has_environment("GRAND_EXHIBIT_TEST_RUN"):
		printerr("REFUSED: requires GRAND_EXHIBIT_TEST_RUN isolation"); quit(2); return
	R = load("res://scripts/meta/reminders.gd")
	LN = load("res://scripts/platform/local_notifications.gd")
	var gs: Node = root.get_node("GameState")
	var ps: Node = root.get_node("PlatformServices")
	var dl: Node = root.get_node("DataLoader")
	root.get_node("SaveSystem").set_process(false)
	root.get_node("Economy").set_process(false)
	gs.reset_to_new_game()
	gs.ready_flag = true
	var clock: int = int(root.get_node("ClockGuard").now())

	# Quiet hours and the gift hour, in the device's time zone.
	var morning := _local_at(clock, 10)
	check(R.out_of_quiet_hours(_local_at(clock, 23)) == _local_at(clock, 8) + 86400, "23:00 moves to 08:00 the next day")
	check(R.out_of_quiet_hours(_local_at(clock, 3)) == _local_at(clock, 8), "03:00 moves to 08:00 the same day")
	check(R.out_of_quiet_hours(morning + 1800) == morning + 1800, "daytime stays put")
	check(R.next_local_hour(morning, 9) == _local_at(clock, 9) + 86400, "after 09:00, the next 09:00 is tomorrow")
	check(R.next_local_hour(_local_at(clock, 8), 9) == _local_at(clock, 9), "before 09:00, it's today")

	# A new player at 10:00: the vault and an unclaimed gift.
	var cap_h: float = float((dl.core.get("economy", {}) as Dictionary).get("offline_cap_hours", 4))
	var plan: Array = R.plan(morning)
	var vault := _find(plan, "vault")
	check(not vault.is_empty() and int(vault["at"]) == morning + int(cap_h * 3600.0), "the vault reminder lands at the offline cap")
	check(int(vault.get("id", 0)) == int(R.IDS["vault"]) and str(vault.get("title", "")) != "", "it carries its fixed id and a title")
	var gift := _find(plan, "gift")
	check(not gift.is_empty() and int(gift["at"]) == morning + R.GIFT_NUDGE, "an unclaimed gift gets a nudge")
	check(not ("dig" in _keys(plan)) and not ("cafe_open" in _keys(plan)), "locked features stay quiet")
	var sorted := true
	for i in range(1, plan.size()):
		sorted = sorted and int(plan[i]["at"]) - int(plan[i - 1]["at"]) >= R.MIN_GAP
	check(sorted, "reminders are in order and at least an hour apart")

	# After claiming: tomorrow's gift at 09:00.
	var DG: GDScript = load("res://scripts/meta/daily_gifts.gd")
	DG.claim(morning)
	gift = _find(R.plan(morning), "gift")
	check(not gift.is_empty() and int(gift["at"]) == _local_at(clock, 9) + 86400, "a claimed gift announces tomorrow's at 09:00")
	check(str(gift.get("body", "")).contains("2"), "and says which day it is")

	# Café and dig site once unlocked.
	var th: Array = dl.core.get("reputation", {}).get("thresholds_mantissa", [])
	var BN: GDScript = load("res://scripts/core/big_number.gd")
	if th.size() >= 5:
		gs.reputation_xp = BN.from_float(float(th[4]))
	var CS: GDScript = load("res://scripts/events/cafe_system.gd")
	var DS: GDScript = load("res://scripts/digsite/dig_system.gd")
	check(CS.unlocked() and gs.feature_unlocked("dig"), "reputation unlocks the café and the dig site")
	var w: Dictionary = CS.window(morning)
	var cands: Array = R.candidates(morning)
	if bool(w["live"]):
		var closing := _find(cands, "cafe_closing")
		check(int(w["ends_at"]) - R.CAFE_LAST_CALL <= morning or int(closing.get("at", 0)) == int(w["ends_at"]) - R.CAFE_LAST_CALL,
			"a live café gets a last call two hours before it closes")
	else:
		check(int(_find(cands, "cafe_open").get("at", 0)) == int(w["next_at"]), "a closed café announces its next opening")
	check(_find(cands, "dig").is_empty(), "full dig energy needs no reminder")
	var dstate: Dictionary = DS._state()
	dstate["energy"] = float(DS.max_energy() - 4)
	dstate["energy_t"] = int(root.get_node("ClockGuard").now())
	var dig := _find(R.candidates(morning), "dig")
	var expect: int = morning + DS.next_energy_in() + 3 * DS.regen_seconds()
	check(not dig.is_empty() and absi(int(dig["at"]) - expect) <= 2, "spent energy is announced when it's full again")

	# The rules on the final plan.
	plan = R.plan(morning)
	check(plan.size() <= R.MAX_PER_BREAK, "at most %d reminders per absence" % R.MAX_PER_BREAK)
	var early := false
	for p in plan:
		early = early or int(p["at"]) < morning + R.MIN_DELAY
	check(not early, "nothing fires in the first 15 minutes")
	gs.settings["notifications"] = false
	check(R.plan(morning).is_empty(), "switched off in Settings: nothing is planned")
	gs.settings["notifications"] = true

	# The scheduler, against a fake plugin.
	var fake := FakeScheduler.new()
	var ln: RefCounted = LN.new()
	ln._set_plugin_for_test(fake)
	check(ln.available() and ln.start(), "the scheduler binds to the plugin")
	check(fake.inits == 1 and fake.channels.size() == 1 and str(fake.channels[0]["channel_id"]) == LN.CHANNEL_ID,
		"start initializes it and creates the channel")
	var n: int = ln.schedule(plan, morning)
	check(n == plan.size() and fake.scheduled.size() == plan.size(), "every planned reminder is scheduled")
	var ok_delays := true
	for i in plan.size():
		ok_delays = ok_delays and int(fake.scheduled[i]["delay"]) == int(plan[i]["at"]) - morning \
			and int(fake.scheduled[i]["notification_id"]) == int(plan[i]["id"])
	check(ok_delays, "with its delay and fixed id")
	check(fake.cancelled.size() >= R.IDS.size(), "the old plan is cancelled first")
	var bare: RefCounted = LN.new()
	check(not bare.available(), "without the plugin (this build) there's no scheduler")

	# PlatformServices: background, return, permission.
	var fake2 := FakeScheduler.new()
	var ln2: RefCounted = LN.new()
	ln2._set_plugin_for_test(fake2)
	ln2.start()
	ps._use_notifier_for_test(ln2)
	check(ps.notifications_available(), "PlatformServices has a scheduler")
	ps._notification(Node.NOTIFICATION_APPLICATION_PAUSED)
	check(fake2.scheduled.size() >= 1, "going to the background schedules the reminders")
	fake2.cancelled.clear()
	ps._notification(Node.NOTIFICATION_APPLICATION_RESUMED)
	check(fake2.cancelled.size() == R.IDS.size() and fake2.badge == 0, "coming back cancels them and clears the badge")
	fake2.scheduled.clear()
	fake2.permission = false
	check(ps.schedule_reminders(morning) == 0 and fake2.scheduled.is_empty(), "no permission, no reminders")
	gs.settings.erase("notifications_asked")
	root.get_node("EventBus").daily_gift_claimed.emit(1)
	root.get_node("EventBus").daily_gift_claimed.emit(2)
	check(fake2.asked == 1, "permission is asked once, after the first Daily Gift")
	ps._use_notifier_for_test(null)

	fake.free()
	fake2.free()
	await create_timer(0.3).timeout
	print("RESULT: ", "OK" if failures == 0 else "FAILED (%d)" % failures)
	quit(1 if failures > 0 else 0)
