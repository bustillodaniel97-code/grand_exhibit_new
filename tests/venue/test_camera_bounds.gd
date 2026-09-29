extends "res://tests/venue/test_nav_reachability.gd"
## Regression: a wide museum must pan at default zoom, not only after zoom-in.
func _check_all_venues() -> void:
 _floor.retheme("grand_river")
 _floor._fit_canvas()
 _floor._pan_camera(Vector2(-10000,0))
 check(_floor._camera_pan.x < -20, "Grand River can reveal its right wing at default zoom")
 var right: Vector2 = _floor._canvas.position + _floor.Iso.to_screen(Vector2(16,0)) * _floor._canvas.scale.x
 check(right.x <= _floor.size.x - 30, "right wing fits inside view after panning")
 _floor._pan_camera(Vector2(20000,0))
 var left: Vector2 = _floor._canvas.position + _floor.Iso.to_screen(Vector2(4,18)) * _floor._canvas.scale.x
 check(left.x >= 30, "opposite pan reveals portico edge")
 check(_floor._camera_pan.x < 1000, "pan remains bounded")
 # The grounded conservatory is an overview-sized building. Its four working
 # departments must be visible on arrival without making the player find a wing.
 _floor.retheme("celestial_conservatory")
 var overview_clear := true
 for room in _floor._theme.rooms:
  var r: Rect2=room["rect"]
  for g in [r.position,Vector2(r.end.x,r.position.y),r.end,Vector2(r.position.x,r.end.y)]:
   var p: Vector2=_floor._canvas.position+_floor.Iso.to_screen(g)*_floor._canvas.scale.x
   if p.x<12 or p.x>_floor.size.x-12 or p.y<72 or p.y>_floor.size.y-12:overview_clear=false
 check(overview_clear,"Celestial's whole floor fits the portrait overview")
 _floor.retheme("ironwood_citadel")
 overview_clear=true
 for room in _floor._theme.rooms:
  var r: Rect2=room["rect"]
  var level := maxi(int(room.get("level",0)),int(room.get("rise_to",0)))
  for g in [r.position,Vector2(r.end.x,r.position.y),r.end,Vector2(r.position.x,r.end.y)]:
   var world: Vector2=_floor.Iso.to_screen(g)
   var foot: Vector2=_floor._canvas.position+world*_floor._canvas.scale.x
   var top: Vector2=_floor._canvas.position+(world+Vector2(0,-level*74-66))*_floor._canvas.scale.x
   if foot.x<12 or foot.x>_floor.size.x-12 or top.y<12 or foot.y>_floor.size.y-12:overview_clear=false
 check(overview_clear,"Ironwood's court, raised armory and working wings fit the overview")
 _floor.retheme("pelagic_crown")
 overview_clear=true
 for room in _floor._theme.rooms:
  var r: Rect2=room["rect"]
  for g in [r.position,Vector2(r.end.x,r.position.y),r.end,Vector2(r.position.x,r.end.y)]:
   var world: Vector2=_floor.Iso.to_screen(g)
   var foot: Vector2=_floor._canvas.position+world*_floor._canvas.scale.x
   var top: Vector2=_floor._canvas.position+(world+Vector2(0,-72))*_floor._canvas.scale.x
   if foot.x<12 or foot.x>_floor.size.x-12 or top.y<12 or foot.y>_floor.size.y-12:overview_clear=false
 check(overview_clear,"Pelagic's lagoon, pavilion and research vault fit the overview")
 _floor.set_size(Vector2(720,910))
 _floor.retheme("chronos_spire")
 overview_clear=true
 for room in _floor._theme.rooms:
  var r: Rect2=room["rect"]
  var level := maxi(int(room.get("level",0)),int(room.get("rise_to",0)))
  for g in [r.position,Vector2(r.end.x,r.position.y),r.end,Vector2(r.position.x,r.end.y)]:
   var world: Vector2=_floor.Iso.to_screen(g)
   var foot: Vector2=_floor._canvas.position+world*_floor._canvas.scale.x
   var top: Vector2=_floor._canvas.position+(world+Vector2(0,-level*74-66))*_floor._canvas.scale.x
   if foot.x<12 or foot.x>_floor.size.x-12 or top.y<12 or foot.y>_floor.size.y-12:overview_clear=false
 check(overview_clear,"Chronos's four-storey clock walk and ground-level working halls fit the overview")
 _floor.set_size(Vector2(720,910))
 _floor.retheme("empyrean_palace")
 overview_clear=true
 for room in _floor._theme.rooms:
  var r: Rect2=room["rect"]
  var level := maxi(int(room.get("level",0)),int(room.get("rise_to",0)))
  for g in [r.position,Vector2(r.end.x,r.position.y),r.end,Vector2(r.position.x,r.end.y)]:
   var world: Vector2=_floor.Iso.to_screen(g)
   var foot: Vector2=_floor._canvas.position+world*_floor._canvas.scale.x
   var top: Vector2=_floor._canvas.position+(world+Vector2(0,-level*74-66))*_floor._canvas.scale.x
   if foot.x<12 or foot.x>_floor.size.x-12 or top.y<12 or foot.y>_floor.size.y-12:overview_clear=false
 check(overview_clear,"Empyrean's court, raised loggia and working wings fit the portrait overview")
 _floor.set_size(Vector2(720,910))
 _floor.retheme("infinite_museum")
 overview_clear=true
 for room in _floor._theme.rooms:
  var r: Rect2=room["rect"]
  var level := maxi(int(room.get("level",0)),int(room.get("rise_to",0)))
  for g in [r.position,Vector2(r.end.x,r.position.y),r.end,Vector2(r.position.x,r.end.y)]:
   var world: Vector2=_floor.Iso.to_screen(g)
   var foot: Vector2=_floor._canvas.position+world*_floor._canvas.scale.x
   var top: Vector2=_floor._canvas.position+(world+Vector2(0,-level*74-66))*_floor._canvas.scale.x
   if foot.x<12 or foot.x>_floor.size.x-12 or top.y<12 or foot.y>_floor.size.y-12:overview_clear=false
 check(overview_clear,"Infinite Museum's central gallery, upper collections and observatory fit the portrait overview")
