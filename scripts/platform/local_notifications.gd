extends RefCounted
## local_notifications.gd — the phone's local notification scheduler behind
## PlatformServices (Android and iOS). It drives the godot-notification-scheduler
## plugin through its native singleton ("NotificationSchedulerPlugin"), which
## takes plain dictionaries, so nothing here needs the plugin to compile. With no
## plugin (desktop, the editor, tests) available() is false and PlatformServices
## skips reminders entirely.
##
## What it guarantees:
##  · One channel ("Museum news"), created at start; Android needs it before the
##    first notification.
##  · A new plan replaces the old one: every reminder kind has a fixed id
##    (scripts/meta/reminders.gd IDS), all cancelled before scheduling.
##  · cancel_all() when the player comes back, so nothing fires mid-session.
##  · Permission is asked for only when the game asks (after the first Daily
##    Gift), never at launch.
##
## tests/meta/test_reminders.gd drives it against a fake singleton.

const Reminders := preload("res://scripts/meta/reminders.gd")

const SINGLETON_NAMES: Array[String] = ["NotificationSchedulerPlugin"]
const CHANNEL_ID := "museum_news"
const ICON := "ic_default_notification"
## NotificationChannel.Importance.DEFAULT
const IMPORTANCE_DEFAULT := 3

var _plugin: Object = null
var _started := false

func available() -> bool:
	return _resolve() != null

func _set_plugin_for_test(obj: Object) -> void:
	_plugin = obj

func _resolve() -> Object:
	if _plugin != null:
		return _plugin
	for name in SINGLETON_NAMES:
		if Engine.has_singleton(name):
			_plugin = Engine.get_singleton(name)
			return _plugin
	return null

func _call(method: String, args: Array = []) -> Variant:
	var p := _resolve()
	if p == null or not p.has_method(method):
		return null
	return p.callv(method, args)

func start() -> bool:
	if _resolve() == null:
		return false
	_call("initialize")
	_call("create_notification_channel", [{
		"channel_id": CHANNEL_ID,
		"channel_name": str(TranslationServer.translate("Museum news")),
		"channel_description": str(TranslationServer.translate("Your vault, gifts, the café and the dig site")),
		"channel_importance": IMPORTANCE_DEFAULT,
		"badge_enabled": true,
	}])
	_started = true
	return true

func is_started() -> bool:
	return _started

## True when notifications may be posted. A plugin without the permission
## call (older iOS builds) is taken as allowed.
func has_permission() -> bool:
	var p := _resolve()
	if p == null:
		return false
	if not p.has_method("has_post_notifications_permission"):
		return true
	return bool(p.call("has_post_notifications_permission"))

func request_permission() -> void:
	_call("request_post_notifications_permission")

## Replace whatever is scheduled with `plans` ([{id, at, title, body}], see
## reminders.gd). Returns how many were scheduled.
func schedule(plans: Array, now: int) -> int:
	if not _started:
		return 0
	cancel_all()
	var n := 0
	for p in plans:
		var d: Dictionary = p
		var delay := int(d.get("at", 0)) - now
		if delay <= 0:
			continue
		_call("schedule", [{
			"notification_id": int(d.get("id", 199)),
			"channel_id": CHANNEL_ID,
			"title": str(d.get("title", "")),
			"content": str(d.get("body", "")),
			"small_icon_name": ICON,
			"delay": delay,
		}])
		n += 1
	return n

func cancel_all() -> void:
	if not _started:
		return
	for id in Reminders.IDS.values():
		_call("cancel", [int(id)])
	_call("set_badge_count", [0])
