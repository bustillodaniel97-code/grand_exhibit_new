extends PanelContainer
## Department operations: individual units, team upgrades and manager assignment.
const UI:=preload("res://scripts/ui/ui_kit.gd")
const Chrome:=preload("res://scripts/ui/museum_chrome.gd")
const Popups:=preload("res://scripts/ui/popup_manager.gd")
const ManagerSystem:=preload("res://scripts/managers/manager_system.gd")
const Progression:=preload("res://scripts/meta/prestige_system.gd")
const DecorSystem:=preload("res://scripts/meta/decor_system.gd")
const MANAGERS_PATH:="res://scenes/managers/managers_screen.tscn"
const TRACKS: Array[String]=["staff","speed","value"]
const TRACK_NAMES:={
	"ticket":{"staff":"Team size","speed":"Service speed","value":"Admission value"},
	"archive":{"staff":"Team size","speed":"Delivery speed","value":"Cart capacity"},
	"promotions":{"staff":"Team size","speed":"Campaign reach","value":"Audience value"},
	"gallery":{"staff":"Team size","speed":"Tour pace","value":"Exhibit value"}}
var venue_id: String=""
var dept_id: String=""
var embedded_in_sheet:=false
var selected_item: int=-1
var _row_level: Dictionary={}
var _row_effect: Dictionary={}
var _row_btn: Dictionary={}
var _item_row: VBoxContainer
var _item_name: Label
var _item_effect: Label
var _item_btn: Button
var _prev_item: Button
var _next_item: Button
var _upgrade_view: VBoxContainer
var _manager_view: VBoxContainer
var _upgrade_tab: Button
var _manager_tab: Button
var _decor_tab: Button
var _decor_view: VBoxContainer
var _collect_btn: Button
var _collect_summary: Label
var _manager_browse: Button

func _button(text: String, primary: bool=false) -> Button:
	var b:=Button.new();b.text=text;b.custom_minimum_size=Vector2(48,48)
	b.add_theme_font_override("font",UI.font());b.add_theme_font_size_override("font_size",15)
	Chrome.button(b,primary)
	b.add_theme_stylebox_override("disabled",Chrome.panel())
	b.add_theme_color_override("font_disabled_color",Chrome.DIM)
	return b

