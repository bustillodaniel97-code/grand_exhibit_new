extends SceneTree
class Sheet extends Node2D:
 var entries: Array = []
 var textures: Array[Texture2D] = []
 func _ready() -> void:
  var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string('res://data/venues.json'))
  entries = data.venues
  for entry in entries:
   var im := Image.load_from_file('res://art/environment/%s-planter.png' % entry.id)
   textures.append(ImageTexture.create_from_image(im))
  queue_redraw()
 func _draw() -> void:
  draw_rect(Rect2(0,0,1200,960),Color('#e5e8de'))
  var font := ThemeDB.fallback_font
  draw_string(font,Vector2(24,35),'GRAND EXHIBIT / TWELVE VENUE DECOR KITS',HORIZONTAL_ALIGNMENT_LEFT,-1,25,Color('#273d40'))
  for k in entries.size():
   var pos := Vector2(18+(k%4)*297,55+(k/4)*295)
   draw_rect(Rect2(pos,Vector2(285,282)),Color('#ced7c8'))
   draw_texture_rect(textures[k],Rect2(pos+Vector2(22,0),Vector2(240,240)),false)
   draw_string(font,pos+Vector2(10,256),str(entries[k].name),HORIZONTAL_ALIGNMENT_LEFT,265,17,Color('#273d40'))
func _initialize() -> void:call_deferred('run')
func run() -> void:
 root.get_node('SaveSystem').set_process(false)
 var vp := SubViewport.new();vp.size=Vector2i(1200,960);vp.render_target_update_mode=SubViewport.UPDATE_ALWAYS;root.add_child(vp)
 vp.add_child(Sheet.new())
 await process_frame
 await process_frame
 await RenderingServer.frame_post_draw
 vp.get_texture().get_image().save_png('/home/bustillo/GrandExhibit-Recovery-2026-09-05/evidence/environment-rework/twelve-planter-kits.png')
 quit()
