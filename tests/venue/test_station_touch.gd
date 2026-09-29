extends "res://tests/venue/test_station_pointer.gd"
## Exercise the engine's touch-to-mouse path rather than invoking handlers.
func tap(button: Button, fraction: Vector2) -> void:
 var room_events: Array=[]
 var observer:=func(dept: String) -> void:room_events.append(dept)
 floor.dept_selected.connect(observer)
 var active:=button.visible and not button.disabled
 var logical: Vector2=button.get_global_transform()*(button.size*fraction)
 var position: Vector2=root.get_final_transform()*logical
 for pressed in [true,false]:
  var event:=InputEventScreenTouch.new()
  event.index=0;event.pressed=pressed;event.position=position
  Input.parse_input_event(event)
  await process_frame
 taps+=1
 floor.dept_selected.disconnect(observer)
 if active:check(room_events.is_empty(),"station touch must not also open the underlying room: "+str(room_events))
