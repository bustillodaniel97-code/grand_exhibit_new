extends MarginContainer
## Persistent rewarded actions, styled as one museum control dock.
## Reward gates, limits, grants, offer lifetimes and prestige ads stay in their systems.

const UI := preload("res://scripts/ui/ui_kit.gd")
const Chrome := preload("res://scripts/ui/museum_chrome.gd")
const Popups := preload("res://scripts/ui/popup_manager.gd")
const RV := preload("res://scripts/monetization/rv_placements.gd")
const Offers := preload("res://scripts/monetization/offer_system.gd")
const Interstitials := preload("res://scripts/monetization/interstitials.gd")
const Art := preload("res://scripts/monetization/store_art.gd")

const STORE_PATH := "res://scenes/store/store_screen.tscn"

## Keep every placement directly reachable without dominating the world.
const CHIP_H := 56
const SIDE_CHIP_W := 116
## Offers are re-evaluated here rather than on store open, so a timed offer's clock
## starts when the player could actually see it. The check is a loop over ~9 rows.
const OFFER_POLL_SECONDS := 5.0

var _boost_btn: Button
var _cash_btn: Button
var _gems_btn: Button
var _offer_btn: Button
var _timer: Timer
var _offer_elapsed: float = 0.0

func _ready() -> void:
	name = "BoostDock"
	UI.install_default_font()
	mouse_filter = Control.MOUSE_FILTER_PASS

	add_theme_constant_override("margin_left", 14)
	add_theme_constant_override("margin_right", 14)
	add_theme_constant_override("margin_top", 4)
	add_theme_constant_override("margin_bottom", 2)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	add_child(row)

	_gems_btn = _chip("gems", UI.BRASS, SIDE_CHIP_W)
	_gems_btn.tooltip_text = "Watch an ad for free gems"
	_gems_btn.pressed.connect(func() -> void: RV.free_gems())
	row.add_child(_gems_btn)

	_cash_btn = _chip("cash", UI.ACCENT, SIDE_CHIP_W)
	_cash_btn.tooltip_text = "Watch an ad for instant cash"
	_cash_btn.pressed.connect(func() -> void: RV.instant_cash())
	row.add_child(_cash_btn)

	_boost_btn = Button.new()
	_boost_btn.custom_minimum_size=Vector2(184,CHIP_H)
	_boost_btn.add_theme_font_override("font",UI.font())
	_boost_btn.add_theme_font_size_override("font_size",15)
	Chrome.button(_boost_btn,true)
	_boost_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_boost_btn.icon = UI.icon_texture("arrow_up", 26)
	_boost_btn.tooltip_text = "Watch an ad to double your income"
	_boost_btn.pressed.connect(func() -> void: RV.income_x2())
	row.add_child(_boost_btn)

	_offer_btn = _chip("cart", Chrome.BRASS, 96)
	_offer_btn.tooltip_text = "A limited-time offer is waiting"
	_offer_btn.pressed.connect(_on_offer_pressed)
	_offer_btn.visible = false
	row.add_child(_offer_btn)

	EventBus.boost_changed.connect(func(_m: float, _s: int) -> void: refresh())
	EventBus.rv_reward_granted.connect(func(_p: String, _c: Dictionary) -> void: refresh())
	EventBus.gems_changed.connect(func(_g: int) -> void: refresh())
	EventBus.iap_completed.connect(func(_p: String) -> void: refresh())
	# Prestige is the one honest session boundary this game has; interstitial policy
	# (cap, gap, ad-free entitlement) lives in Interstitials, not here.
	EventBus.prestige_performed.connect(_on_prestige)

	_timer = Timer.new()
	_timer.wait_time = 1.0
	_timer.autostart = true
	_timer.timeout.connect(_tick)
	add_child(_timer)

	get_viewport().size_changed.connect(_apply_safe_area)
	_apply_safe_area()
	refresh()

## Keep the dock clear of a curved-display cutout. Bottom inset belongs to the nav
## bar below us, so only the sides matter here.
func _apply_safe_area() -> void:
	var inset: Dictionary = UI.safe_area_insets(self)
	add_theme_constant_override("margin_left", 14 + int(inset["left"]))
	add_theme_constant_override("margin_right", 14 + int(inset["right"]))

func _chip(icon_name: String, _color: Color, width: int) -> Button:
	var b:=Button.new();Chrome.button(b)
	# Currency icons keep their own colours; only glyph icons take the ink tint.
	for state in ["icon_normal_color","icon_hover_color","icon_pressed_color"]:b.add_theme_color_override(state,Color.WHITE)
	b.custom_minimum_size=Vector2(width,CHIP_H)
	b.add_theme_font_override("font",UI.font())
	b.add_theme_font_size_override("font_size",12)
	b.icon=UI.icon_texture(icon_name,20)
	b.icon_alignment=HORIZONTAL_ALIGNMENT_LEFT
	b.expand_icon=false;b.clip_text=true
	return b

# ---------------------------------------------------------------------- refresh

func _tick() -> void:
	refresh()
	_offer_elapsed += _timer.wait_time
	if _offer_elapsed >= OFFER_POLL_SECONDS:
		_offer_elapsed = 0.0
		Offers.check_triggers()

func refresh() -> void:
	if _boost_btn == null:
		return
	var remaining: int = RV.income_x2_remaining_seconds()
	if RV.is_busy("income_x2"):
		_boost_btn.text = "Loading ad…"
	elif remaining > 0:
		_boost_btn.text = "x2 active · %s\nWatch ad to extend" % _fmt(remaining)
	else:
		_boost_btn.text = "Double income\nWatch ad · x2"


	_cash_btn.text="Loading…" if RV.is_busy("instant_cash") else "Instant cash\nWatch ad"
	_gems_btn.text="Loading…" if RV.is_busy("free_gems") else "Free gems\n%d left · Ad"%RV.remaining_free_gems()

	var offers: Array = Offers.active_offers()
	_offer_btn.visible = not offers.is_empty()
	if not offers.is_empty():
		var oid: String = str(offers[0]["id"])
		Offers.mark_seen(oid)
		_offer_btn.text = "Offer\n"+_fmt_compact(Offers.seconds_left(oid)) if Offers.expires(oid) else "Offer"

func _on_offer_pressed() -> void:
	Analytics.store_open("world_offer_chip")
	Popups.open(STORE_PATH, {"source": "offer_chip"})

func _on_prestige(_from_venue: String, _to_venue: String) -> void:
	Interstitials.maybe_show("venue_switch")

## Chip-width countdown: the offer chip is 96px wide, so "23h 59m" does not fit.
func _fmt_compact(seconds: int) -> String:
	seconds = maxi(seconds, 0)
	if seconds >= 3600:
		return "%dh" % (seconds / 3600)
	if seconds >= 60:
		return "%dm" % (seconds / 60)
	return "%ds" % seconds

func _fmt(seconds: int) -> String:
	seconds = maxi(seconds, 0)
	var h: int = seconds / 3600
	var m: int = (seconds % 3600) / 60
	if h > 0:
		return "%dh %02dm" % [h, m]
	if m > 0:
		return "%dm" % m
	return "%ds" % seconds
