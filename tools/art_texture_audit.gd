extends SceneTree
func _initialize() -> void:call_deferred("run")
func run() -> void:
 root.get_node("SaveSystem").set_process(false)
 var checked := 0
 var failed := 0
 var motion_bytes := 0
 var motion_count := 0
 var vehicle_bytes := 0
 var vehicle_count := 0
 var activity_bytes := 0
 var activity_count := 0
 var seating_bytes := 0
 var seating_count := 0
 var cart_bytes := 0
 var cart_count := 0
 for folder in ["visitors","staff","environment","npc_motion","vehicles","npc_activities","npc_seating","npc_carts"]:
  for filename in DirAccess.get_files_at("res://art/"+folder):
   if not filename.ends_with(".png"):continue
   var texture: Texture2D = load("res://art/%s/%s" % [folder,filename])
   if texture == null:
    failed+=1;continue
   var im:=texture.get_image()
   if im == null or im.is_empty() or not im.has_mipmaps():
    printerr("FAIL texture/mipmaps: ",filename);failed+=1
   if folder=="npc_motion" and im!=null:
    motion_count+=1;motion_bytes+=im.get_data_size()
   if folder=="vehicles" and im!=null:
    vehicle_count+=1;vehicle_bytes+=im.get_data_size()
   if folder=="npc_activities" and im!=null:
    activity_count+=1;activity_bytes+=im.get_data_size()
   if folder=="npc_seating" and im!=null:
    seating_count+=1;seating_bytes+=im.get_data_size()
   if folder=="npc_carts" and im!=null:
    cart_count+=1;cart_bytes+=im.get_data_size()
   checked+=1
 print("Imported vehicle textures: ",vehicle_count,"; decoded image bytes with mipmaps: ",vehicle_bytes)
 print("Imported public activity textures: ",activity_count,"; decoded image bytes with mipmaps (whole pool, loaded per feeder in play): ",activity_bytes)
 print("Imported motion textures: ",motion_count,"; decoded image bytes with mipmaps: ",motion_bytes)
 print("Imported seating textures: ",seating_count,"; decoded image bytes with mipmaps (whole pool, owned by resting visitors): ",seating_bytes)
 print("Imported cart textures: ",cart_count,"; decoded image bytes with mipmaps: ",cart_bytes)
 print("Imported art textures checked: ",checked,"; failures: ",failed)
 quit(1 if failed else 0)
