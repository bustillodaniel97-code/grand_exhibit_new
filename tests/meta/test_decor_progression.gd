extends SceneTree
var failures:=0
func check(ok: bool,label: String) -> void:
 if not ok:failures+=1;printerr("FAIL: ",label)
func _initialize() -> void:call_deferred("run")
func run() -> void:
 root.get_node("SaveSystem").set_process(false)
 var gs: Node=root.get_node("GameState");var dl: Node=root.get_node("DataLoader")
 var ps=load("res://scripts/meta/prestige_system.gd");var ds=load("res://scripts/meta/decor_system.gd")
 for vid in dl.venue_order():
  gs.reset_to_new_game();gs.current_venue=vid;gs.cash=BigNumber.from_parts(9.99,300);gs.gems=0
  var vs: Dictionary=gs.venue_state(vid)
  for ms in dl.milestones[vid]:vs.milestones.append(ms.id)
  for track in ps.core_tracks():gs.set_dept_level(vid,track[0],track[1],int(dl.get_venue(vid).track_level_cap))
  check(not ps.gate_met(vid),str(vid)+" completed operations cannot bypass empty decor")
  check(not ps.graduate(),str(vid)+" move rejected before furnishing")
  check(ps.readiness_progress(vid)<1,str(vid)+" HUD cannot read complete")
  check("Furnish" in ps.block_reason(),str(vid)+" explains furnishing block")
  for did in dl.decor:
   var def: Dictionary=dl.decor[did]
   if int(def.get("cost_gems",0))>0 or bool(def.get("event_exclusive",false)):continue
   if ps.decor_met(vid):break
   check(ds.buy_decor(vid,did),str(vid)+" cash design purchase "+str(did))
  check(ps.gate_met(vid),str(vid)+" cash-only furnishings complete readiness")
  check(gs.gems==0,str(vid)+" requires no gems")
  var placed: Array=vs.decor.values().duplicate()
  for did in placed:check(ds.remove_decor(vid,did),"storage round trip")
  check(not ps.gate_met(vid),str(vid)+" bought designs in storage do not satisfy gate")
  for did in placed:check(ds.place_decor(vid,did),"free replacement")
  check(ps.gate_met(vid),str(vid)+" replacing restores readiness")
  if ps.next_venue_id()!="":
   check(ps.graduate(),str(vid)+" decorated venue can advance")
   check(not ps.decor_met(gs.current_venue),"new venue requires its own furnishings")
 gs.reset_to_new_game();var vid: String=gs.current_venue;gs.cash=BigNumber.from_parts(9.99,300)
 for did in ["welcome_planter","oak_bench","reading_lamps"]:ds.buy_decor(vid,did)
 check(ps.decor_done(vid)==3 and not ps.decor_met(vid),"piece count alone cannot bypass decor quality")
 print("DECOR_PROGRESSION failures=",failures);quit(1 if failures else 0)
