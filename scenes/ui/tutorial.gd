extends Control
## Tutorial — the first-run walkthrough (Idle Bank Tycoon's pointing hand).
##
## A bobbing pointer and a speech bubble walk a new player through the first
## loop: collect a desk's coins, upgrade a desk, open a department, then point
## at the Floors and the Dig Site. Each step finishes on the REAL game event
## (EventBus / the sheet actually opening), never on a tap of the overlay: the
## overlay ignores the mouse entirely, so it can never swallow a tap or block a
## player who already knows what to do.
##
## Progress lives in GameState.settings["tutorial_step"] (saved with the game).
## Only a fresh game starts it; existing players never see it.

const Chrome := preload("res://scripts/ui/museum_chrome.gd")
const UI := preload("res://scripts/ui/ui_kit.gd")

const STEPS := [
	{"id": "collect", "text": "Visitors pay at the ticket desks.\nTap the coin to collect your cash!", "target": "chip"},
	{"id": "upgrade", "text": "Upgrade a desk so it serves visitors faster.", "target": "upgrade"},
	{"id": "gallery", "text": "Tap the Nature Hall to see its upgrades.", "target": "gallery"},
	{"id": "floors", "text": "Complete goals to open new floors and make your museum grander!", "target": "floors", "seconds": 7.0},
	{"id": "dig", "text": "Dig up artifacts at the Dig Site to grow your collection.", "target": "dig", "seconds": 7.0},
]

var step := -1
var _bubble: PanelContainer
var _label: Label
var _clock := 0.0
var _t := 0.0

func _ready() -> void:
	name = "Tutorial"
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	z_index = 120
	_bubble = PanelContainer.new()
	_bubble.name = "Bubble"
	_bubble.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := Chrome.panel(18, Color(Chrome.INK, 0.94))
	sb.set_content_margin_all(16)
	sb.set_border_width_all(0)
	sb.shadow_color = Color(0, 0, 0, 0.2)
	sb.shadow_size = 16
	sb.shadow_offset = Vector2(0, 6)
	_bubble.add_theme_stylebox_override("panel", sb)
	_label = UI.make_display_label("", 18, Chrome.PANEL)
	_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_label.custom_minimum_size = Vector2(430, 0)
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bubble.add_child(_label)
	add_child(_bubble)
	EventBus.item_collected.connect(func(_v: String, _d: String, _i: int, _a: Variant) -> void: _event("collect"))
	EventBus.item_upgraded.connect(func(_v: String, _d: String, _i: int, _l: int) -> void: _event("upgrade"))
	step = int(GameState.settings.get("tutorial_step", -1))
	if step < 0:
		# Only a genuinely new museum-one player gets the walkthrough.
		var fresh: bool = GameState.rep_level() <= 1 and GameState.venues_unlocked.size() <= 1
		step = 0 if fresh else STEPS.size()
		GameState.settings["tutorial_step"] = step
	_show()

func active() -> bool:
	return step >= 0 and step < STEPS.size()

func current_id() -> String:
	return str(STEPS[step]["id"]) if active() else ""

func _event(id: String) -> void:
	if current_id() == id:
		advance()

## Move to the next step (public so a skip button / tests can drive it).
func advance() -> void:
	step += 1
	GameState.settings["tutorial_step"] = step
	_clock = 0.0
	_show()

func skip() -> void:
	step = STEPS.size()
	GameState.settings["tutorial_step"] = step
	_show()

func _show() -> void:
	visible = active()
	if active():
		_label.text = str(STEPS[step]["text"])
		_bubble.reset_size()
	queue_redraw()

func _process(delta: float) -> void:
	if not active():
		return
	_t += delta
	var s: Dictionary = STEPS[step]
	if s.has("seconds"):
		_clock += delta
		if _clock >= float(s["seconds"]):
			advance()
			return
	if current_id() == "gallery":
		var view := get_tree().root.find_child("VenueView", true, false)
		if view != null and str(view.get("_open_dept")) == "gallery":
			advance()
			return
	var target := _target_point()
	_bubble.visible = true
	var bsize := _bubble.get_combined_minimum_size()
	var y := clampf(target.y - bsize.y - 110.0, 210.0, size.y - bsize.y - 180.0) if target != Vector2.INF else 260.0
	if target != Vector2.INF and target.y < 520.0:
		y = target.y + 90.0
	_bubble.position = Vector2((size.x - bsize.x) * 0.5, y)
	queue_redraw()

## Where the pointer should point, in this control's coordinates; INF if the
## target is not on screen right now (the bubble still shows).
func _target_point() -> Vector2:
	var s: Dictionary = STEPS[step]
	var floor := get_tree().root.find_child("VenueFloor", true, false)
	var p := Vector2.INF
	match str(s["target"]):
		"chip":
			p = _control_center(floor.find_child("StationCash0", true, false) if floor else null)
		"upgrade":
			p = _control_center(floor.find_child("StationUpgrade0", true, false) if floor else null)
		"gallery":
			if floor != null and floor.get("world") != null:
				var w: Node = floor.get("world")
				var cam: Camera3D = w.get("camera")
				if cam != null:
					var sp: Vector2 = cam.unproject_position(w.dept_center("gallery"))
					p = (floor as Control).get_global_rect().position + sp - get_global_rect().position
		"floors":
			p = _control_center(get_tree().root.find_child("ItemFloors", true, false))
		"dig":
			var nav := get_tree().root.find_child("BottomNav", true, false)
			if nav != null and nav.get("_buttons") is Dictionary:
				p = _control_center((nav.get("_buttons") as Dictionary).get("expedition"))
	return p

func _control_center(c: Variant) -> Vector2:
	if c is Control and (c as Control).is_visible_in_tree():
		return (c as Control).get_global_rect().get_center() - get_global_rect().position
	return Vector2.INF

func _draw() -> void:
	if not active():
		return
	var p := _target_point()
	if p == Vector2.INF:
		return
	var pulse := 0.5 + 0.5 * sin(_t * 5.0)
	draw_arc(p, 30.0 + 8.0 * pulse, 0.0, TAU, 40, Color(Chrome.PANEL, 0.95 - 0.55 * pulse), 4.0, true)
	# An arrow bobbing above the target, pointing at it.
	var tip := p + Vector2(0, -40.0 - 10.0 * pulse)
	var col := Chrome.PANEL
	var ink := Chrome.INK
	var pts := PackedVector2Array([tip, tip + Vector2(-22, -26), tip + Vector2(-9, -26), tip + Vector2(-9, -58),
		tip + Vector2(9, -58), tip + Vector2(9, -26), tip + Vector2(22, -26)])
	draw_colored_polygon(pts, col)
	pts.append(tip)
	draw_polyline(pts, ink, 3.0, true)
