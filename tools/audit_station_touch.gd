extends "res://tests/venue/test_nav_reachability.gd"
## Export actual station touch bounds. The pointer/touch regression tests now
## enforce non-overlap and real dispatch; this tool also writes per-venue JSON.
func _check_all_venues() -> void:
 _floor.set_size(Vector2(720,910))
 var report: Dictionary={}
 for vid in DL.venue_order():
  root.get_node("GameState").current_venue=str(vid)
  _floor.retheme(str(vid))
  root.get_node("GameState").set_dept_level(str(vid),"ticket","staff",_floor._max_windows)
  _floor.retheme(str(vid))
  _floor._refresh_cast()
  _floor._refresh_station_ui()
  _floor._fit_canvas()
  var controls: Array=[]
  for w in _floor._station_chips.size():
   for pair in [["collect",_floor._station_chips[w]],["upgrade",_floor._station_upgrade[w]]]:
    var button: Button=pair[1]
    if not button.visible or button.disabled:continue
    controls.append({"station":w,"action":pair[0],"rect":Rect2(button.position,button.size.max(button.get_combined_minimum_size()))})
  var conflicts: Array=[]
  for i in controls.size():
   for j in range(i+1,controls.size()):
    var first: Dictionary=controls[i]
    var second: Dictionary=controls[j]
    var overlap: Rect2=first.rect.intersection(second.rect)
    if overlap.has_area():
     conflicts.append({"first":str(first.station)+":"+first.action,"second":str(second.station)+":"+second.action,"overlap":str(overlap)})
  report[str(vid)]={"controls":controls.size(),"footprints":controls,"conflicts":conflicts}
  check(conflicts.is_empty(),str(vid)+" station touch regions do not overlap ("+str(conflicts.size())+" conflicts)")
 var output:=OS.get_environment("GRAND_EXHIBIT_TOUCH_REPORT")
 if not output.is_empty():
  var file:=FileAccess.open(output,FileAccess.WRITE)
  file.store_string(JSON.stringify(report,"  ")+"\n")
