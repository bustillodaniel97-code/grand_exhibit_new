extends SceneTree
var failures:=0
func _initialize() -> void:call_deferred("run")
func check(ok: bool,message: String) -> void:
	if not ok:failures+=1;printerr("FAIL ",message)
func find_floor(node: Node) -> Node:
	if node.get_script()!=null and node.get_script().resource_path=="res://scenes/venue/floor/venue_floor.gd":return node
	for child in node.get_children():
		var found:=find_floor(child)
		if found!=null:return found
	return null
func run() -> void:
	if not OS.has_environment("GRAND_EXHIBIT_TEST_RUN") or OS.get_environment("XDG_DATA_HOME").is_empty():quit(2);return
	var gs: Node=root.get_node("GameState");gs.reset_to_new_game();gs.ready_flag=true
	gs.cash=load("res://scripts/core/big_number.gd").from_parts(9,300);gs.gems=1000000
	var cash: String=gs.cash.to_notation()
	root.get_node("SaveSystem").set_process(false);root.get_node("Economy").set_process(false)
	root.get_node("SaveSystem").save_now()
	var game: Node=load("res://scenes/main.tscn").instantiate();root.add_child(game)
	var picker: Node=load("res://tools/playtest_venue_picker.gd").new();root.add_child(picker)
	await process_frame
	var floor_node:=find_floor(root)
	check(picker.venues.size()==12,"all12 museums selectable")
	check(not picker.visit("invalid_venue"),"reject invalid venue")
	for id in picker.venues:
		check(picker.visit(id),"visit "+id)
		check(gs.current_venue==id and floor_node._theme.id==id,"real floor changes to "+id)
		check(gs.cash.to_notation()==cash and gs.gems==1000000,"currency retained")
		check(gs.dept_level(id,"ticket","staff")==1,"jump does not max stations")
	picker.visit("whispering_pines")
	load("res://scripts/meta/decor_system.gd").buy_decor("whispering_pines","brass_fountain")
	picker.visit("copper_kettle");picker.visit("whispering_pines")
	check(load("res://scripts/meta/decor_system.gd").owned("whispering_pines","brass_fountain"),"return retains local decor")
	var event:=InputEventKey.new();event.keycode=KEY_F6;event.pressed=true
	Input.parse_input_event(event)
	await process_frame
	check(picker.dialog.visible,"F6 opens actual chooser")
	await RenderingServer.frame_post_draw
	if not OS.get_cmdline_user_args().is_empty():root.get_texture().get_image().save_png(OS.get_cmdline_user_args()[0])
	picker.dialog.hide()
	picker.queue_free();game.queue_free();await process_frame;await process_frame
	print("PLAYTEST_PICKER_REVIEW failures=",failures)
	quit(0 if failures==0 else 1)
