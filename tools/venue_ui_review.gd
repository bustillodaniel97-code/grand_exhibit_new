extends "res://tools/main_ui_review.gd"
## Native popup review. All progress is a disposable in-memory fixture.
var toasts: Array=[]
var progression: GDScript
var source_hashes: Dictionary={}
func _initialize() -> void:
	call_deferred("run");call_deferred("_watchdog")
func _watchdog() -> void:
	await create_timer(240).timeout
	printerr("FAIL venue review timeout");quit(1)
func descendants(n: Node) -> Array:
	var out: Array=[]
	for c in n.get_children():
		out.append(c);out.append_array(descendants(c))
	return out
func horizontal_fit(screen: Control,scroll: ScrollContainer,label: String) -> void:
	var bounds:=scroll.get_global_rect()
	for n in descendants(screen._list):
		if n is Control and n.is_visible_in_tree():
			var rect: Rect2=n.get_global_rect()
			check(rect.position.x>=bounds.position.x-1 and rect.end.x<=bounds.end.x+1,label+" horizontal bounds "+str(n.get_path()))
func ready_fixture(gs: Node,dl: Node,vid: String,ready: bool) -> void:
	gs.current_venue=vid
	var done: Array=[]
	if ready:
		for m in dl.milestones[vid]:done.append(str(m.id))
	gs.venue_state(vid)["milestones"]=done
	for track in progression.core_tracks():
		gs.set_dept_level(vid,str(track[0]),str(track[1]),int(dl.get_venue(vid).get("track_level_cap",100)) if ready else 1)
