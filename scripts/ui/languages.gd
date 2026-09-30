extends RefCounted
## languages.gd — which language the game speaks.
##
## Translations are gettext catalogs in locale/<code>.po, keyed by the English
## text (tools/i18n_extract.py builds them from tr() calls, UI text literals,
## scenes and the data files). Godot translates Label/Button text by itself, so
## switching the locale re-labels open screens; code that builds a sentence
## wraps the English template in tr() first.
##
## The choice lives in GameState.settings["language"]: "auto" (default)
## follows the device, anything else is one of LANGUAGES. A language is listed
## only when its catalog is complete (tests/core/test_i18n.gd checks).

## [code, name in that language]. The UI face (Inter, subset in assets/fonts)
## covers Latin, Latin Extended and Vietnamese; scripts beyond that need a
## fallback font before they're listed.
const LANGUAGES: Array = [
	["en", "English"],
	["es", "Español"],
	["fr", "Français"],
	["de", "Deutsch"],
	["pt_BR", "Português (Brasil)"],
	["it", "Italiano"],
]

static func codes() -> Array[String]:
	var out: Array[String] = []
	for l in LANGUAGES:
		out.append(str(l[0]))
	return out

static func display_name(code: String) -> String:
	for l in LANGUAGES:
		if str(l[0]) == code:
			return str(l[1])
	return code

## The saved choice: "auto" or a code.
static func choice() -> String:
	return str(GameState.settings.get("language", "auto"))

## The code a choice means on this device. "auto" takes the device locale
## (exact match first, e.g. pt_BR, then the language alone, e.g. es_MX -> es).
static func resolve(pick: String, device_locale: String = "") -> String:
	var all := codes()
	if pick != "auto" and pick in all:
		return pick
	var dev := device_locale if device_locale != "" else OS.get_locale()
	if dev in all:
		return dev
	var lang := dev.split("_")[0].split("-")[0]
	for code in all:
		if code == lang or code.split("_")[0] == lang:
			return code
	return "en"

static func current() -> String:
	return resolve(choice())

## Apply the saved choice. Called at boot and whenever it changes.
static func apply() -> void:
	var code := current()
	if TranslationServer.get_locale() == code:
		return
	TranslationServer.set_locale(code)
	# Built text that caches translated strings starts over.
	var WS: GDScript = load("res://scripts/meta/wing_system.gd")
	WS.clear_cache()

static func set_choice(pick: String) -> void:
	GameState.settings["language"] = pick if (pick == "auto" or pick in codes()) else "auto"
	apply()
	Analytics.log_event("language_set", {"choice": choice(), "locale": current()})