func _ready() -> void:
	var surface:=Chrome.panel(10,Chrome.BG);surface.set_content_margin_all(0)
	add_theme_stylebox_override("panel",surface)
	var pad:=MarginContainer.new()
	for side in ["left","right","top","bottom"]:pad.add_theme_constant_override("margin_"+side,10)
	add_child(pad)
	var body:=VBoxContainer.new();body.add_theme_constant_override("separation",12);pad.add_child(body)
	if not embedded_in_sheet:
		var title:=UI.make_display_label(DataLoader.venue_dept_name(venue_id,dept_id),22,Chrome.INK)
		title.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;body.add_child(title)
	var tabs:=HBoxContainer.new();tabs.add_theme_constant_override("separation",8);body.add_child(tabs)
	_upgrade_tab=_button("Upgrades",true);_upgrade_tab.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	_upgrade_tab.pressed.connect(func() -> void:_show_tab(false));tabs.add_child(_upgrade_tab)
	_manager_tab=_button("Managers");_manager_tab.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	_manager_tab.pressed.connect(func() -> void:_show_tab(true));tabs.add_child(_manager_tab)
	_decor_tab=_button("Decor");_decor_tab.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	_decor_tab.pressed.connect(_show_decor);tabs.add_child(_decor_tab)
	_decor_view=VBoxContainer.new();_decor_view.add_theme_constant_override("separation",10);_decor_view.visible=false;body.add_child(_decor_view)
	_upgrade_view=VBoxContainer.new();_upgrade_view.add_theme_constant_override("separation",10);body.add_child(_upgrade_view)
	_manager_view=VBoxContainer.new();_manager_view.add_theme_constant_override("separation",10);_manager_view.visible=false;body.add_child(_manager_view)
	var collect:=HBoxContainer.new();collect.add_theme_constant_override("separation",10);_upgrade_view.add_child(collect)
	_collect_summary=UI.make_label("Museum income",13);_collect_summary.add_theme_color_override("font_color",Chrome.DIM)
	_collect_summary.size_flags_horizontal=Control.SIZE_EXPAND_FILL;_collect_summary.vertical_alignment=VERTICAL_ALIGNMENT_CENTER
	collect.add_child(_collect_summary)
	_collect_btn=_button("Collect income");_collect_btn.custom_minimum_size.x=146
	_collect_btn.pressed.connect(_collect_income);collect.add_child(_collect_btn)
	_item_row=VBoxContainer.new();_item_row.add_theme_constant_override("separation",6);_upgrade_view.add_child(_item_row)
	var item_header:=HBoxContainer.new();item_header.add_theme_constant_override("separation",6);_item_row.add_child(item_header)
	_item_name=UI.make_display_label("Selected unit",16,Chrome.BRASS);_item_name.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	_item_name.vertical_alignment=VERTICAL_ALIGNMENT_CENTER;item_header.add_child(_item_name)
	_prev_item=_button("‹");_prev_item.tooltip_text="Previous unit";_prev_item.pressed.connect(_cycle_item.bind(-1));item_header.add_child(_prev_item)
	_next_item=_button("›");_next_item.tooltip_text="Next unit";_next_item.pressed.connect(_cycle_item.bind(1));item_header.add_child(_next_item)
	var item_body:=HBoxContainer.new();item_body.add_theme_constant_override("separation",10);_item_row.add_child(item_body)
	_item_effect=UI.make_label("",14);_item_effect.add_theme_color_override("font_color",Chrome.DIM)
	_item_effect.size_flags_horizontal=Control.SIZE_EXPAND_FILL;_item_effect.vertical_alignment=VERTICAL_ALIGNMENT_CENTER
	item_body.add_child(_item_effect)
	_item_btn=_button("Upgrade",true);_item_btn.custom_minimum_size=Vector2(146,56)
	_item_btn.pressed.connect(_on_buy_item);item_body.add_child(_item_btn)
	_upgrade_view.add_child(UI.make_divider(Chrome.BORDER))
	for track in TRACKS:_upgrade_view.add_child(_make_upgrade_row(track))
	EventBus.cash_changed.connect(_on_econ_change)
	EventBus.department_upgraded.connect(_on_department_upgraded)
	EventBus.item_upgraded.connect(_on_item_upgraded)
	EventBus.item_collected.connect(_on_item_collected)
	EventBus.manager_assigned.connect(_on_manager_changed)
	EventBus.manager_leveled.connect(_on_manager_changed)
	EventBus.manager_ranked_up.connect(_on_manager_changed)
	EventBus.reputation_changed.connect(_on_manager_changed)
	EventBus.decor_purchased.connect(_on_decor_changed)
	refresh()

func _make_upgrade_row(track: String) -> HBoxContainer:
	var row:=HBoxContainer.new();row.add_theme_constant_override("separation",10)
	var copy:=VBoxContainer.new();copy.add_theme_constant_override("separation",3)
	copy.size_flags_horizontal=Control.SIZE_EXPAND_FILL;copy.alignment=BoxContainer.ALIGNMENT_CENTER;row.add_child(copy)
	var header:=HBoxContainer.new();header.add_theme_constant_override("separation",8);copy.add_child(header)
	header.add_child(UI.make_display_label(str(TRACK_NAMES.get(dept_id,{}).get(track,track.capitalize())),16,Chrome.INK))
	var level:=UI.make_label("",13);level.add_theme_color_override("font_color",Chrome.DIM);header.add_child(level)
	var effect:=UI.make_label("",14);effect.add_theme_color_override("font_color",Chrome.DIM);copy.add_child(effect)
	var b:=_button("Upgrade",true);b.custom_minimum_size=Vector2(146,56);b.pressed.connect(_on_buy.bind(track));row.add_child(b)
	_row_level[track]=level;_row_effect[track]=effect;_row_btn[track]=b
	return row

func _cycle_item(direction: int) -> void:
	var count:=GameState.dept_items(venue_id,dept_id).size()
	if count>0:selected_item=posmod(selected_item+direction,count);_refresh_item()

