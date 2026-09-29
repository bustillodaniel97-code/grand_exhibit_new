extends SceneTree
## Actual engine-dispatched taps, not direct handler calls. Touch bounds must
## remain distinct and station-owned while the world pans, zooms and rethemes.
var failures:=0
var floor: Control
var selected: Array=[]
var collected: Array=[]
var taps:=0
func check(ok: bool, message: String) -> void:
 if not ok:failures+=1;printerr("FAIL: ",message)
func _initialize() -> void:call_deferred("run")
func run() -> void:
 var gs: Node=root.get_node("GameState")
 var dl: Node=root.get_node("DataLoader")
 var ec: Node=root.get_node("Economy")
 root.get_node("SaveSystem").set_process(false);ec.set_process(false)
 gs.reset_to_new_game();gs.ready_flag=true
 floor=load("res://scenes/venue/floor/venue_floor.tscn").instantiate()
 floor.size=Vector2(720,910);root.add_child(floor);floor.set_process(false)
 floor.item_selected.connect(func(dept: String,index: int) -> void:selected.append([dept,index]))
 root.get_node("EventBus").item_collected.connect(func(venue: String,dept: String,index: int,_amount: Variant) -> void:collected.append([venue,dept,index]))
 await process_frame;await process_frame
 for vid in dl.venue_order():
  gs.reset_to_new_game();gs.ready_flag=true
  gs.current_venue=str(vid);floor.retheme(str(vid));floor.set_process(false)
  floor.size=Vector2(720,910);floor._fit_canvas();floor._refresh_station_ui()
  verify_bounds(str(vid)+" early")
  check(floor._station_chips.size()==1 and floor._station_chips[0].visible,str(vid)+" initial station remains visible")
  gs.set_dept_level(str(vid),"ticket","staff",floor._max_windows)
  floor.retheme(str(vid));floor.set_process(false);floor._refresh_cast();floor._refresh_station_ui()
  for scenario in range(5):
   floor.size=Vector2(720,640) if scenario==1 else (Vector2(600,720) if scenario==2 else Vector2(720,910))
   floor._user_zoom=1.65 if scenario==3 else (2.3 if scenario==4 else 1.0)
   floor._camera_pan=Vector2(80,-50) if scenario==3 else (Vector2(-120,70) if scenario==4 else Vector2.ZERO)
   floor._fit_canvas();await process_frame
   verify_bounds(str(vid)+" scenario "+str(scenario))
   for index in floor._station_chips.size():
    var chip: Button=floor._station_chips[index]
    var up: Button=floor._station_upgrade[index]
    if not chip.visible:continue
    var points: Array=[Vector2(.5,.5)]
    if scenario==0:points.append_array([Vector2(.06,.12),Vector2(.94,.88)])
    for fraction in points:
     var items: Array=gs.dept_items(str(vid),"ticket")
     var total:=0.0
     for i in items.size():
      items[i].pending=BigNumber.from_float((i+1)*25).to_save()
      items[i].collect_ready_at=0;total+=(i+1)*25
     gs.pending_cash[str(vid)]=BigNumber.from_float(total)
     var before: BigNumber=gs.cash
     floor._refresh_station_ui();collected.clear();selected.clear()
     await tap(chip,fraction)
     check(collected==[[str(vid),"ticket",index]],str(vid)+" collect tap owns station "+str(index)+" "+str(fraction)+" events="+str(collected))
     check(gs.cash.eq(before.add(BigNumber.from_float((index+1)*25))),str(vid)+" tap banks only its own station")
     check(selected.is_empty(),str(vid)+" collect did not accidentally trigger upgrade")
     if scenario==0 and index==0 and fraction==Vector2(.5,.5):
      var after_collect: BigNumber=gs.cash
      collected.clear();selected.clear()
      await tap(chip,fraction)
      check(collected.is_empty() and selected.is_empty() and gs.cash.eq(after_collect),str(vid)+" cooldown tap neither recollects nor changes station")
     collected.clear();selected.clear()
     await tap(up,fraction)
     check(selected==[["ticket",index]],str(vid)+" upgrade tap selects station "+str(index)+" events="+str(selected))
     check(collected.is_empty(),str(vid)+" upgrade did not collect neighbouring cash")
   if failures>0:break
  # Maxed controls retire without moving their collect target or exposing a
  # hidden upgrade target. Initial single-station banks remain reachable too.
  floor.size=Vector2(720,910);floor._user_zoom=1.0;floor._camera_pan=Vector2.ZERO;floor._fit_canvas()
  var positions: Array=[]
  for button in floor._station_chips:positions.append(button.position)
  gs.set_item_level(str(vid),"ticket",0,ec.item_max_level())
  floor._refresh_station_ui()
  check(not floor._station_upgrade[0].visible and floor._station_upgrade[0].disabled,str(vid)+" maxed upgrade cannot intercept taps")
  for i in positions.size():check(floor._station_chips[i].position==positions[i],str(vid)+" maxing a station does not move its controls")
  if floor._station_chips[0].visible:
   selected.clear();collected.clear()
   await tap(floor._station_upgrade[0],Vector2(.5,.5))
   check(selected.is_empty() and collected.is_empty(),str(vid)+" hidden upgrade receives no actual click")
  print("STATION_POINTER ",vid," failures=",failures," taps=",taps)
  if failures>0:break
 print("STATION POINTER RESULT: ",taps," dispatched taps; ",failures," failures")
 quit(0 if failures==0 else 1)
func verify_bounds(context: String) -> void:
 var occupied: Array[Rect2]=[]
 var visible:=Rect2(Vector2(12,12),floor.size-Vector2(24,24))
 for index in floor._station_chips.size():
  var chip: Button=floor._station_chips[index]
  var anchor: Vector2=floor._station_anchor_points[index]
  check(chip.visible==visible.has_point(anchor),context+" visible desk retains its control")
  for button in [chip,floor._station_upgrade[index]]:
   if not button.visible:continue
   var rect: Rect2=button.get_rect()
   check(rect.size.x>=48 and rect.size.y>=48,context+" touch area stays at least 48 pixels")
   check(visible.encloses(rect),context+" control stays within floor viewport")
   for other in occupied:check(not rect.intersects(other),context+" controls do not overlap: "+str(button.name)+" "+str(rect)+" vs "+str(other))
   occupied.append(rect)
func tap(button: Button, fraction: Vector2) -> void:
 var logical: Vector2=button.get_global_transform()*(button.size*fraction)
 var position: Vector2=root.get_final_transform()*logical
 for pressed in [true,false]:
  var event:=InputEventMouseButton.new()
  event.button_index=MOUSE_BUTTON_LEFT;event.pressed=pressed
  event.position=position;event.global_position=position
  Input.parse_input_event(event)
  await process_frame
 taps+=1
