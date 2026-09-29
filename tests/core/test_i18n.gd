extends SceneTree
## test_i18n.gd — the translations and the language setting.
##
## Proves: every catalog in locale/ is registered and loads for its locale;
## every language offered in Settings translates every string in
## locale/messages.pot; placeholders (%s, %d, %.2f, %%...) survive in the same
## order, so a `tr("...") % args` can't crash or garble; the device locale maps
## to a language (es_MX -> es, pt_PT -> pt_BR, unknown -> en); switching
## re-labels text, formatted strings and the cached floor blurbs; and the pot
## matches the code (tools/i18n_extract.py --check, when python3 is around).

var failures := 0
var Languages: GDScript

func check(ok: bool, message: String) -> void:
	if ok:
		print("  PASS ", message)
	else:
		failures += 1
		printerr("  FAIL ", message)

func _initialize() -> void:
	call_deferred("run")

## msgids from the template (the extractor writes one line per msgid).
func _pot_ids() -> Array[String]:
	var out: Array[String] = []
	var text := FileAccess.get_file_as_string("res://locale/messages.pot")
	for line in text.split("\n"):
		if line.begins_with("msgid \"") and line != "msgid \"\"":
			out.append(_unescape(line.substr(7, line.length() - 8)))
	return out

## msgid -> msgstr from a catalog file (one line each, as the extractor writes
## them). Read from the file because Godot's loader drops entries whose
## translation equals the English ("MAX"), which still count as translated.
func _po_map(path: String) -> Dictionary:
	var out := {}
	var id := ""
	for line in FileAccess.get_file_as_string(path).split("\n"):
		if line.begins_with("msgid \""):
			id = _unescape(line.substr(7, line.length() - 8))
		elif line.begins_with("msgstr \"") and id != "":
			out[id] = _unescape(line.substr(8, line.length() - 9))
			id = ""
	return out

func _unescape(s: String) -> String:
	return s.replace("\\\\", "\u0001").replace("\\n", "\n").replace("\\t", "\t") \
		.replace("\\\"", "\"").replace("\u0001", "\\")

func _specs(s: String) -> Array[String]:
	var re := RegEx.new()
	re.compile("%[-+ 0#]*\\d*(?:\\.\\d+)?[sdifxXcv%]")
	var out: Array[String] = []
	for m in re.search_all(s):
		out.append(m.get_string())
	return out

func run() -> void:
	if not OS.has_environment("GRAND_EXHIBIT_TEST_RUN"):
		printerr("REFUSED: requires GRAND_EXHIBIT_TEST_RUN isolation"); quit(2); return
	Languages = load("res://scripts/ui/languages.gd")
	var gs: Node = root.get_node("GameState")
	root.get_node("SaveSystem").set_process(false)
	root.get_node("Economy").set_process(false)
	gs.reset_to_new_game()
	gs.ready_flag = true

	# Catalogs are registered and load.
	var registered: PackedStringArray = ProjectSettings.get_setting("internationalization/locale/translations", PackedStringArray())
	var catalogs: Dictionary = {}
	for f in DirAccess.get_files_at("res://locale"):
		if f.ends_with(".po"):
			var path := "res://locale/" + f
			check(path in registered, "%s is registered in project.godot" % f)
			var t: Translation = load(path) as Translation
			check(t != null and t.locale == f.get_basename(), "%s loads as the %s catalog" % [f, f.get_basename()])
			if t != null:
				catalogs[t.locale] = t

	# Every language offered is complete, with intact placeholders.
	var ids := _pot_ids()
	check(ids.size() > 1000, "the template lists the game's strings (%d)" % ids.size())
	for code in Languages.codes():
		if code == "en":
			continue
		check(catalogs.has(code), "Settings offers %s and its catalog exists" % code)
		if not catalogs.has(code):
			continue
		var po := _po_map("res://locale/%s.po" % code)
		var missing: Array[String] = []
		var broken: Array[String] = []
		for id in ids:
			var msg := str(po.get(id, ""))
			if msg == "":
				missing.append(id)
				continue
			var want := _specs(id)
			if not want.is_empty() and want != _specs(msg):
				broken.append(id)
		check(missing.is_empty(), "%s translates every string (missing %d, e.g. %s)" % [code, missing.size(), str(missing.slice(0, 3))])
		check(broken.is_empty(), "%s keeps every placeholder in order (%s)" % [code, str(broken.slice(0, 3))])

	# The device locale picks a language.
	check(Languages.resolve("auto", "es_MX") == "es", "es_MX devices get Spanish")
	check(Languages.resolve("auto", "pt_BR") == "pt_BR", "pt_BR devices get Brazilian Portuguese")
	check(Languages.resolve("auto", "pt_PT") == "pt_BR", "other Portuguese devices get it too")
	check(Languages.resolve("auto", "de-AT") == "de", "a dashed locale works")
	check(Languages.resolve("auto", "ja_JP") == "en", "an unsupported locale falls back to English")
	check(Languages.resolve("fr", "de_DE") == "fr", "an explicit choice beats the device")
	check(Languages.resolve("xx", "it_IT") == "it", "an unknown choice follows the device")

	# Switching re-labels the game.
	var label := Label.new()
	label.text = "Settings"
	root.add_child(label)
	await process_frame
	var w_en: float = label.get_minimum_size().x
	Languages.set_choice("de")
	await process_frame
	check(TranslationServer.get_locale() == "de" and str(gs.settings.get("language", "")) == "de",
		"choosing Deutsch sets and saves the locale")
	check(root.tr("Settings") == "Einstellungen", "tr() answers in German")
	check(label.get_minimum_size().x > w_en, "an existing label re-renders in German")
	check(root.tr("Managers (%d)") % 3 == "Manager (3)", "a formatted string translates, then formats")
	var WS: GDScript = load("res://scripts/meta/wing_system.gd")
	var blurb := ""
	for vid in ["whispering_pines", "chronos_spire", "infinite_museum", "grand_river"]:
		for w in WS.wings(vid):
			var b := str((w as Dictionary).get("blurb", ""))
			if b.begins_with("Öffne"):
				blurb = b
	check(blurb != "", "generated floor blurbs are rebuilt in the new language")
	Languages.set_choice("es")
	await process_frame
	check(root.tr("Settings") == "Ajustes", "switching again works (Spanish)")
	Languages.set_choice("en")
	await process_frame
	check(root.tr("Settings") == "Settings" and label.get_minimum_size().x == w_en, "English is back")
	Languages.set_choice("auto")
	check(str(gs.settings.get("language", "")) == "auto", "Automatic is a valid choice")
	TranslationServer.set_locale("en")
	label.queue_free()

	# The template matches the code.
	var out: Array = []
	var rc := OS.execute("python3", [ProjectSettings.globalize_path("res://tools/i18n_extract.py"), "--check"], out, true)
	if rc == 0 or rc == 1:
		check(rc == 0, "locale/messages.pot is up to date (run python3 tools/i18n_extract.py) %s" % str(out))
	else:
		print("  SKIP pot freshness: python3 not available (rc %d)" % rc)

	await create_timer(0.3).timeout
	print("RESULT: ", "OK" if failures == 0 else "FAILED (%d)" % failures)
	quit(1 if failures > 0 else 0)
