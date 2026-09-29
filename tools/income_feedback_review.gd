extends "res://tools/walking_campaign_review.gd"
const Feedback:=preload("res://scenes/venue/floor/income_feedback.gd")
var failures:=0
func check(ok: bool, message: String) -> void:
	if not ok:failures+=1;printerr("FAIL ",message)
func clear_feedback(f: Node) -> void:
	for child in f._canvas.get_children():
		if child is Feedback:child.free()
func run() -> void:
	if not OS.has_environment("GRAND_EXHIBIT_TEST_RUN") or OS.get_environment("XDG_DATA_HOME").is_empty():quit(2);return
	output=OS.get_cmdline_user_args()[0];DirAccess.make_dir_recursive_absolute(output)
	root.get_node("SaveSystem").set_process(false)
	var gs: Node=root.get_node("GameState");gs.reset_to_new_game();seed(918)
	vp=SubViewport.new();vp.size=Vector2i(720,1280);vp.render_target_update_mode=SubViewport.UPDATE_ALWAYS
	root.add_child(vp);vp.add_child(load("res://scenes/main.tscn").instantiate());await create_timer(2).timeout
	for i in 4:load("res://scripts/ui/popup_manager.gd").close_top()
	for node in root.get_children():
		if node!=vp:node.process_mode=Node.PROCESS_MODE_DISABLED
	vp.get_child(0).process_mode=Node.PROCESS_MODE_DISABLED
	var f: Node=find_floor(vp);var records: Array=[]
	for vid in root.get_node("DataLoader").venue_order():
		var args:=OS.get_cmdline_user_args()
		if args.size()>1 and not vid in args[1].split(","):continue
		gs.current_venue=vid
		for dept in ["ticket","archive","gallery","promotions"]:
			for track in ["staff","speed","value"]:gs.set_dept_level(vid,dept,track,8)
		f.retheme(vid);f.set_rates(root.get_node("Economy").venue_rates(vid));f._refresh_station_ui()
		for tick in 240:f.advance_sim(.05)
		update_characters(vp,0);clear_feedback(f)
		var station_count: int=f._station_chips.size()
		for automatic in [true,false]:
			clear_feedback(f)
			for station in station_count:
				var g: Vector2=f._admissions.point(station,Vector2(0,-1))
				seed(990+station);randf_range(-14,14);var expected:=randf()
				seed(990+station)
				f._spawn_float("+$12.3M",g,automatic)
				check(randf()==expected,"feedback preserves next simulation RNG value")
				var receipt: Node2D=f._canvas.get_child(f._canvas.get_child_count()-1)
				check(receipt is Feedback,"feedback uses visual-only node")
				check(receipt.position==f._lifted(g)+Vector2(0,4 if automatic else -8),"receipt follows storey anchor")
				check(receipt.z_index==f._theme.level_at(g)*f.Iso.LEVEL_Z+1,"receipt follows storey depth")
				receipt.animation.pause();receipt.set_progress(.3)
			for zoom in [1.0,2.6]:
				f._user_zoom=zoom;f._fit_canvas()
				if zoom>1:
					var target:=Vector2.ZERO
					for station in station_count:target+=f.station_center(station)
					target/=maxi(1,station_count)
					f._pan_camera(f.size*.5-(target*f._canvas.scale+f._canvas.position))
				await capture(output+"/%s-%s-%s.png"%[vid,"service" if automatic else "collect","overview" if zoom==1 else "close"])
		records.append({"venue":vid,"stations":station_count,"captures":4})
		print("INCOME_FEEDBACK_CAPTURE ",vid)
	var file:=FileAccess.open(output+"/review.json",FileAccess.WRITE);file.store_string(JSON.stringify({"venues":records,"failures":failures},"\t"));file.close()
	print("Income feedback failures: ",failures)
	quit(1 if failures else 0)
