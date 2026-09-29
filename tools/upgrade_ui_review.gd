extends "res://tools/main_ui_review.gd"
var toasts: Array=[]
func _initialize() -> void:
	call_deferred("run");call_deferred("_watchdog")
func _watchdog() -> void:
	await create_timer(240).timeout
	printerr("FAIL upgrade review timeout");quit(1)
func run() -> void:
	if not OS.has_environment("GRAND_EXHIBIT_TEST_RUN") or OS.get_environment("XDG_DATA_HOME").is_empty():quit(2);return
	Popups=load("res://scripts/ui/popup_manager.gd")
	output=OS.get_cmdline_user_args()[0];DirAccess.make_dir_recursive_absolute(output)
	root.size=Vector2i(720,1280);root.content_scale_size=root.size
	var gs: Node=root.get_node("GameState");var ec: Node=root.get_node("Economy")
	root.get_node("SaveSystem").set_process(false);ec.set_process(false)
	var main: Node=load("res://scenes/main.tscn").instantiate();root.add_child(main)
	await create_timer(2).timeout;await close_popups()
	root.get_node("EventBus").toast_requested.connect(func(t: String) -> void:toasts.append(t))
	var view: Node=main.find_child("VenueView",true,false)
	var quests: Node=main.find_child("QuestsBar",true,false)
	view._floor.set_process(false)
	await tap(quests._chips[quests._shown_index].btn)
	check(view._sheet.visible,"objective opens upgrade panel")
	var objective_panel: Node=view._panels[view._open_dept]
	check(view._sheet_scroll.get_global_rect().encloses(objective_panel._row_btn.speed.get_global_rect()),"speed objective reveals speed purchase control without searching")
	await capture("objective-focus")
	view._close_sheet();await settle()
	var cases: Array=[]
	for height in [1280,1000]:
		root.size=Vector2i(720,height);root.content_scale_size=root.size;await settle()
		for dept in ["ticket","archive","promotions","gallery"]:
			gs.cash=BigNumber.from_float(1000000);gs.reputation_xp=BigNumber.zero()
			for track in ["staff","speed","value"]:gs.set_dept_level(gs.current_venue,dept,track,2 if track=="staff" else 1)
			view._open_item_sheet(dept,0)
			var panel: Node=view._panels[dept];panel._show_tab(false);panel.refresh();await settle()
			check(view.get_global_rect().encloses(view._sheet.get_global_rect()),"sheet fits view: "+dept)
			check(view._sheet.size.x<=root.get_visible_rect().size.x,"sheet fits width: "+dept)
			await capture("%d-%s-upgrades"%[height,dept])
			view._sheet_scroll.ensure_control_visible(panel._next_item);await settle()
			await tap(panel._next_item);check(panel.selected_item==1,"next selects unit 2: "+dept)
			var unit_level: int=gs.item_level(gs.current_venue,dept,1)
			var unit_cost: BigNumber=ec.item_upgrade_cost(gs.current_venue,dept,1)
			var cash_before: BigNumber=gs.cash
			view._sheet_scroll.ensure_control_visible(panel._item_btn);await settle()
			await tap(panel._item_btn)
			check(gs.item_level(gs.current_venue,dept,1)==unit_level+1,"selected unit upgrades: "+dept)
			check(gs.cash.cmp(cash_before.sub(unit_cost))==0,"unit charges displayed cost: "+dept)
			for track in ["staff","speed","value"]:
				var level: int=gs.dept_level(gs.current_venue,dept,track)
				var cost: BigNumber=panel._cost_for(track);cash_before=gs.cash
				view._sheet_scroll.ensure_control_visible(panel._row_btn[track]);await settle()
				check_button(panel._row_btn[track],dept+track)
				await tap(panel._row_btn[track]);await settle()
				check(gs.dept_level(gs.current_venue,dept,track)==level+1,"track upgrades: "+dept+track)
				check(gs.cash.cmp(cash_before.sub(cost))==0,"track charges displayed cost: "+dept+track)
			gs.cash=BigNumber.zero();panel.refresh();toasts.clear()
			view._sheet_scroll.ensure_control_visible(panel._row_btn.speed);await settle()
			var unchanged: int=gs.dept_level(gs.current_venue,dept,"speed")
			await tap(panel._row_btn.speed)
			check(gs.dept_level(gs.current_venue,dept,"speed")==unchanged,"unaffordable tap does not buy: "+dept)
			check(not toasts.is_empty() and str(toasts.back()).begins_with("Need $"),"unaffordable tap explains shortfall: "+dept)
			await capture("%d-%s-unaffordable"%[height,dept])
			gs.pending_cash[gs.current_venue]=BigNumber.from_float(100)
			panel.refresh();var expected: BigNumber=panel._collect_amount();cash_before=gs.cash
			view._sheet_scroll.ensure_control_visible(panel._collect_btn);await settle()
			await tap(panel._collect_btn)
			check(gs.cash.cmp(cash_before.add(expected))==0,"explicit collect matches preview including tip: "+dept)
			cash_before=gs.cash;await tap(panel._collect_btn)
			check(gs.cash.cmp(cash_before)==0,"empty collect cannot duplicate income: "+dept)
			view._sheet_scroll.ensure_control_visible(panel._manager_tab);await settle();await tap(panel._manager_tab)
			await capture("%d-%s-managers-locked"%[height,dept])
			await tap(panel._manager_browse);check(not Popups.is_open(),"panel respects manager reputation lock: "+dept)
			gs.reputation_xp=BigNumber.from_float(1e12);panel._refresh_managers();await settle()
			await tap(panel._manager_browse)
			check(find_script(main,"res://scenes/managers/managers_screen.gd")!=null,"unlocked manager path works: "+dept)
			if dept=="ticket":await capture("%d-manager-popup"%height)
			var cancel:=InputEventAction.new();cancel.action="ui_cancel";cancel.pressed=true;root.push_input(cancel,true);await settle()
			check(not Popups.is_open() and view._sheet.visible,"cancel closes manager popup only")
			root.push_input(cancel,true);await settle();check(not view._sheet.visible,"second cancel closes upgrade panel")
			cases.append({"height":height,"department":dept})
	# A maximum previous museum must not poison the new venue's panel binding.
	view._open_sheet("ticket");var old_panel: Node=view._panels.ticket
	var old_panel_id: int=old_panel.get_instance_id()
	var old_venue: String=gs.current_venue
	gs.set_dept_level(old_venue,"ticket","speed",ec.track_max_level(old_venue,"speed"));old_panel.refresh()
	check(old_panel._row_btn.speed.disabled,"maximum track has a deliberate completed state")
	gs.current_venue="copper_kettle";view._on_venue_changed(old_venue,gs.current_venue);view._floor.retheme(gs.current_venue)
	view._open_sheet("ticket");var fresh: Node=view._panels.ticket;await settle()
	check(fresh.get_instance_id()!=old_panel_id and fresh.venue_id==gs.current_venue,"new museum gets fresh bound panel")
	check(not fresh._row_btn.speed.disabled,"fresh station does not inherit previous maximum state")
	await capture("fresh-museum-panel")
	var file:=FileAccess.open(output+"/review.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"checks":checks,"failures":failures,"cases":cases},"\t"));file.close()
	print("UPGRADE_UI_REVIEW checks=",checks," failures=",failures)
	quit(1 if failures else 0)
