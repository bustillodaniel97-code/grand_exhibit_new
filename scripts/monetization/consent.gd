extends RefCounted
## consent.gd — privacy consent gate (UMP/GDPR + COPPA declaration), stubbed.
##
## This is an interface with a real call site, not a shipped consent dialog: the
## actual EEA form comes from Google's User Messaging Platform SDK, which is not
## wired here (no SDK dependency, no network). What this file guarantees today is
## that every place that could leak data asks first:
##   · Analytics writes nothing to disk until resolve() has run (autoload/analytics.gd).
##   · AdService is told whether it may request personalized ads (apply()).
##   · The store carries a "Privacy choices" entry point so the choice is revocable,
##     which is a hard requirement once a real consent form exists.
##
## Child-directed treatment is read from data (data/store_iap.json "policy" block)
## rather than hardcoded, because it is a distribution decision, not a code one: a
## Families-programme build flips one flag and every ad request downstream becomes
## non-personalized regardless of what the player chose.
##
## State: GameState.settings["privacy"] =
##   {status:"unknown|granted|denied", personalized:bool, asked_at:int}

const MonoClock := preload("res://scripts/monetization/mono_clock.gd")

const POLICY_PATH := "res://data/store_iap.json"

static var _policy_cache: Dictionary = {}

static func _st() -> Dictionary:
	var s: Variant = GameState.settings.get("privacy", null)
	if typeof(s) != TYPE_DICTIONARY:
		s = {"status": "unknown", "personalized": false, "asked_at": 0}
		GameState.settings["privacy"] = s
	return s

static func policy() -> Dictionary:
	if not _policy_cache.is_empty():
		return _policy_cache
	_policy_cache = {"child_directed": false, "ad_content_rating": "G", "consent_required_regions": "EEA_UK"}
	if FileAccess.file_exists(POLICY_PATH):
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(POLICY_PATH))
		if typeof(parsed) == TYPE_DICTIONARY:
			var p: Variant = (parsed as Dictionary).get("policy", null)
			if typeof(p) == TYPE_DICTIONARY:
				_policy_cache.merge(p as Dictionary, true)
	return _policy_cache

static func child_directed() -> bool:
	return bool(policy().get("child_directed", false))

static func status() -> String:
	return str(_st().get("status", "unknown"))

static func resolved() -> bool:
	return status() != "unknown"

## True when the player's own choice is still needed. The real UMP SDK answers this
## per-region; the stub asks once, everywhere, which is the conservative reading.
static func required() -> bool:
	return not resolved()

## Personalized ads are allowed only if the player said yes AND the build is not
## child-directed. Both conditions, always — a child-directed build cannot opt in.
static func personalized_ads() -> bool:
	if child_directed():
		return false
	return status() == "granted" and bool(_st().get("personalized", false))

## Record a choice. `personalized` covers both ad personalization and analytics;
## the stub keeps them as one decision because it presents one question.
static func set_choice(granted: bool, personalized: bool = false) -> void:
	var s: Dictionary = _st()
	s["status"] = "granted" if granted else "denied"
	s["personalized"] = personalized and granted and not child_directed()
	s["asked_at"] = MonoClock.now()
	Analytics.log_event("consent_choice", {
		"status": s["status"], "personalized": s["personalized"],
		"child_directed": child_directed(),
	})
	apply()

## Clear the recorded choice so the form is shown again ("Privacy choices" in the
## store). Revocability is not optional under GDPR.
static func reset_choice() -> void:
	var s: Dictionary = _st()
	s["status"] = "unknown"
	s["personalized"] = false
	apply()

## Push the current state into every consumer. Called at boot (AdService) and
## whenever the choice changes.
static func apply() -> void:
	Analytics.set_consent(status() == "granted")

## Boot-time resolution. A debug build auto-grants so developer telemetry works
## without a dialog in front of every test run; a release build must ask, and until
## it does, nothing is written and ads stay non-personalized.
static func resolve_at_boot() -> void:
	if not resolved() and OS.is_debug_build() and not OS.has_feature("release"):
		var s: Dictionary = _st()
		s["status"] = "granted"
		s["personalized"] = false
		s["asked_at"] = MonoClock.now()
	apply()
