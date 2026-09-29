extends SceneTree
var Popups: GDScript
var RV: GDScript
var failures:=0
var checks:=0
var output: String
var records: Array=[]
func _initialize() -> void:call_deferred("run")
func check(ok: bool,label: String) -> void:
	checks+=1
	if not ok:failures+=1;printerr("FAIL ",label)
func settle() -> void:await create_timer(.25).timeout
func tap(button: Button, wait: bool=true) -> void:
	check(button.is_visible_in_tree(),"tap target is visible: "+button.name)
	var e:=InputEventMouseButton.new();e.button_index=MOUSE_BUTTON_LEFT
	e.position=button.get_global_rect().get_center();e.pressed=true;root.push_input(e,true)
	var release:=e.duplicate();release.pressed=false;root.push_input(release,true)
	if wait:await settle()
	else:await process_frame
func find_script(n: Node,path: String) -> Node:
	if n.get_script()!=null and n.get_script().resource_path==path:return n
	for child in n.get_children():
		var found:=find_script(child,path)
		if found!=null:return found
	return null
func capture(name: String) -> void:
	await RenderingServer.frame_post_draw
	check(root.get_texture().get_image().save_png(output+"/"+name+".png")==OK,"save "+name)
func close_popups() -> void:
	while Popups.is_open():Popups.close_top();await settle()
func check_button(b: Button,label: String) -> void:
	if not b.is_visible_in_tree():return
	check(b.size.x>=48 and b.size.y>=48,label+" minimum touch size")
	check(root.get_visible_rect().encloses(b.get_global_rect()),label+" stays on screen")
