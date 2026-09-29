extends "res://tests/venue/test_nav_reachability.gd"
## An unused or dead-end flight can evade tests of operational destinations.
## Each authored stair needs a reachable room at both matching elevations.
func _check_all_venues() -> void:
 for vid in DL.venue_order():
  root.get_node("GameState").current_venue = str(vid)
  _floor.retheme(str(vid))
  for room in _floor._theme.rooms:
   var from_level := int(room.get("level",0))
   var to_level := int(room.get("rise_to",from_level))
   if from_level==to_level:continue
   var rect: Rect2 = room.rect
   var axis: String = room.get("stair_axis","x" if rect.size.x>=rect.size.y else "y")
   var along := Vector2.RIGHT if axis=="x" else Vector2.DOWN
   var across := Vector2.DOWN if axis=="x" else Vector2.RIGHT
   var length: float = rect.size.x if axis=="x" else rect.size.y
   var width: float = rect.size.y if axis=="x" else rect.size.x
   var sides: Array = []
   for end_ in 2:
    var expected: int = from_level if end_==0 else to_level
    if bool(room.get("rise_reverse",false)):expected = to_level if end_==0 else from_level
    var candidates: Array[Vector2i] = []
    for sample in 7:
     var point := rect.position+along*(-.35 if end_==0 else length+.35)+across*width*(.20+.1*sample)
     var id: Vector2i = _floor._nav_id(point)
     var neighbor: Dictionary = _floor._theme.room_at(Vector2(id)*.25)
     if neighbor.is_empty() or neighbor.get("id")==room.id:continue
     if int(neighbor.get("level",0))!=expected or int(neighbor.get("rise_to",expected))!=expected:continue
     if _floor._nav.is_point_solid(id):continue
     if _floor._nav.get_id_path(_floor._nav_id(_floor._door_g),id).is_empty():continue
     candidates.append(id)
    sides.append(candidates)
    check(not candidates.is_empty(),"%s %s end %d has a reachable landing at level %d" % [vid,room.id,end_,expected])
   var crossed := false
   for a in sides[0]:
    for b in sides[1]:
     var route: Array[Vector2i] = _floor._nav.get_id_path(a,b)
     for id in route:
      if _floor._theme.room_at(Vector2(id)*.25).get("id","")==room.id:crossed = true
   check(crossed,str(vid)+" "+room.id+" actually connects its two landings")
