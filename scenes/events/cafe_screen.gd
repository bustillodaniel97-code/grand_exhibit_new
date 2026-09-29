extends Control
## Pop-Up Café screen: the timed event area. The café lives in its own toy
## diorama (cafe_world.gd); under it, the four stations to open and upgrade
## with café coins, and the star reward track. CafeSystem owns every number.
##
## House rule: no button is disabled for something the player can fix. A
## station they can't afford stays tappable and says how many coins it needs.

const CafeSystem := preload("res://scripts/events/cafe_system.gd")
const CafeWorld := preload("res://scenes/events/cafe_world.gd")
const UI := preload("res://scripts/ui/ui_kit.gd")
const Chrome := preload("res://scripts/ui/museum_chrome.gd")
const Juice := preload("res://scripts/ui/juice.gd")

var world: Node3D
var _title: Label
var _time: Label
var _coins: Label
var _rate: Label
var _stars: Label
var _closed: PanelContainer
var _rows := {}      # station id -> {"name": Label, "info": Label, "button": Button}
var _chips: Array = []
var _timer: Timer

func setup(_payload: Dictionary) -> void:
	pass

func _ready() -> void:
	name = "CafeScreen"
	CafeSystem.tick()
	var bg := ColorRect.new()
	bg.color = Chrome.BG
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right"]:
		margin.add_theme_constant_override("margin_%s" % side, 14)
	margin.add_theme_constant_override("margin_top", 10)
	margin.add_theme_constant_override("margin_bottom", 12)
	add_child(margin)
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 8)
	margin.add_child(body)

	var head := HBoxContainer.new()
	body.add_child(head)
	_title = UI.make_display_label("", 26, Chrome.INK)
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_title.clip_text = true
	head.add_child(_title)
	_time = UI.make_display_label("", 16, Chrome.BRASS)
	_time.name = "TimeLeft"
	_time.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	head.add_child(_time)

	var wallet := HBoxContainer.new()
	wallet.add_theme_constant_override("separation", 10)
	body.add_child(wallet)
	_coins = UI.make_display_label("", 22, Chrome.INK)
	_coins.name = "Coins"
	wallet.add_child(_coins)
	_rate = UI.make_label("", 15)
	_rate.add_theme_color_override("font_color", Chrome.TEAL)
	_rate.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_rate.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	wallet.add_child(_rate)
	_stars = UI.make_display_label("", 20, Chrome.BRASS)
	_stars.name = "Stars"
	wallet.add_child(_stars)

	var view := SubViewportContainer.new()
	view.name = "CafeView"
	view.stretch = true
	view.custom_minimum_size = Vector2(0, 420)
	view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	body.add_child(view)
	var vp := SubViewport.new()
	vp.own_world_3d = true
	vp.msaa_3d = Viewport.MSAA_4X
	view.add_child(vp)
	world = CafeWorld.new()
	world.name = "CafeWorld"
	vp.add_child(world)

	_closed = PanelContainer.new()
	_closed.name = "ClosedNotice"
	var sb := Chrome.panel(16, Chrome.RAISED)
	sb.set_content_margin_all(14)
	_closed.add_theme_stylebox_override("panel", sb)
	_closed.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_closed.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var cl := _label("", 18, Chrome.INK)
	cl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cl.custom_minimum_size = Vector2(380, 0)
	_closed.add_child(cl)
	view.add_child(_closed)

	for st in CafeSystem.stations():
		body.add_child(_station_row(str(st["id"])))

	body.add_child(_label("Reward track · every level you buy is a star", 14, Chrome.DIM))
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 112)
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	body.add_child(scroll)
	var track := HBoxContainer.new()
	track.name = "RewardTrack"
	track.add_theme_constant_override("separation", 8)
	scroll.add_child(track)
	for i in CafeSystem.rewards().size():
		var chip := _reward_chip(i)
		track.add_child(chip)
		_chips.append(chip)

	_timer = Timer.new()
	_timer.wait_time = 0.5
	_timer.autostart = true
	_timer.timeout.connect(refresh)
	add_child(_timer)
	refresh()

func refresh() -> void:
	var w := CafeSystem.tick()
	var live := bool(w.get("live", false)) and CafeSystem.unlocked()
	_title.text = str(CafeSystem.theme().get("name", "Pop-Up Cafe"))
	var now := ClockGuard.now()
	if not CafeSystem.unlocked():
		_time.text = ""
	elif live:
		_time.text = tr("Ends in %s") % CafeSystem.fmt_left(int(w["ends_at"]) - now)
	else:
		_time.text = "Closed"
	_coins.text = tr("%s coins") % BigNumber.from_float(CafeSystem.coins()).to_notation()
	_rate.text = tr("+%s / sec") % BigNumber.from_float(CafeSystem.rate()).to_notation() if live else ""
	_stars.text = "★ %d" % CafeSystem.stars()
	_closed.visible = not live
	var notice: Label = _closed.get_child(0)
	if not CafeSystem.unlocked():
		notice.text = tr("The Pop-Up Café opens at reputation %d.") % int(CafeSystem.config().get("unlock_rep", 3))
	else:
		notice.text = tr("The café is closed.\nThe next pop-up opens in %s.") % CafeSystem.fmt_left(int(w.get("next_at", now)) - now)
	for id in _rows.keys():
		var row: Dictionary = _rows[id]
		var lvl := CafeSystem.level(id)
		(row["name"] as Label).text = CafeSystem.station_name(id)
		(row["info"] as Label).text = ("Lv %d · +%s/s" % [lvl, BigNumber.from_float(CafeSystem.income(id)).to_notation()]) if lvl > 0 else tr("Closed · earns +%s/s") % BigNumber.from_float(CafeSystem.income(id, 1)).to_notation()
		var b: Button = row["button"]
		if lvl >= CafeSystem.max_level():
			b.text = "Max"
		else:
			b.text = (tr("Open\n%s") if lvl <= 0 else tr("Upgrade\n%s")) % BigNumber.from_float(CafeSystem.cost(id)).to_notation()
		Chrome.button(b, live and CafeSystem.can_buy(id), 14)
	for i in _chips.size():
		_style_chip(_chips[i], i)
	if world != null:
		world.refresh()

