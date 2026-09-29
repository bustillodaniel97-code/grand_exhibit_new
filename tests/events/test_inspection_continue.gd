extends SceneTree
var failures := 0
func check(ok: bool, label: String) -> void:
 if not ok:failures += 1;printerr("FAIL: ",label)
 else:print("PASS: ",label)
func _initialize() -> void:call_deferred("run")
func run() -> void:
 var gs := root.get_node("GameState")
 gs.reset_to_new_game();gs.ready_flag = true;gs.gems = 100
 var screen: Control = load("res://scenes/events/inspection_screen.gd").new()
 root.add_child(screen)
 screen._es()["opened_at"] = root.get_node("ClockGuard").now()
 screen._open_battle(0,[],20)
 var battle: Control = screen._battle
 battle._boss_hp = 42.0;battle._moves = 0;battle._over = true
 var board: Array = battle._engine.grid().duplicate(true)
 screen._continue_with_gems()
 check(gs.gems == 70,"paid continuation spends exactly 30 gems")
 check(battle.battle_state().moves == 20 and battle.battle_state().hp == 42.0,"restores full moves while preserving dealt damage")
 check(battle._engine.grid() == board,"continuation preserves the board")
 screen._continue_with_gems()
 check(gs.gems == 70,"repeat tap on resumed attempt cannot charge again")
 battle._moves = 0;battle._over = true
 gs.gems = 29
 screen._continue_with_gems()
 check(gs.gems == 29 and battle.battle_state().over,"insufficient gems leave attempt and wallet unchanged")
 check(battle.continue_battle(.5) and battle.battle_state().moves == 10,"half continuation restores half the original allowance")
 battle._moves = 0;battle._over = true
 screen._continue_pending = true
 screen._on_continue_ad("inspection_continue",true,{"battle_id":battle.get_instance_id(),"reward_token":"forged"})
 check(battle.battle_state().over,"forged ad result cannot resume")
 screen._premium_continues = 5;gs.gems = 100
 screen._continue_with_gems()
 check(gs.gems == 100 and battle.battle_state().over,"premium continuation cap cannot charge or resume")
 screen._premium_continues = 0
 var ads := root.get_node("AdService")
 ads.debug_ads = true
 await create_timer(.5).timeout
 screen._request_continue_ad()
 await create_timer(2.0).timeout
 check(not battle.battle_state().over and battle.battle_state().moves == 10,"verified simulator ad resumes with half moves")
 check(gs.gems == 100,"rewarded continuation does not spend gems")
 battle._over = true
 battle._boss_hp = 0
 check(not battle.continue_battle(1.0),"won battle cannot resume")
 screen.free()
 await process_frame
 print("Inspection continuation failures: ",failures)
 quit(1 if failures else 0)
