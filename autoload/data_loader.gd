extends Node
## DataLoader — parses all data/*.json once at boot. See docs/SPEC.md §3-4.

var core: Dictionary = {}
var venues: Dictionary = {}
var managers: Dictionary = {}
var lootboxes: Dictionary = {}
var decor: Dictionary = {}
var decor_sets: Dictionary = {}
var quests: Dictionary = {}
var milestones: Dictionary = {}   # venue_id -> Array of milestone defs
var iap_products: Dictionary = {}
var offers: Dictionary = {}
var events: Dictionary = {}

const DATA_DIR := "res://data/"

func _ready() -> void:
	reload_all()

func reload_all() -> void:
	core = _load("balance_core.json")
	venues = _index_by_id(_load("venues.json").get("venues", []))
	managers = _index_by_id(_load("managers.json").get("managers", []))
	lootboxes = _index_by_id(_load("lootboxes.json").get("lootboxes", []))
	var decor_file: Dictionary = _load("decor.json")
	decor = _index_by_id(decor_file.get("decor", []))
	decor_sets = _index_by_id(decor_file.get("sets", []))
	quests = _index_by_id(_load("quests_milestones.json").get("quests", []))
	milestones = _load("quests_milestones.json").get("milestones", {})
	iap_products = _index_by_id(_load("store_iap.json").get("products", []))
	offers = _index_by_id(_load("offers.json").get("offers", []))
	events = _load("events.json")

func _load(file_name: String) -> Dictionary:
	var path := DATA_DIR + file_name
	if not FileAccess.file_exists(path):
		push_warning("DataLoader: missing " + path)
		return {}
	var text := FileAccess.get_file_as_string(path)
	var parsed: Variant = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		push_warning("DataLoader: bad JSON in " + path)
		return {}
	return parsed

func _index_by_id(arr: Array) -> Dictionary:
	var out: Dictionary = {}
	for item in arr:
		if typeof(item) == TYPE_DICTIONARY and item.has("id"):
			out[item["id"]] = item
	return out

func venue_order() -> Array:
	var arr: Array = venues.values()
	arr.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a.get("order", 0)) < int(b.get("order", 0)))
	return arr.map(func(v: Dictionary) -> String: return v["id"])

func get_venue(id: String) -> Dictionary:
	return venues.get(id, {})

func get_manager_def(id: String) -> Dictionary:
	return managers.get(id, {})

func get_lootbox(id: String) -> Dictionary:
	return lootboxes.get(id, {})

func get_decor(id: String) -> Dictionary:
	return decor.get(id, {})

func get_iap(id: String) -> Dictionary:
	return iap_products.get(id, {})

func get_event(id: String) -> Dictionary:
	return events.get(id, {})

func dept_def(dept_id: String) -> Dictionary:
	return core.get("departments", {}).get(dept_id, {})

## Player-facing department name for this venue.  The simulation deliberately
## keeps stable ids such as "promotions", but authored venues are free to turn
## that same economic role into a café, concierge desk, or outreach booth.
## The name a museum gives a department ("Nature Hall"), in the player's
## language. Pass localized = false for the English data name (for logic that
## looks at the words, never for display).
func venue_dept_name(venue_id: String, dept_id: String, localized: bool = true) -> String:
	var theme: Variant = get_venue(venue_id).get("theme", {})
	if theme is Dictionary:
		for room in (theme as Dictionary).get("rooms", []):
			if room is Dictionary and str((room as Dictionary).get("dept", "")) == dept_id:
				var raw := str((room as Dictionary).get("name",
					dept_def(dept_id).get("name", dept_id.capitalize())))
				return title_case(tr(raw)) if localized else raw.capitalize()
	var generic := str(dept_def(dept_id).get("name", dept_id.capitalize()))
	return tr(generic) if localized else generic

## Room signs are written in capitals ("HALL OF THE GUARD"); panels show them
## in title case. English keeps Godot's capitalize(); other languages leave
## their short joining words lower-case ("Sala de la Naturaleza", "Halle der
## Dynastien") and capitalise each part of a hyphenated word.
const _TITLE_SMALL := ["a", "à", "al", "au", "aux", "da", "das", "de", "dei", "del", "della", "delle",
	"der", "des", "di", "die", "do", "dos", "du", "e", "el", "em", "et", "im", "la", "las", "le",
	"les", "los", "na", "no", "und", "von", "y", "zum", "zur"]

func title_case(s: String) -> String:
	if TranslationServer.get_locale().begins_with("en"):
		return s.capitalize()
	var words := s.to_lower().split(" ")
	for i in words.size():
		var w: String = words[i]
		if i > 0 and w in _TITLE_SMALL:
			continue
		var parts := w.split("-")
		for j in parts.size():
			var p: String = parts[j]
			var apo := p.find("'")
			if apo >= 0 and apo <= 2 and apo + 1 < p.length():
				parts[j] = p.substr(0, apo + 1) + p.substr(apo + 1, 1).to_upper() + p.substr(apo + 2)
			elif p != "":
				parts[j] = p.substr(0, 1).to_upper() + p.substr(1)
		words[i] = "-".join(parts)
	return " ".join(words)

## cost = base_cost * growth^level * venue_cost_mult * 10^venue_cost_exp
## venue_cost_exp defaulted so the SPEC §3 4-arg call form stays valid.
func upgrade_cost(dept_id: String, track: String, level: int, venue_cost_mult: float, venue_cost_exp: int = 0) -> BigNumber:
	var t: Dictionary = dept_def(dept_id).get("tracks", {}).get(track, {})
	if t.is_empty():
		return BigNumber.zero()
	var base_m: float = float(t.get("base_cost_m", 10.0))
	var growth: float = float(t.get("growth", 1.12))
	var cost_m: float = base_m * pow(growth, level) * venue_cost_mult
	return BigNumber.from_parts(cost_m, venue_cost_exp)

## product of all step multipliers whose level requirement <= level
func track_step_multiplier(dept_id: String, track: String, level: int) -> float:
	var steps: Dictionary = dept_def(dept_id).get("tracks", {}).get(track, {}).get("steps", {})
	var mult: float = 1.0
	var keys: Array = steps.keys()
	keys.sort_custom(func(a: String, b: String) -> bool: return int(a) < int(b))
	for k in keys:
		if int(k) <= level:
			mult *= float(steps[k])
	return mult
