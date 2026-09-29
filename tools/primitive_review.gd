extends SceneTree
var vp: SubViewport
var node: Node2D
var primitive:=false
var output: String
func _initialize() -> void:call_deferred("run")
func draw_test() -> void:
 for y in range(20):
  for x in range(20):
   var at:=Vector2(x*29+13,y*27+12)
   var q:=PackedVector2Array([at,at+Vector2(13,6),at+Vector2(2,19),at+Vector2(-11,12)])
   var color:=Color(.2+x*.03,.2+y*.03,.45,.65 if (x+y)%2 else 1)
   if primitive:node.draw_primitive(q,PackedColorArray([color]),PackedVector2Array())
   else:node.draw_colored_polygon(q,color)
func sample(label: String) -> void:
 node.queue_redraw()
 for i in range(5):await process_frame
 await RenderingServer.frame_post_draw
 vp.get_texture().get_image().save_png(output+"/"+label+".png")
 print(label," draw_calls=",Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
func run() -> void:
 output=OS.get_cmdline_user_args()[0]
 root.get_node("SaveSystem").set_process(false)
 vp=SubViewport.new();vp.size=Vector2i(600,580);vp.render_target_update_mode=SubViewport.UPDATE_ALWAYS;root.add_child(vp)
 node=Node2D.new();node.draw.connect(draw_test);vp.add_child(node)
 await sample("polygons")
 primitive=true;await sample("primitives")
 quit(0)
