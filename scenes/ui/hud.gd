extends PanelContainer
## Persistent wallet: reputation, income, gems and research at a glance.
const UI:=preload("res://scripts/ui/ui_kit.gd")
const Chrome:=preload("res://scripts/ui/museum_chrome.gd")
const Popups:=preload("res://scripts/ui/popup_manager.gd")
const STORE_PATH:="res://scenes/store/store_screen.tscn"
const ROW_H:=56
var _cash_lbl: Label
var _rate_lbl: Label
var _gems_lbl: Label
var _insight_lbl: Label
var _lvl_lbl: Label
var _rep_bar: ProgressBar
var _margin: MarginContainer
var _cash_button: Button
var _gems_button: Button
var _timer: Timer

func _ready() -> void:
	UI.install_default_font()
	add_theme_stylebox_override("panel",StyleBoxEmpty.new())
	_margin=MarginContainer.new()
	_margin.add_theme_constant_override("margin_top",8)
	_margin.add_theme_constant_override("margin_bottom",4)
	add_child(_margin)
	var row:=HBoxContainer.new();row.add_theme_constant_override("separation",8)
	_margin.add_child(row)
	row.add_child(_build_level_capsule())
	row.add_child(_build_cash_button())
	row.add_child(_build_gems_button())
	row.add_child(_build_insight_chip())
	for signal_name in ["cash_changed","gems_changed","insight_changed","reputation_changed"]:
		EventBus.connect(signal_name,_on_any_change)
	_timer=Timer.new();_timer.wait_time=.5;_timer.autostart=true
	_timer.timeout.connect(refresh);add_child(_timer)
	get_viewport().size_changed.connect(_apply_safe_area)
	_apply_safe_area();refresh()

func _build_level_capsule() -> PanelContainer:
	var card:=PanelContainer.new();card.custom_minimum_size=Vector2(110,ROW_H)
	card.add_theme_stylebox_override("panel",Chrome.panel())
	var col:=VBoxContainer.new();col.add_theme_constant_override("separation",5)
	col.alignment=BoxContainer.ALIGNMENT_CENTER;card.add_child(col)
	var row:=HBoxContainer.new();row.add_theme_constant_override("separation",5)
	col.add_child(row);row.add_child(UI.make_icon("star",18,Chrome.BRASS))
	_lvl_lbl=UI.make_display_label("Rep 1",16,Chrome.INK);row.add_child(_lvl_lbl)
	_rep_bar=ProgressBar.new();_rep_bar.custom_minimum_size=Vector2(0,5)
	_rep_bar.max_value=100;_rep_bar.show_percentage=false
	_rep_bar.add_theme_stylebox_override("background",Chrome.channel(Chrome.BG))
	_rep_bar.add_theme_stylebox_override("fill",Chrome.channel(Chrome.BRASS))
	col.add_child(_rep_bar)
	return card

func _build_cash_button() -> Button:
	_cash_button=Button.new();Chrome.button(_cash_button)
	_cash_button.custom_minimum_size=Vector2(176,ROW_H)
	_cash_button.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	_cash_button.pressed.connect(_on_store_pressed.bind("resources"))
	_cash_button.tooltip_text="Museum cash · open resource shop"
	var row:=_overlay_row(_cash_button)
	row.add_child(UI.make_icon("cash",24,Color.WHITE))
	var col:=VBoxContainer.new();col.add_theme_constant_override("separation",0)
	col.alignment=BoxContainer.ALIGNMENT_CENTER;col.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	row.add_child(col)
	_cash_lbl=UI.make_display_label("0",24,Chrome.INK);_cash_lbl.clip_text=true;col.add_child(_cash_lbl)
	_rate_lbl=UI.make_display_label("+0/s",12,Chrome.TEAL);_rate_lbl.clip_text=true;col.add_child(_rate_lbl)
	row.add_child(_plus_badge());_ignore_mouse(row)
	return _cash_button

func _build_gems_button() -> Button:
	_gems_button=Button.new();Chrome.button(_gems_button)
	_gems_button.custom_minimum_size=Vector2(142,ROW_H)
	_gems_button.pressed.connect(_on_store_pressed.bind("gems"))
	var row:=_overlay_row(_gems_button)
	row.add_child(UI.make_icon("gems",20,Color.WHITE))
	_gems_lbl=UI.make_display_label("0",19,Chrome.INK)
	_gems_lbl.clip_text=true;_gems_lbl.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	row.add_child(_gems_lbl);row.add_child(_plus_badge());_ignore_mouse(row)
	return _gems_button

func _build_insight_chip() -> PanelContainer:
	var card:=PanelContainer.new();card.custom_minimum_size=Vector2(78,ROW_H)
	card.add_theme_stylebox_override("panel",Chrome.panel())
	var col:=VBoxContainer.new();col.alignment=BoxContainer.ALIGNMENT_CENTER
	col.add_theme_constant_override("separation",1);card.add_child(col)
	var label:=UI.make_display_label("INSIGHT",10,Chrome.DIM)
	label.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER;col.add_child(label)
	_insight_lbl=UI.make_display_label("0",17,Chrome.INK)
	_insight_lbl.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER;_insight_lbl.clip_text=true
	col.add_child(_insight_lbl)
	return card

func _plus_badge() -> Label:
	var label:=UI.make_display_label("+",20,Chrome.BRASS)
	label.custom_minimum_size=Vector2(18,0);label.vertical_alignment=VERTICAL_ALIGNMENT_CENTER
	label.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
	return label

func _overlay_row(button: Button) -> HBoxContainer:
	var row:=HBoxContainer.new();row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	row.offset_left=10;row.offset_right=-10;row.add_theme_constant_override("separation",6)
	row.alignment=BoxContainer.ALIGNMENT_CENTER;button.add_child(row)
	return row

func _ignore_mouse(node: Node) -> void:
	if node is Control:node.mouse_filter=Control.MOUSE_FILTER_IGNORE
	for child in node.get_children():_ignore_mouse(child)

func _apply_safe_area() -> void:
	if _margin==null:return
	var inset:=UI.safe_area_insets(self)
	_margin.add_theme_constant_override("margin_top",8+int(inset.top))
	_margin.add_theme_constant_override("margin_left",14+int(inset.left))
	_margin.add_theme_constant_override("margin_right",14+int(inset.right))

func _on_any_change(_a: Variant=null,_b: Variant=null) -> void:refresh()
func refresh() -> void:
	_cash_lbl.text=GameState.cash.to_notation()
	_rate_lbl.text="+%s / sec"%Economy.current_cash_per_second().to_notation()
	_gems_lbl.text=BigNumber.from_float(GameState.gems).to_notation()
	_gems_button.tooltip_text="%d gems · open gem shop"%GameState.gems
	_insight_lbl.text=GameState.insight.to_notation()
	_lvl_lbl.text="Rep %d"%GameState.rep_level()
	_rep_bar.value=GameState.rep_progress()*100

func _on_store_pressed(category: String="offers") -> void:
	Popups.open(STORE_PATH,{"source":"wallet","category":category})
