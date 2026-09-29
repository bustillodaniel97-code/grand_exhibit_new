extends SceneTree
func _initialize() -> void:call_deferred("run")
func run() -> void:
 root.get_node("SaveSystem").set_process(false)
 var gs: Node=root.get_node("GameState");gs.reset_to_new_game();gs.ready_flag=true
 var f: Node=load("res://scenes/venue/floor/venue_floor.tscn").instantiate();f.set_size(Vector2(720,760));root.add_child(f)
 for n in root.get_children():n.process_mode=Node.PROCESS_MODE_DISABLED
 var checked:=0;var failures:=0
 for vid in root.get_node("DataLoader").venue_order():
  gs.current_venue=vid;f.retheme(vid)
  var b: Rect2=f._theme.bounds.grow(1)
  for y in range(floori(b.position.y),ceili(b.end.y)):
   for x in range(floori(b.position.x),ceili(b.end.x)):
    for offset in [Vector2.ZERO,Vector2(.001,.001),Vector2(.2,.7),Vector2(.5,.5),Vector2(.999,.999)]:
     var point: Vector2=Vector2(x,y)+offset;checked+=1
     if not is_equal_approx(f._porter_layout._height_at(point),f._theme.lift_at(point)):failures+=1;printerr("FAIL height ",vid," ",point)
 print("Height cache samples=",checked," failures=",failures);quit(1 if failures else 0)
