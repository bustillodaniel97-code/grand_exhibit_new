extends Node
## Development launcher only; never attached by the shipping main scene.
const Popups:=preload("res://scripts/ui/popup_manager.gd")
var dialog: ConfirmationDialog
var picker: OptionButton
var venues: Array=[]
func _ready() -> void:
	if not OS.has_environment("GRAND_EXHIBIT_TEST_RUN") or OS.get_environment("XDG_DATA_HOME").is_empty():
		queue_free();return
	venues=DataLoader.venue_order()
	dialog=ConfirmationDialog.new();dialog.title="Playtest — choose a museum"
	dialog.ok_button_text="Visit museum";add_child(dialog)
	var content:=VBoxContainer.new();content.add_theme_constant_override("separation",12)
	dialog.add_child(content)
	var note:=Label.new();note.text="This test save keeps each museum's\nupgrades and decor when you switch."
	content.add_child(note)
	picker=OptionButton.new();picker.custom_minimum_size=Vector2(340,48)
	for id in venues:picker.add_item(str(DataLoader.get_venue(id).get("name",id)))
	content.add_child(picker)
	dialog.confirmed.connect(func():visit(str(venues[picker.selected])))
func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode==KEY_F6:
		picker.select(maxi(0,venues.find(GameState.current_venue)))
		dialog.popup_centered(Vector2i(420,190));get_viewport().set_input_as_handled()
func visit(id: String) -> bool:
	if id not in venues:return false
	while Popups.is_open():Popups.close_top()
	var previous:=GameState.current_venue
	if id not in GameState.venues_unlocked:GameState.venues_unlocked.append(id)
	GameState.venues_closed.erase(id)
	GameState.current_venue=id
	GameState.venue_state(id)
	load("res://scripts/meta/quest_system.gd").ensure_active_quests(id)
	EventBus.prestige_performed.emit(previous,id)
	get_tree().root.get_node("SaveSystem").save_now()
	return true