func _collect_amount() -> BigNumber:
	var pending: BigNumber=GameState.pending_cash.get(venue_id,BigNumber.zero())
	var cfg: Dictionary=DataLoader.core.get("economy",{})
	return pending.scale(float(cfg.get("manual_collect_fraction",1.0))*(1.0+float(cfg.get("tip_bonus_pct",.05))))

func _refresh_collect() -> void:
	var amount:=_collect_amount()
	_collect_summary.text="Available museum income\n$"+amount.to_notation()
	_collect_btn.tooltip_text="Collect available museum income, including the configured tip bonus"

func _collect_income() -> void:
	var amount:=Economy.manual_collect(venue_id)
	EventBus.toast_requested.emit("Collected $"+amount.to_notation() if not amount.is_zero() else "No income waiting — keep the museum running")
	_refresh_collect()

func _show_tab(managers: bool) -> void:
	_decor_view.visible=false;Chrome.button(_decor_tab,false)
	_upgrade_view.visible=not managers;_manager_view.visible=managers
	Chrome.button(_upgrade_tab,not managers);Chrome.button(_manager_tab,managers)
	if managers:_refresh_managers()

func _show_decor() -> void:
	_upgrade_view.visible=false;_manager_view.visible=false;_decor_view.visible=true
	Chrome.button(_upgrade_tab,false);Chrome.button(_manager_tab,false);Chrome.button(_decor_tab,true)
	_refresh_decor()

func _on_decor_changed(_v: String,_d: String) -> void:
	if _decor_view.visible:_refresh_decor()

func _refresh_decor() -> void:
	for child in _decor_view.get_children():_decor_view.remove_child(child);child.queue_free()
	_decor_view.add_child(UI.make_display_label("Museum furnishings",18,Chrome.BRASS))
	var status:=UI.make_label(Progression.decor_summary(venue_id),15)
	status.add_theme_color_override("font_color",Chrome.INK);status.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;_decor_view.add_child(status)
	var bar:=ProgressBar.new();bar.max_value=1;bar.value=Progression.decor_progress(venue_id);bar.show_percentage=false
	bar.custom_minimum_size.y=14;bar.add_theme_stylebox_override("background",Chrome.channel(Chrome.BG));bar.add_theme_stylebox_override("fill",Chrome.channel(Chrome.TEAL));_decor_view.add_child(bar)
	var copy:=UI.make_label("Furnish this museum to open the next venue. Installed pieces improve income and visitor comfort. Cash designs can meet the full target.",14)
	copy.add_theme_color_override("font_color",Chrome.DIM);copy.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;_decor_view.add_child(copy)
	var browse:=_button("Choose furnishings",true)
	browse.pressed.connect(func() -> void: Popups.open("res://scenes/meta/decor_screen.tscn",{"venue_id":venue_id}))
	_decor_view.add_child(browse)

func _refresh_managers() -> void:
	for child in _manager_view.get_children():_manager_view.remove_child(child);child.queue_free()
	var assigned:=ManagerSystem.assigned_ids(dept_id)
	var slots:=ManagerSystem.assignment_slots(dept_id)
	_manager_tab.text="Managers (%d)"%assigned.size()
	var summary:=UI.make_label("%d of %d posts filled · x%.2f output"%[assigned.size(),slots,Economy.manager_multiplier_for(dept_id)],15)
	summary.add_theme_color_override("font_color",Chrome.DIM);summary.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;_manager_view.add_child(summary)
	var purpose:=UI.make_label("Assigned managers multiply this department’s speed and value. Improve the slowest department to raise overall income. Your collection also powers audit teams.",14)
	purpose.add_theme_color_override("font_color",Chrome.DIM);purpose.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;_manager_view.add_child(purpose)
	if not GameState.feature_unlocked("managers"):
		var req:=int(DataLoader.core.get("unlocks",{}).get("managers_rep",3))
		_manager_view.add_child(UI.make_display_label("Managers unlock at Rep %d"%req,17,Chrome.INK))
	else:
		for id in assigned:_manager_view.add_child(_manager_row(id))
	_manager_browse=_button("Choose a manager",true);_manager_browse.pressed.connect(_open_department_managers);_manager_view.add_child(_manager_browse)

