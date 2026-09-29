extends Control
## Welcome Back popup (SPEC §9): offline earnings summary + 3 claim options.
## Claim 1x (free) / Watch Ad x2 (RV placement "welcome_back") / 20 Gems x3.
## Multipliers + gem cost come from balance_core.json monetization_tuning.

const UI := preload("res://scripts/ui/ui_kit.gd")
const Chrome := preload("res://scripts/ui/museum_chrome.gd")
const Popups := preload("res://scripts/ui/popup_manager.gd")

var _amount: BigNumber = BigNumber.zero()
var _seconds: int = 0
var _busy: bool = false

var _amount_lbl: Label
var _away_lbl: Label
var _claim_btn: Button
var _ad_btn: Button
var _gem_btn: Button

func _ready() -> void:
	# The column has to be told to fill. A VBoxContainer parented to a plain Control
	# keeps its minimum size in the top-left corner, so every centred label was
	# centred inside a 245px box hugging the left edge and the three claim buttons
	# came out a third of the sheet wide.
	var scroll := UI.make_page_scroll(self, 24)

	var vbox := VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_theme_constant_override("separation", 18)
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	scroll.add_child(vbox)

	# No page fill of its own: this sheet sits straight on the popup frame, which
	# is UI.PAGE. Every label therefore has to name a light colour explicitly —
	# make_label still defaults to INK for the light surfaces that remain.
	var title := UI.make_display_label("Welcome back", 34, UI.TEXT)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)

	var sub := UI.make_label("Your museum kept earning while you were away.", 18, UI.TEXT_DIM)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(sub)

	var coin_row := HBoxContainer.new()
	coin_row.alignment = BoxContainer.ALIGNMENT_CENTER
	coin_row.add_theme_constant_override("separation", 10)
	vbox.add_child(coin_row)
	coin_row.add_child(UI.make_icon("cash", 56))

	# Full-chroma green: the darkened variant was tuned to carry on cream stock.
	_amount_lbl = UI.make_display_label("+$0", 44, Chrome.TEAL)
	_amount_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(_amount_lbl)

	_away_lbl = UI.make_label("", 20, UI.TEXT_DIM)
	_away_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(_away_lbl)

	var tuning: Dictionary = DataLoader.core.get("monetization_tuning", {})
	var ad_mult: float = float(tuning.get("welcome_back_ad_mult", 2.0))
	var gem_mult: float = float(tuning.get("welcome_back_gem_mult", 3.0))
	var gem_cost: int = int(tuning.get("welcome_back_gem_cost", 20))

	_claim_btn = UI.make_button("Claim 1x", UI.SAGE)
	_claim_btn.custom_minimum_size = Vector2(0, 56)
	_claim_btn.icon = UI.icon_texture("check", 22)
	_claim_btn.pressed.connect(_on_claim)
	vbox.add_child(_claim_btn)
	var optional := UI.make_label("Optional bonus", 15, Chrome.DIM)
	optional.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(optional)

	_ad_btn = UI.make_button(tr("Watch Ad x%d") % int(ad_mult), Chrome.PANEL)
	_ad_btn.custom_minimum_size = Vector2(0, 56)
	_ad_btn.pressed.connect(_on_watch_ad.bind(ad_mult))
	vbox.add_child(_ad_btn)

	_gem_btn = UI.make_button(tr("%d Gems x%d") % [gem_cost, int(gem_mult)], Chrome.PANEL)
	_gem_btn.custom_minimum_size = Vector2(0, 56)
	_gem_btn.icon = UI.icon_texture("gems", 22)
	_gem_btn.pressed.connect(_on_gem_claim.bind(gem_mult, gem_cost))
	vbox.add_child(_gem_btn)

func setup(payload: Dictionary) -> void:
	var raw: Variant = payload.get("amount")
	_amount = raw if raw is BigNumber else BigNumber.from_save(raw)
	_seconds = int(payload.get("seconds", 0))
	_amount_lbl.text = "+$" + _amount.to_notation()
	_away_lbl.text = tr("away for %dh %dm") % [_seconds / 3600, (_seconds % 3600) / 60]

func _on_claim() -> void:
	# 1x amount was already granted by SaveSystem.compute_offline_and_apply().
	Popups.close_top()

func _on_watch_ad(mult: float) -> void:
	if _busy:
		return
	_busy = true
	_ad_btn.disabled = true
	var ctx := {"mult": mult, "amount": _amount.to_save()}
	AdService.ad_result.connect(_on_ad_result, CONNECT_ONE_SHOT)
	AdService.show_rewarded("welcome_back", ctx)

func _on_ad_result(placement_id: String, success: bool, context: Dictionary) -> void:
	if placement_id != "welcome_back":
		# Not ours — re-arm the one-shot listener and keep waiting.
		AdService.ad_result.connect(_on_ad_result, CONNECT_ONE_SHOT)
		return
	_busy = false
	if success:
		var mult: float = float(context.get("mult", 2.0))
		var amt: BigNumber = BigNumber.from_save(context.get("amount", {}))
		GameState.add_cash(amt.scale(mult - 1.0))  # 1x already applied; grant the extra
		EventBus.rv_reward_granted.emit("welcome_back", context)
		Analytics.rv_impression("welcome_back")
		EventBus.toast_requested.emit("Bonus claimed!")
		UI.play_sfx(self, "buy")
		Popups.close_top()
	else:
		_ad_btn.disabled = false
		EventBus.toast_requested.emit("Ad unavailable")

func _on_gem_claim(mult: float, cost: int) -> void:
	if GameState.spend_gems(cost):
		GameState.add_cash(_amount.scale(mult - 1.0))  # 1x already applied; grant the extra
		EventBus.toast_requested.emit("Bonus claimed!")
		UI.play_sfx(self, "buy")
		Popups.close_top()
	else:
		EventBus.toast_requested.emit("Not enough gems")