func run() -> void:
	if not OS.has_environment("GRAND_EXHIBIT_TEST_RUN") or OS.get_environment("XDG_DATA_HOME").is_empty():quit(2);return
	Popups=load("res://scripts/ui/popup_manager.gd");RV=load("res://scripts/monetization/rv_placements.gd")
	output=OS.get_cmdline_user_args()[0];DirAccess.make_dir_recursive_absolute(output)
	root.size=Vector2i(720,1280);root.content_scale_size=root.size
	var gs: Node=root.get_node("GameState")
	root.get_node("SaveSystem").set_process(false);root.get_node("Economy").set_process(false)
	var main: Node=load("res://scenes/main.tscn").instantiate();root.add_child(main)
	await create_timer(2).timeout;await close_popups()
	var hud:=main.find_child("HUD",true,false)
	var quests:=main.find_child("QuestsBar",true,false)
	var nav:=main.find_child("BottomNav",true,false)
	var dock:=main.find_child("BoostDock",true,false)
	var rail:=main.find_child("SideRail",true,false)
	var floor_node:=main.find_child("VenueFloor",true,false)
	floor_node.set_process(false)
	for height in [1280,1000]:
		root.size=Vector2i(720,height);root.content_scale_size=root.size;await settle()
		gs.reputation_xp=BigNumber.zero();gs.first_launch_unix=root.get_node("ClockGuard").now()
		hud.refresh();nav.refresh_locks();quests.refresh();dock.refresh();rail.refresh();await settle()
		var before_cash: Dictionary=gs.cash.to_save();var before_gems: int=gs.gems
		for id in nav._buttons:check_button(nav._buttons[id],id)
		for b in [hud._cash_button,hud._gems_button,quests._cycle_btn,dock._gems_btn,dock._cash_btn,dock._boost_btn,dock._offer_btn]:check_button(b,b.name)
		check(quests._venue_label.text==root.get_node("DataLoader").get_venue(gs.current_venue).name,"museum name shown")
		check(quests.get_global_rect().end.y<dock.get_global_rect().position.y,"world remains between goals and dock")
		await capture("%d-locked"%height)
		await tap(nav._buttons.managers);check(not Popups.is_open(),"locked managers explains without opening screen")
		var first_id: String=quests._shown_qid
		var seen: Array=[]
		for i in 3:
			seen.append(quests._shown_qid)
			var visible:=0
			for chip in quests._chips:
				if chip.btn.is_visible_in_tree():visible+=1
			check(visible==1,"one legible objective")
			await tap(quests._cycle_btn)
		check(seen.size()==3 and seen[0]!=seen[1] and seen[1]!=seen[2] and seen[0]!=seen[2],"cycle reaches all three quests")
		check(quests._shown_qid==first_id,"cycle returns to first objective")
		quests.refresh();check(quests._shown_qid==first_id,"refresh preserves selection")
		await tap(quests._chips[quests._shown_index].btn)
		check(main.find_child("VenueView",true,false)._sheet.visible,"objective opens its station sheet")
		main.find_child("VenueView",true,false)._close_sheet();await settle()
		await tap(hud._gems_button)
		var store:=find_script(main,"res://scenes/store/store_screen.gd")
		check(store!=null and store._category=="gems","gems wallet opens gem shelf")
		check(not store._impressions.has("starter_bundle"),"gem deep link does not track unseen offer products")
		await capture("%d-gem-shortcut"%height);await close_popups()
		await tap(hud._cash_button);store=find_script(main,"res://scenes/store/store_screen.gd")
		check(store!=null and store._category=="resources","cash wallet opens resource shelf")
		await close_popups()
		check(gs.cash.to_save()==before_cash and gs.gems==before_gems,"navigation spends no currency")
		gs.reputation_xp=BigNumber.from_float(1e12);gs.first_launch_unix-=3*86400
		gs.cash=BigNumber.from_parts(9.99,300);gs.gems=1000000
		hud.refresh();nav.refresh_locks();rail.refresh();await settle()
		await capture("%d-unlocked-funded"%height)
		for id in ["managers","expedition","event","store"]:
			await tap(nav._buttons[id]);check(Popups.is_open(),"unlocked destination opens: "+id)
			await close_popups()
		records.append({"height":height,"hud_height":hud.size.y,"goals_height":quests.size.y,"nav_height":nav.size.y,"dock_height":dock.size.y})
	# Exercise the real debug reward flow through the new button, not a direct grant.
	gs.rv_state={};var gems_before: int=gs.gems
	await tap(dock._gems_btn,false);dock.refresh();check(RV.is_busy("free_gems"),"gem ad shows pending state");await capture("reward-loading")
	await create_timer(2).timeout;dock.refresh()
	check(gs.gems==gems_before+RV.free_gems_amount(),"gem ad grants exactly once")
	check(RV.remaining_free_gems()==RV.daily_cap("free_gems")-1,"gem ad decrements daily count")
	await tap(dock._boost_btn);await create_timer(2).timeout;dock.refresh()
	check(RV.income_x2_remaining_seconds()>0,"boost button activates timed multiplier")
	await capture("reward-active")
	var venue_records: Array=[]
	root.size=Vector2i(720,1280);root.content_scale_size=root.size
	for vid in root.get_node("DataLoader").venue_order():
		if OS.get_cmdline_user_args().size()>1 and OS.get_cmdline_user_args()[1]=="shell":break
		gs.current_venue=vid;floor_node.retheme(vid)
		for dept in ["ticket","archive","gallery","promotions"]:
			for track in ["staff","speed","value"]:gs.set_dept_level(vid,dept,track,8)
		floor_node.set_rates(root.get_node("Economy").venue_rates(vid));floor_node._refresh_station_ui()
		quests.refresh();hud.refresh();rail.refresh();await settle()
		check(quests._shown_index==0,"new museum selects its first objective")
		var ids: Array=[]
		for i in quests._objective_count():
			var chip: Dictionary=quests._chips[quests._shown_index]
			ids.append(chip.quest_id)
			check(chip.desc.size.y>=chip.desc.get_minimum_size().y-1,"objective text fits height: "+vid)
			if quests._objective_count()>1:await tap(quests._cycle_btn)
		await capture("venue-"+vid)
		venue_records.append({"venue":vid,"objectives":ids})
	var file:=FileAccess.open(output+"/review.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"checks":checks,"failures":failures,"layouts":records,"venues":venue_records},"\t"));file.close()
	print("MAIN_UI_REVIEW checks=",checks," failures=",failures)
	quit(1 if failures else 0)