func run() -> void:
	if not OS.has_environment("GRAND_EXHIBIT_TEST_RUN") or OS.get_environment("XDG_DATA_HOME").is_empty():quit(2);return
	Popups=load("res://scripts/ui/popup_manager.gd");progression=load("res://scripts/meta/prestige_system.gd")
	output=OS.get_cmdline_user_args()[0];DirAccess.make_dir_recursive_absolute(output)
	root.size=Vector2i(720,1280);root.content_scale_size=root.size
	var gs: Node=root.get_node("GameState");var dl: Node=root.get_node("DataLoader")
	root.get_node("SaveSystem").set_process(false);root.get_node("Economy").set_process(false)
	var main: Node=load("res://scenes/main.tscn").instantiate();root.add_child(main)
	await create_timer(2).timeout;await close_popups()
	main.find_child("VenueFloor",true,false).set_process(false)
	root.get_node("EventBus").toast_requested.connect(func(t: String):toasts.append(t))
	var order: Array=dl.venue_order()
	var focused: bool=OS.get_cmdline_user_args().size()>1 and OS.get_cmdline_user_args()[1]=="confirmation"
	for height in [1280,1000]:
		root.size=Vector2i(720,height);root.content_scale_size=root.size;await settle()
		for index in ([0,5] if focused else [0,5,11]):
			for ready in ([true] if focused else [false,true]):
				var vid: String=order[index]
				ready_fixture(gs,dl,vid,ready)
				var before_cash: Dictionary=gs.cash.to_save();var before_gems: int=gs.gems
				var before_closed: Array=gs.venues_closed.duplicate()
				Popups.open("res://scenes/meta/prestige_screen.tscn")
				await create_timer(2).timeout
				var screen: Control=find_script(main,"res://scenes/meta/prestige_screen.gd")
				check(screen!=null,"actual venue popup opens")
				source_hashes["prestige_screen.gd"]=screen.get_script().source_code.sha256_text()
				source_hashes["popup_manager.gd"]=Popups.source_code.sha256_text()
				var scroll: ScrollContainer=screen._list.get_parent()
				var card: Control=Popups._instance._stack.back().get_meta("popup_card")
				var label: String="%d-%02d-%s"%[height,index+1,"ready" if ready else "locked"]
				check(root.get_visible_rect().encloses(card.get_global_rect()),label+" actual popup fits viewport")
				horizontal_fit(screen,scroll,label)
				var action: Button=screen._action_bar.get_child(0)
				check_button(action,label+" pinned action")
				check(card.get_global_rect().encloses(action.get_global_rect()),label+" action inside popup")
				check(scroll.get_global_rect().end.y<=action.get_global_rect().position.y,label+" action below scroll")
				for n in descendants(screen._list):
					if n is TextureRect and str(n.name).begins_with("VenueArtwork_"):
						check(n.texture!=null,label+" artwork loaded "+n.name)
				await capture(label+"-top")
				toasts.clear();await tap(action)
				if ready and index<11:
					check(screen._confirm.visible,label+" ready action asks confirmation")
					check(root.get_visible_rect().encloses(Rect2(Vector2(screen._confirm.position),Vector2(screen._confirm.size))),label+" confirmation fits viewport")
					for button in [screen._confirm.get_ok_button(),screen._confirm.get_cancel_button()]:
						check(screen._confirm.get_visible_rect().encloses(button.get_global_rect()),label+" confirmation button fits dialog "+button.text)
						check(button.size.x>=48 and button.size.y>=48,label+" confirmation touch size "+button.text)
						records.append({"case":label,"dialog_position":str(screen._confirm.position),"dialog_size":str(screen._confirm.size),"dialog_scale":screen._confirm.content_scale_factor,"button":button.text,"button_rect":str(button.get_global_rect()),"button_size":str(button.size),"button_custom_minimum":str(button.custom_minimum_size),"button_minimum":str(button.get_minimum_size()),"button_combined_minimum":str(button.get_combined_minimum_size())})
					await capture(label+"-confirmation")
					# Native dialog cancellation is local, never an actual graduation.
					var cancel_event:=InputEventMouseButton.new()
					cancel_event.button_index=MOUSE_BUTTON_LEFT;cancel_event.pressed=true
					cancel_event.position=Vector2(screen._confirm.position)+screen._confirm.get_cancel_button().get_global_rect().get_center()
					root.push_input(cancel_event,true)
					var cancel_release:=cancel_event.duplicate();cancel_release.pressed=false
					root.push_input(cancel_release,true);await settle()
					check(not screen._confirm.visible,label+" confirmation cancelled")
					if screen._confirm.visible:screen._confirm.hide() # Prevent cascading input failures.
				else:
					check(not screen._confirm.visible and not toasts.is_empty(),label+" blocked action explains reason")
					check(str(toasts.back())==progression.block_reason(),label+" exact gate explanation")
				check(gs.current_venue==vid and gs.venues_closed==before_closed and gs.cash.to_save()==before_cash and gs.gems==before_gems,label+" browsing and cancellation do not alter progression or currency")
				scroll.scroll_vertical=int(scroll.get_v_scroll_bar().max_value);await settle()
				await capture(label+"-bottom")
				if index==0 and not ready:
					var toggle: Button
					for n in descendants(screen._list):
						if n is Button and n.text=="Explore all 12 museums":toggle=n
					check(toggle!=null,"collection toggle exists")
					scroll.ensure_control_visible(toggle);await settle();await tap(toggle)
					var grid: GridContainer=screen._list.get_child(screen._list.get_child_count()-1)
					check(grid.visible and grid.get_child_count()==12,"gallery expands all 12 actual museums")
					var textures: Array=[]
					for n in descendants(grid):
						if n is TextureRect and str(n.name).begins_with("VenueArtwork_"):
							var id: String=str(n.name).trim_prefix("VenueArtwork_")
							check(n.texture!=null and n.texture.resource_path=="res://art/venue_previews/"+id+".png","gallery correct texture "+id)
							textures.append(id)
					check(textures==order,"gallery shows every museum in campaign order")
					horizontal_fit(screen,scroll,label+" expanded")
					for row in range(6):
						scroll.ensure_control_visible(grid.get_child(row*2));await settle()
						await capture("%d-gallery-row-%d"%[height,row+1])
					scroll.scroll_vertical=int(scroll.get_v_scroll_bar().max_value);await settle()
					check(scroll.get_global_rect().encloses(grid.get_child(11).get_global_rect()),"last gallery card fully reachable")
					check(card.get_global_rect().encloses(action.get_global_rect()),"expanded gallery preserves pinned button")
					scroll.ensure_control_visible(toggle);await settle();await tap(toggle)
					check(not grid.visible and grid.get_child_count()==0,"collection collapses and frees previews")
				records.append({"case":label,"card":str(card.get_global_rect()),"scroll":str(scroll.get_global_rect()),"button":str(action.get_global_rect())})
				await close_popups()
	var f:=FileAccess.open(output+"/review.json",FileAccess.WRITE)
	f.store_string(JSON.stringify({"checks":checks,"failures":failures,"source_hashes":source_hashes,"cases":records},"\t"));f.close()
	print("VENUE_UI_REVIEW checks=",checks," failures=",failures)
	quit(1 if failures else 0)