func _station_row(id: String) -> Control:
	var card := PanelContainer.new()
	card.name = "Station_%s" % id
	var sb := Chrome.panel(14, Chrome.PANEL)
	sb.set_content_margin_all(8)
	sb.content_margin_left = 14
	card.add_theme_stylebox_override("panel", sb)
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 10)
	card.add_child(hb)
	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", 0)
	hb.add_child(col)
	var nm := UI.make_display_label("", 18, Chrome.INK)
	col.add_child(nm)
	var info := _label("", 14, Chrome.DIM)
	col.add_child(info)
	var b := Button.new()
	b.name = "Buy_%s" % id
	b.custom_minimum_size = Vector2(150, 56)
	b.add_theme_font_override("font", UI.font())
	b.add_theme_font_size_override("font_size", 15)
	b.pressed.connect(_on_buy.bind(id))
	hb.add_child(b)
	_rows[id] = {"name": nm, "info": info, "button": b}
	return card

func _on_buy(id: String) -> void:
	if not CafeSystem.is_live():
		EventBus.toast_requested.emit("The café is closed right now")
		return
	if CafeSystem.level(id) >= CafeSystem.max_level():
		EventBus.toast_requested.emit(tr("%s is at max level") % CafeSystem.station_name(id))
		return
	if not CafeSystem.buy(id):
		var short := CafeSystem.cost(id) - CafeSystem.coins()
		EventBus.toast_requested.emit(tr("Need %s more café coins") % BigNumber.from_float(short).to_notation())
		return
	UI.play_sfx(self, "buy")
	if world != null:
		world.celebrate(id)
	refresh()

func _reward_chip(index: int) -> Control:
	var chip := PanelContainer.new()
	chip.name = "Reward%d" % index
	chip.custom_minimum_size = Vector2(104, 104)
	var col := VBoxContainer.new()
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_theme_constant_override("separation", 2)
	chip.add_child(col)
	var r: Dictionary = CafeSystem.rewards()[index]
	var star := UI.make_display_label("★ %d" % int(r.get("stars", 0)), 16, Chrome.BRASS)
	star.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(star)
	var what := _label(_reward_text(r), 13, Chrome.INK)
	what.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(what)
	var b := Button.new()
	b.name = "Claim"
	b.custom_minimum_size = Vector2(88, 34)
	b.add_theme_font_override("font", UI.font())
	b.add_theme_font_size_override("font_size", 14)
	b.pressed.connect(_on_claim.bind(index))
	col.add_child(b)
	return chip

func _reward_text(r: Dictionary) -> String:
	if r.has("cards_box"):
		return str(DataLoader.get_lootbox(str(r["cards_box"])).get("name", "Manager case"))
	return tr("%d gems") % int(r.get("gems", 0))

func _style_chip(chip: PanelContainer, index: int) -> void:
	var ready := CafeSystem.claimable(index)
	var got := CafeSystem.is_claimed(index)
	var sb := Chrome.panel(14, Chrome.RAISED if ready else Chrome.PANEL)
	sb.set_content_margin_all(6)
	if ready:
		sb.border_color = Chrome.ACTION
		sb.set_border_width_all(3)
	chip.add_theme_stylebox_override("panel", sb)
	chip.modulate = Color(1, 1, 1, 0.6) if got else Color.WHITE
	var b: Button = chip.find_child("Claim", true, false)
	b.text = "Got it" if got else ("Claim" if ready else "Locked")
	Chrome.button(b, ready, 10)

func _on_claim(index: int) -> void:
	if CafeSystem.is_claimed(index):
		return
	if not CafeSystem.claimable(index):
		var need := int((CafeSystem.rewards()[index] as Dictionary).get("stars", 0)) - CafeSystem.stars()
		EventBus.toast_requested.emit(tr("%d more stars to go") % need)
		return
	var got := CafeSystem.claim(index)
	var chip: Control = _chips[index]
	if int(got.get("gems", 0)) > 0:
		Juice.coin_burst(chip.get_global_rect().get_center(), "gems", 7)
		EventBus.toast_requested.emit(tr("+%d gems") % int(got["gems"]))
	else:
		var n := 0
		for v in (got.get("cards", {}) as Dictionary).values():
			n += int(v)
		EventBus.toast_requested.emit(tr("+%d manager cards") % n)
	UI.play_sfx(self, "buy")
	refresh()

func _label(text: String, size_px: int, color: Color) -> Label:
	var l := UI.make_label(text, size_px)
	l.add_theme_color_override("font_color", color)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return l