func _manager_row(id: String) -> Control:
	var row:=HBoxContainer.new();row.add_theme_constant_override("separation",8)
	var def:=DataLoader.get_manager_def(id)
	var text:=UI.make_label("%s · Lv %d · Rank %d"%[str(def.get("name",id)),ManagerSystem.level(id),ManagerSystem.rank(id)],15)
	text.add_theme_color_override("font_color",Chrome.INK);text.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	text.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;text.vertical_alignment=VERTICAL_ALIGNMENT_CENTER;row.add_child(text)
	var stand:=_button("Stand down");stand.pressed.connect(func() -> void:
		ManagerSystem.unassign(id)
		EventBus.toast_requested.emit("%s stood down from %s"%[str(def.get("name",id)),DataLoader.venue_dept_name(venue_id,dept_id)]))
	row.add_child(stand);return row

func _open_department_managers() -> void:
	if not GameState.feature_unlocked("managers"):
		EventBus.toast_requested.emit("Managers unlock at Rep %d"%int(DataLoader.core.get("unlocks",{}).get("managers_rep",3)));return
	var assigned:=ManagerSystem.assigned_ids(dept_id)
	var select:=assigned[0] if not assigned.is_empty() else ""
	if select=="":
		for id in DataLoader.managers.keys():
			if str(DataLoader.get_manager_def(id).get("specialty",""))==dept_id:select=str(id);break
	Popups.open(MANAGERS_PATH,{"specialty":dept_id,"select":select})

func _on_manager_changed(_a: Variant=null,_b: Variant=null) -> void:
	_manager_tab.text="Managers (%d)"%ManagerSystem.assigned_ids(dept_id).size()
	if _manager_view!=null and _manager_view.visible:_refresh_managers()

## Cost for the next level of a track (mirrors Economy._cost; SPEC §4 upgrade_cost).
func _cost_for(track: String) -> BigNumber:
	var venue: Dictionary = DataLoader.get_venue(venue_id)
	var level: int = GameState.dept_level(venue_id, dept_id, track)
	return DataLoader.upgrade_cost(dept_id, track, level,
		float(venue.get("cost_mult", 1.0)), int(venue.get("cost_exp", 0)))

func _is_maxed(track: String) -> bool:
	if track == "staff":
		return GameState.dept_level(venue_id, dept_id, "staff") >= Economy.max_staff(venue_id, dept_id)
	return GameState.dept_level(venue_id, dept_id, track) >= Economy.track_max_level(venue_id, track)

func refresh() -> void:
	if venue_id == "" or dept_id == "":
		return
	var def: Dictionary = DataLoader.dept_def(dept_id)
	for track in TRACKS:
		var level: int = GameState.dept_level(venue_id, dept_id, track)
		(_row_level[track] as Label).text = "Lv %d" % level
		(_row_effect[track] as Label).text = _effect_text(track, def, level)
		var btn: Button = _row_btn[track]
		if _is_maxed(track):
			btn.text = "MAX"
			btn.disabled = true
			btn.modulate = Color.WHITE
		else:
			var cost: BigNumber = _cost_for(track)
			btn.text = ("Hire" if track=="staff" else "Upgrade")+"\n$"+cost.to_notation()
			var affordable: bool = GameState.cash.gte(cost)
			# Never disable for cost: a disabled button swallows the tap
			# silently (player bug: "upgrade buttons don't buy"). Stay
			# tappable so _on_buy can explain the shortfall via toast;
			# dim the button as the can't-afford visual affordance.
			btn.disabled = false
			Chrome.button(btn,affordable)
	_refresh_collect()
	_refresh_item()
	_manager_tab.text="Managers (%d)"%ManagerSystem.assigned_ids(dept_id).size()

func select_item(index: int) -> void:
	selected_item = index
	_refresh_item()

