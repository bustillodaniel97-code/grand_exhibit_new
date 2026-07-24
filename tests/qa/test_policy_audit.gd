extends SceneTree
## QA M5-7: policy & license audit (automated, report-style checks).
## - Lootbox screen displays published drop rates (rates_text wiring).
## - Every store IAP price string ends in "9" (SPEC §4 store_iap.json).
## - Lootbox rarity weights sum to 1.0 and boxes are flagged published.
## - CREDITS.md covers every asset class used by the game (art/fonts/audio rows).
## - No NC/ND (non-commercial / no-derivatives) licensed content anywhere.
## - README documents the debug_ads / debug_iap release flags.
## Run: godot --headless --path <repo> -s tests/qa/test_policy_audit.gd

var failures: int = 0

func check(cond: bool, msg: String) -> void:
	if cond:
		print("  PASS ", msg)
	else:
		failures += 1
		printerr("  FAIL ", msg)

func read_text(path: String) -> String:
	if not FileAccess.file_exists(path):
		return ""
	return FileAccess.get_file_as_string(path)

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var DL: Node = root.get_node("DataLoader")
	DL.reload_all()

	print("-- lootbox published rates shown in UI --")
	var lootbox_screen: String = read_text("res://scenes/managers/lootbox_screen.gd")
	check(lootbox_screen.contains("rates_text"), "lootbox_screen.gd wires rates_text (published rates)")
	check(lootbox_screen.length() > 0, "lootbox_screen.gd readable")
	for box_id in DL.lootboxes.keys():
		var box: Dictionary = DL.lootboxes[box_id]
		var w: Dictionary = box.get("rarity_weights", {})
		var sum: float = 0.0
		for r in w.keys():
			sum += float(w[r])
		check(absf(sum - 1.0) < 0.001, "lootbox %s rarity weights sum to 1.0 (%.4f)" % [box_id, sum])
		check(bool(box.get("published", false)), "lootbox %s flagged published" % box_id)

	print("-- store prices end in 9 --")
	var store_raw: Variant = JSON.parse_string(read_text("res://data/store_iap.json"))
	var products: Array = store_raw.get("products", []) if typeof(store_raw) == TYPE_DICTIONARY else []
	check(products.size() > 0, "store_iap.json has products (%d)" % products.size())
	var bad_prices: Array = []
	for p in products:
		var price: String = str(p.get("price_usd", ""))
		if not price.ends_with("9"):
			bad_prices.append("%s=%s" % [p.get("id", "?"), price])
	check(bad_prices.is_empty(), "all %d store prices end in 9 (bad: %s)" % [products.size(), str(bad_prices)])

	print("-- CREDITS.md asset-class coverage --")
	var credits: String = read_text("res://CREDITS.md")
	check(credits.length() > 0, "CREDITS.md exists")
	check(credits.contains("Art"), "CREDITS.md has Art row")
	check(credits.contains("Fonts") or credits.contains("font"), "CREDITS.md has Fonts row")
	check(credits.contains("Audio"), "CREDITS.md has Audio row")
	check(credits.contains("CC0"), "CREDITS.md states CC0 for placeholder art")

	print("-- no NC/ND licensed content --")
	var offenders: Array = []
	var patterns: Array[String] = ["CC BY-NC", "CC-BY-NC", "BY-NC", "NonCommercial",
		"NoDerivatives", "BY-ND", "CC BY-ND", "CC-BY-ND"]
	_scan_dir("res://", patterns, offenders)
	# The CREDITS.md audit-target line ("No NC, no ND") is a policy statement, not a
	# license grant; it contains no license-pattern string, so no whitelist needed.
	check(offenders.is_empty(), "no NC/ND license strings in repo (found: %s)" % str(offenders))

	print("-- debug flags documented in README --")
	var readme: String = read_text("res://README.md")
	check(readme.contains("debug_ads"), "README documents debug_ads")
	check(readme.contains("debug_iap"), "README documents debug_iap")

	print("---")
	if failures == 0:
		print("ALL QA POLICY-AUDIT TESTS PASSED")
	else:
		printerr("QA POLICY-AUDIT TESTS FAILED: %d" % failures)
	quit(0 if failures == 0 else 1)

const TEXT_EXTS: Array[String] = ["gd", "md", "json", "tscn", "txt", "cfg", "godot", "import", "svg"]

func _scan_dir(path: String, patterns: Array[String], offenders: Array) -> void:
	if path.contains(".git") or path.contains(".godot") or path.contains("uid_cache"):
		return
	var dir := DirAccess.open(path)
	if dir == null:
		return
	dir.list_dir_begin()
	var name: String = dir.get_next()
	while name != "":
		if name.begins_with("."):
			name = dir.get_next()
			continue
		var full: String = path.path_join(name)
		if full == "res://tests/qa/test_policy_audit.gd":
			name = dir.get_next()
			continue  # this file legitimately contains the pattern strings
		if dir.current_is_dir():
			_scan_dir(full, patterns, offenders)
		else:
			var ext: String = name.get_extension().to_lower()
			if ext in TEXT_EXTS:
				var text: String = read_text(full)
				for pat in patterns:
					if text.contains(pat):
						offenders.append("%s [%s]" % [full, pat])
		name = dir.get_next()
	dir.list_dir_end()
