extends SceneTree
func _initialize() -> void:call_deferred("run")
func run() -> void:
 root.get_node("SaveSystem").set_process(false)
 var gs := root.get_node("GameState")
 gs.reset_to_new_game();gs.ready_flag = true;gs.gems = 100
 var vp := SubViewport.new()
 vp.size = Vector2i(720,1280);vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
 root.add_child(vp)
 var screen: Control = load("res://scenes/events/inspection_screen.gd").new()
 screen.size = Vector2(720,1280);vp.add_child(screen)
 screen._es()["opened_at"] = root.get_node("ClockGuard").now()
 screen._open_battle(0,[],20)
 screen._battle._moves = 0
 screen._battle._finish("lose")
 await create_timer(.7).timeout
 await process_frame
 await process_frame
 await RenderingServer.frame_post_draw
 vp.get_texture().get_image().save_png("/home/bustillo/GrandExhibit-Recovery-2026-09-05/evidence/inspection-continue.png")
 quit()
