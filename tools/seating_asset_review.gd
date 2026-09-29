extends SceneTree
## Native Character/Exhibits review of the staged bench generation. No save edits.
const Character:=preload("res://scenes/venue/floor/character.gd")
const Exhibits:=preload("res://scenes/venue/floor/exhibits.gd")
const Props:=preload("res://scenes/venue/floor/museum_props.gd")
const Iso:=preload("res://scenes/venue/floor/iso.gd")
var vp: SubViewport
var output: String
var source: String
func _initialize() -> void:call_deferred("run")
func caption(parent: Node, text: String, at: Vector2) -> void:
	var label:=Label.new();label.text=text;label.position=at
	label.add_theme_font_size_override("font_size",12)
	label.add_theme_color_override("font_color",Color("213640"));parent.add_child(label)
func capture(name: String) -> void:
	for i in 3:await process_frame
	await RenderingServer.frame_post_draw
	var err:=vp.get_texture().get_image().save_png(output.path_join(name))
	if err!=OK:printerr("SEATING_CAPTURE_ERROR ",err);quit(1)
func run() -> void:
	var args:=OS.get_cmdline_user_args();output=args[0];source=args[1]
	DirAccess.make_dir_recursive_absolute(output)
	for n in root.get_children():n.process_mode=Node.PROCESS_MODE_DISABLED
	vp=SubViewport.new();vp.size=Vector2i(960,1080);vp.render_target_update_mode=SubViewport.UPDATE_ALWAYS;root.add_child(vp)
	var specs: Array=JSON.parse_string(FileAccess.get_file_as_string(source.path_join("benches.json")))
	specs=specs.filter(func(item):return "-bench-" in str(item.asset))
	var records: Array=[];var index:=0
	while index<specs.size():
		var stage:=Node2D.new();vp.add_child(stage)
		var background:=Polygon2D.new();background.polygon=PackedVector2Array([Vector2.ZERO,Vector2(960,0),Vector2(960,1080),Vector2(0,1080)]);background.color=Color("d8e2e1");stage.add_child(background)
		caption(stage,"Grand Exhibit | actual character renderer + staged furniture | 2.5x view",Vector2(18,10))
		var actors: Array=[]
		for slot in 12:
			if index>=specs.size():break
			var item: Dictionary=specs[index];var filename: String=item.asset
			var parts:=filename.trim_suffix(".png").split("-bench-")
			var dimensions:=parts[1].split("-")
			var length:=float(dimensions[0])/100.0;var axis:=dimensions[1];var flip:=dimensions[2]=="1"
			var image:=Image.load_from_file(source.path_join("benches/"+filename));image.generate_mipmaps()
			Props._textures["res://art/environment/"+filename]=ImageTexture.create_from_image(image)
			var card:=Node2D.new();card.position=Vector2(160+(slot%3)*320,185+(slot/3)*250)-Iso.ORIGIN*2.5;card.scale=Vector2.ONE*2.5;card.y_sort_enabled=true;stage.add_child(card)
			caption(stage,filename.trim_suffix(".png"),Vector2(10+(slot%3)*320,40+(slot/3)*250))
			var spec:={"kind":"bench","at":Vector2.ZERO,"len":length,"axis":axis,"flip":flip,"museum_venue":parts[0]}
			var painter:=Exhibits.painter("bench",spec)
			var bench:=Node2D.new();bench.position=Iso.to_screen(Exhibits.anchor(spec));card.add_child(bench)
			bench.draw.connect(func():bench.draw_set_transform(-bench.position);painter.call(bench))
			var along:=Vector2.RIGHT if axis=="x" else Vector2.DOWN
			var front:=Vector2.DOWN if axis=="x" else Vector2.RIGHT
			var across:=front*(.14 if flip else .30)
			if flip:front=-front
			var seats: Array=[.5] if length<1.5 else [.25,.75]
			for seat in seats:
				var c:=Character.new();c.set_look_slot((index*2+actors.size())%24);card.add_child(c);c.set_process(false)
				c.scale=Vector2.ONE*c.age_scale();c.position=Iso.to_screen(along*(length*float(seat))+across)
				if not c.begin_seating(front,Vector2.ZERO):printerr("SEATING_PACKET_MISSING ",c.identity);quit(1);return
				c.advance_seating(1,true);c._process(0);actors.append(c)
				records.append({"asset":filename,"identity":c.identity,"front":str(front),"position":str(c.position),"scale":c.scale.y})
			index+=1
		await capture("seated-page-%02d.png"%ceili(float(index)/12))
		if index==12:
			for frame in 33:
				for c in actors:c._seating_progress=1.0-float(frame)/32;c._process(0);c.queue_redraw()
				await capture("rise-%02d.png"%frame)
		stage.free()
		print("SEATING_ASSET_PAGE ",index)
	var f:=FileAccess.open(output.path_join("review-manifest.json"),FileAccess.WRITE);f.store_string(JSON.stringify(records,"\t"));f.close()
	quit(0)
