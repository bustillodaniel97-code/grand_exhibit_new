extends SceneTree
var failures := 0
var checks := 0
const Art = preload("res://scripts/monetization/store_art.gd")
func _initialize() -> void: call_deferred("run")
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1
	print("PASS " if ok else "FAIL ",label)
func run() -> void:
	var catalog = JSON.parse_string(FileAccess.get_file_as_string("res://data/store_iap.json"))
	var seen := {}
	for product in catalog.products:
		check(Art.PRODUCT_ART.has(product.id),"Authored mapping: " + product.id)
		var art := Art.make_product_art(product)
		check(art.texture != null and art.texture.get_image().has_mipmaps(),"Imported filtered image: " + product.id)
		seen[Art.product_key(product)] = true
		art.free()
	for id in ["reward_income_x2","reward_instant_cash","reward_free_gems"]:
		var art := Art.make_product_art({"id":id})
		check(art.texture != null,"Reward art: " + id)
		seen[Art.product_key({"id":id})] = true
		art.free()
	check(seen.size() == 17,"All 17 authored miniatures are used")
	var gem_keys := {}
	for id in ["gems_pouch","gems_sack","gems_crate","gems_vault","gems_hoard","gems_empire"]:
		gem_keys[Art.product_key({"id":id})] = true
	check(gem_keys.size() == 6,"Six gem tiers have independent imagery")
	for hex in ["aa552e","d6b579","27766a","2e6e8b","765f92","213641"]:
		var base := Color(hex)
		var foreground := Art.foreground_for(base)
		for darken in [0.0,.04,.13]:
			var l1 := base.darkened(darken).srgb_to_linear().get_luminance()
			var l2 := foreground.srgb_to_linear().get_luminance()
			var ratio := (maxf(l1,l2)+.05)/(minf(l1,l2)+.05)
			check(ratio >= 4.5,"Readable price/badge color %s state %.2f: %.2f:1" % [hex,darken,ratio])
	print("STORE_ART_DONE checks=%d failures=%d" % [checks,failures])
	quit(0 if failures == 0 else 1)
