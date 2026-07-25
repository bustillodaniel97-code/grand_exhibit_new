extends MarginContainer
## BoostDock — the persistent rewarded-video action row on the world view.
##
## IBT_PARITY.md priority 2: "the missing revenue loop". Every rewarded placement
## we own used to be reachable from exactly one place — three cards at the bottom of
## the store, roughly a screen below the fold — so the highest-margin surface in the
## game was one the player had to go looking for. This dock puts them one tap away,
## permanently, on the screen the player already stares at.
##
## Layout, not overlay, and deliberately so. It is a real row in main.gd's shell
## VBox between the venue and the bottom nav, in the indigo band the world already
## wastes. An overlay would have to dodge the HUD, the nav bar and the department
## sheet that slides up from the bottom of the venue view — three moving targets on
## a canvas where z_index is global. A layout row cannot overlap any of them by
## construction.
##
## Buttons are never disabled. A capped or cooling-down placement stays tappable and
## explains itself by toast (rv_placements.blocked_message); a disabled button
## swallows the tap and reads as a broken game.

const UI := preload("res://scripts/ui/ui_kit.gd")
const Popups := preload("res://scripts/ui/popup_manager.gd")
const RV := preload("res://scripts/monetization/rv_placements.gd")
const Offers := preload("res://scripts/monetization/offer_system.gd")
const Interstitials := preload("res://scripts/monetization/interstitials.gd")
const Art := preload("res://scripts/monetization/store_art.gd")

const STORE_PATH := "res://scenes/store/store_screen.tscn"

## Chip height. 64 rather than the 48dp floor: this row is the most-tapped control
## in the game and it sits next to a 5-tab nav bar, so it has to win the thumb.
## The side chips are square at that height on purpose — the nav below is a row of
## 64px discs, so the two rows share one module size and read as a single bottom
## system instead of two unrelated bars. Square also buys the wide BOOST pill ~100px
## it did not have, which is where the eye should land.
const CHIP_H := 64
const SIDE_CHIP_W := 72
## Offers are re-evaluated here rather than on store open, so a timed offer's clock
## starts when the player could actually see it. The check is a loop over ~9 rows.
const OFFER_POLL_SECONDS := 5.0

var _boost_btn: Button
var _cash_btn: Button
var _gems_btn: Button
var _offer_btn: Button
var _gems_badge: Label
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
	row.add_theme_constant_override("separation", 10)
	add_child(row)

	_gems_btn = _chip("gems", UI.BRASS, SIDE_CHIP_W)
	_gems_btn.tooltip_text = "Watch an ad for free gems"
	_gems_btn.pressed.connect(func() -> void: RV.free_gems())
	row.add_child(_free_stack(_gems_btn))

	_cash_btn = _chip("cash", UI.ACCENT, SIDE_CHIP_W)
	_cash_btn.tooltip_text = "Watch an ad for instant cash"
	_cash_btn.pressed.connect(func() -> void: RV.instant_cash())
	row.add_child(_cash_btn)

	_boost_btn = Art.make_boost_button("x2 BOOST", UI.SAGE)
	_boost_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_boost_btn.icon = UI.icon_texture("arrow_up", 26)
	_boost_btn.tooltip_text = "Watch an ad to double your income"
	_boost_btn.pressed.connect(func() -> void: RV.income_x2())
	row.add_child(_boost_btn)

	_offer_btn = _chip("cart", UI.PLUM, SIDE_CHIP_W)
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

func _chip(icon_name: String, color: Color, width: int) -> Button:
	var b := UI.make_button("", color)
	b.custom_minimum_size = Vector2(width, CHIP_H)
	b.icon = UI.icon_texture(icon_name, 26)
	# 11px, not TYPE_CAPTION: the chips are square now and "+CASH" at 13 clipped to
	# "+CAS", which reads as a rendering fault rather than a tight fit.
	b.add_theme_font_size_override("font_size", 11)
	# Icon above the caption rather than beside it: at chip width a side-by-side icon
	# and word leaves the word two letters wide.
	b.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	b.vertical_icon_alignment = VERTICAL_ALIGNMENT_TOP
	b.expand_icon = false
	b.clip_text = true
	return b

## "FREE" flag over the gems chip — the same read as IBT's free-currency chip,
## drawn as our own small ribbon rather than copied.
func _free_stack(btn: Button) -> Control:
	var holder := Control.new()
	holder.custom_minimum_size = Vector2(SIDE_CHIP_W, CHIP_H)
	btn.set_anchors_preset(Control.PRESET_FULL_RECT)
	holder.add_child(btn)
	var ribbon := Art.make_ribbon("FREE", UI.SAGE)
	ribbon.position = Vector2(-2, -6)
	holder.add_child(ribbon)
	# Dark ink, not white: the counter prints on the gold chip face, where white
	# measures under 2:1 and the halo was doing all the work.
	_gems_badge = UI.make_display_label("", 11, Color("#4A2E05"))
	_gems_badge.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	# Clear of the candy cap's bottom lip: sat on it, the descenders were cut and the
	# counter read as a clipped label.
	_gems_badge.offset_top = -26
	_gems_badge.offset_bottom = -8
	_gems_badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_gems_badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	UI.add_text_halo(_gems_badge, Color(1, 0.93, 0.75, 0.65), 3)
	holder.add_child(_gems_badge)
	return holder

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
		_boost_btn.text = "loading…"
	elif remaining > 0:
		_boost_btn.text = "x2  %s" % _fmt(remaining)
	else:
		_boost_btn.text = "x2 BOOST"
	UI.retint_button(_boost_btn, UI.SAGE if remaining <= 0 else UI.SAGE.darkened(0.12))

	_cash_btn.text = "loading…" if RV.is_busy("instant_cash") else "CASH"
	# The gems chip already spends its caption line on the daily counter, so the word
	# would land on top of it. FREE ribbon + gem icon + "3 left" says it without one.
	_gems_badge.text = "loading…" if RV.is_busy("free_gems") else "%d left" % RV.remaining_free_gems()

	var offers: Array = Offers.active_offers()
	_offer_btn.visible = not offers.is_empty()
	if not offers.is_empty():
		var oid: String = str(offers[0]["id"])
		Offers.mark_seen(oid)
		_offer_btn.text = _fmt_compact(Offers.seconds_left(oid)) if Offers.expires(oid) else "OFFER"

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
