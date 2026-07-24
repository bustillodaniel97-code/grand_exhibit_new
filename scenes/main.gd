extends Control
## Boot root (SCAFFOLD VERSION — venue-ui branch replaces with full game shell).
## Boots data, loads save, applies offline earnings, shows a status label.

func _ready() -> void:
	DataLoader.reload_all()
	var loaded: bool = SaveSystem.load_game()
	if not loaded:
		GameState.reset_to_new_game()
	GameState.ready_flag = true
	var offline: Dictionary = SaveSystem.compute_offline_and_apply()
	Analytics.session_start()
	var label := Label.new()
	label.text = "Grand Exhibit\nSave loaded: %s\nCash: %s\nOffline: +%s (%ds)" % [
		str(loaded), GameState.cash.to_notation(),
		offline["amount"].to_notation(), offline["seconds"]]
	label.position = Vector2(40, 200)
	add_child(label)
	print("BOOT OK — cash=", GameState.cash.to_notation(), " rep=", GameState.rep_level())