func _refresh_item() -> void:
	if _item_row == null:
		return
	var items: Array = GameState.dept_items(venue_id, dept_id)
	if selected_item<0 and not items.is_empty():selected_item=0
	var valid: bool = selected_item >= 0 and selected_item < items.size()
	_prev_item.visible=items.size()>1
	_next_item.visible=items.size()>1
	_item_row.visible = valid
	if not valid:
		return
	var level: int = GameState.item_level(venue_id, dept_id, selected_item)
	var maxed: bool = level >= Economy.item_max_level()
	var current: float = Economy.item_mult(level)
	var next: float = Economy.item_mult(mini(level + 1, Economy.item_max_level()))
	_item_name.text = "%s %d · Lv %d" % [
		"Station" if dept_id == "ticket" else "Unit", selected_item + 1, level]
	_item_effect.text = "%.2fx → %.2fx" % [current, next] if not maxed else "%.2fx · MAX" % current
	if maxed:
		_item_btn.text = "MAX"
		_item_btn.disabled = true
		_item_btn.modulate = Color.WHITE
		return
	var cost: BigNumber = Economy.item_upgrade_cost(venue_id, dept_id, selected_item)
	_item_btn.text = "Upgrade\n$"+cost.to_notation()
	_item_btn.disabled = false
	Chrome.button(_item_btn,GameState.cash.gte(cost))

func _on_buy_item() -> void:
	if selected_item < 0:
		return
	var cost: BigNumber = Economy.item_upgrade_cost(venue_id, dept_id, selected_item)
	if not GameState.cash.gte(cost):
		EventBus.toast_requested.emit("Need $" + cost.sub(GameState.cash).to_notation() + " more")
		return
	if Economy.purchase_item_upgrade(venue_id, dept_id, selected_item):
		UI.play_sfx(self, "buy")
	_refresh_item()

func _on_item_upgraded(v_id: String, d_id: String, index: int, _level: int) -> void:
	if v_id == venue_id and d_id == dept_id and index == selected_item:
		_refresh_item()

func _on_item_collected(v_id: String, d_id: String, index: int, _amount: Variant) -> void:
	if v_id == venue_id and d_id == dept_id and index == selected_item:
		_refresh_item()

func _effect_text(track: String, def: Dictionary, level: int) -> String:
	if track == "staff":
		if _is_maxed(track):
			return "%d team members · maximum" % level
		return "Team %d → %d" % [level, level + 1]
	var t: Dictionary = def.get("tracks", {}).get(track, {})
	var cur: float = Economy.dept_stat(venue_id, dept_id, track)
	var nxt: float = (float(t.get("base_stat", 1.0)) + float(t.get("per_level", 0.0)) * float(level)) \
		* DataLoader.track_step_multiplier(dept_id, track, level + 1)
	if track in ["speed", "value"]:
		nxt *= Economy.manager_multiplier_for(dept_id)
	return "%.2f → %.2f" % [cur, nxt]

func _on_buy(track: String) -> void:
	if _is_maxed(track):
		return
	var cost: BigNumber = _cost_for(track)
	if not GameState.cash.gte(cost):
		var short: BigNumber = cost.sub(GameState.cash)
		EventBus.toast_requested.emit("Need $" + short.to_notation() + " more")
		_flash_button(track, false)
		return
	if Economy.purchase_upgrade(venue_id, dept_id, track):
		_flash_button(track, true)
	# Signals (cash_changed / department_upgraded) trigger refresh; call directly too.
	refresh()

## Button-press feedback: punchy scale+green flash on a successful buy,
## small red shake when the tap only produced a "need more" toast.
func _flash_button(track: String, success: bool) -> void:
	var btn: Button = _row_btn.get(track)
	if btn == null:
		return
	btn.pivot_offset = btn.size * 0.5
	var tw := btn.create_tween()
	if success:
		tw.tween_property(btn, "scale", Vector2(1.035, 1.035), 0.08)
		tw.parallel().tween_property(btn, "modulate", Chrome.TEAL.lightened(0.1), 0.08)
		tw.tween_property(btn, "scale", Vector2.ONE, 0.16)
		tw.parallel().tween_property(btn, "modulate", Color.WHITE, 0.16)
		tw.tween_callback(refresh)  # restore affordability modulate
	else:
		tw.tween_property(btn, "modulate", Chrome.DANGER, 0.07)
		tw.tween_property(btn, "modulate", Color.WHITE, 0.22)
		tw.tween_callback(refresh)

func _on_econ_change(_v: Variant = null) -> void:
	refresh()

func _on_department_upgraded(v_id: String, d_id: String, _track: String, _level: int) -> void:
	if v_id == venue_id and d_id == dept_id:
		refresh()
