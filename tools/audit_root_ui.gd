extends SceneTree
func _initialize()->void:call_deferred("run")
func run()->void:
 if OS.get_environment("GRAND_EXHIBIT_TEST_RUN")!="1" or not OS.get_environment("XDG_DATA_HOME").begins_with("/tmp/grand-audit-root"):
  printerr("AUDIT_REFUSED: requires an isolated /tmp/grand-audit-root profile");quit(2);return
 var gs=root.get_node("GameState");root.get_node("SaveSystem").set_process(false)
 gs.reset_to_new_game();gs.ready_flag=true
 root.get_node("Economy").set_process(false)
 var layer=load("res://scenes/ui/popup_layer.tscn").instantiate();root.add_child(layer)
 var popup=load("res://scripts/ui/popup_manager.gd")
 print("ANDROID_BACK default_quit_on_go_back=",get("quit_on_go_back"))
 var screens=["store/store_screen","managers/managers_screen","managers/lootbox_screen","meta/decor_screen","meta/prestige_screen","meta/statistics_screen","events/expedition_screen","events/inspection_screen"]
 for dimensions in [Vector2i(720,1280),Vector2i(360,640),Vector2i(720,500)]:
  root.size=dimensions;root.content_scale_size=dimensions
  for screen in screens:
   popup.open("res://scenes/"+screen+".tscn",{})
   await create_timer(.25).timeout
   var holder=layer._stack.back();var card=holder.get_meta("popup_card")
   print("POPUP ",screen," viewport=",dimensions," card=",card.get_global_rect()," fits=",Rect2(Vector2.ZERO,Vector2(dimensions)).encloses(card.get_global_rect()))
   popup.close_top();await process_frame
 # Abruptly close before delayed layout or animation callbacks run.
 for screen in screens:
  for i in 3:
   popup.open("res://scenes/"+screen+".tscn",{})
   popup.close_top()
  await create_timer(.3).timeout
 popup.open("res://scenes/store/store_screen.tscn",{})
 await process_frame
 root.propagate_notification(Node.NOTIFICATION_WM_GO_BACK_REQUEST)
 print("ANDROID_BACK popup_still_open_after_notification=",popup.is_open())
 popup.close_top();await create_timer(.3).timeout
 print("AUDIT_ROOT_UI_FINISHED")
 quit()
