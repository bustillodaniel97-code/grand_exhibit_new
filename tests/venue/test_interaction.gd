extends SceneTree
## REAL-INPUT interaction regression (player bug: "unable to upgrade
## stations/workers"). Boots the actual VenueView (floor + bottom sheet) and
## drives synthetic InputEventMouseButton presses through the engine's gui
## dispatch — no direct handler calls. Asserts the full chain:
##   tap ticket room -> dept sheet opens for ticket
##   tap gallery WHILE the ticket sheet is open -> sheet switches (the sheet
##     dim must not swallow floor taps — the original root cause)
##   tap UPGRADE with cash -> level +1 and cash down
##   tap UPGRADE broke -> EventBus.toast_requested "Need $X more"
##   tap dead carpet -> nothing
## Run: godot --headless --path <repo> -s tests/venue/test_interaction.gd
## (exit 0 = pass). Headless windows are 64x64, so screen positions are mapped
## logical -> window px through Viewport.get_final_transform() — the same path
## real device taps take under stretch mode canvas_items / aspect keep.

var _frame: int = 0
var _fail: int = 0
var _phase: int = 0
var _phase_t: float = 0.0

var _vv: Control
var _floor: Control
var _canvas: Node2D
var _sheet: Control
var _taps: Array = []
var _toasts: Array = []
var _cash_before: BigNumber
var _level_before: int = 0

func check(cond: bool, msg: String) -> void:
	if cond:
		print("PASS: ", msg)
	else:
		_fail += 1
		printerr("FAIL: ", msg)

func _initialize() -> void:
	var autoloads := [
		["EventBus", "res://autoload/event_bus.gd"],
		["DataLoader", "res://autoload/data_loader.gd"],
		["ClockGuard", "res://autoload/clock_guard.gd"],
		["Analytics", "res://autoload/analytics.gd"],
		["AdService", "res://autoload/ad_service.gd"],
		["IAPService", "res://autoload/iap_service.gd"],
		["GameState", "res://autoload/game_state.gd"],
		["SaveSystem", "res://autoload/save_system.gd"],
		["Economy", "res://autoload/economy.gd"],
	]
	for pair in autoloads:
		if root.has_node(pair[0]):
			continue
		var n: Node = (load(pair[1]) as GDScript).new()
		n.name = pair[0]
		root.add_child(n)

	var gs: Node = root.get_node("GameState")
	root.get_node("DataLoader").reload_all()
	gs.reset_to_new_game()
	gs.ready_flag = true

func _process(delta: float) -> bool:
	_frame += 1
	if _frame == 3:
		# Build the venue view here (not in _initialize): venue_view._ready
		# only runs once the SceneTree is fully up.
		_vv = (load("res://scenes/venue/venue_view.tscn") as PackedScene).instantiate()
		root.add_child(_vv)  # full-rect anchors fill the 720x1280 logical viewport
		_floor = _vv.find_child("VenueFloor", true, false)
		_canvas = _floor.get_child(0)
		_sheet = _vv.find_child("DeptSheet", true, false)
		_floor.dept_selected.connect(func(d: String) -> void: _taps.append(d))
		root.get_node("EventBus").toast_requested.connect(func(t: String) -> void: _toasts.append(t))
	if _frame < 6:
		return false
	_phase_t += delta
	if _frame > 3600:
		printerr("FAIL: test timed out")
		quit(1)
		return true
	match _phase:
		0:  # Tap the ticket hall with a real click.
			_click_room(Vector2(350, 620), "ticket hall")
			_next()
		1:
			if _phase_t >= 0.1:
				check(_taps == ["ticket"], "real click on ticket room emits dept_selected (got %s)" % [_taps])
				check(_sheet.visible and _vv._open_dept == "ticket",
					"ticket tap opens the dept sheet for ticket (visible=%s open='%s')" % [
						_sheet.visible, _vv._open_dept])
				_next()
		2:  # Tap the gallery WHILE the ticket sheet is open (dim regression).
			_click_room(Vector2(234, 204), "gallery")
			_next()
		3:
			if _phase_t >= 0.1:
				check(_taps == ["ticket", "gallery"],
					"floor tap passes the open sheet dim (got %s)" % [_taps])
				check(_vv._open_dept == "gallery",
					"sheet switches to gallery while a sheet was open (open='%s')" % _vv._open_dept)
				_next()
		4:  # Close via the sheet's real X button.
			var close_btn: Button = null
			for b in _sheet.find_children("*", "Button", true, false):
				# ui_kit swaps a lone "✕" label for a cross icon (a glyph that
				# small is a poor touch target), so match the role tag it sets
				# rather than the now-empty label text.
				if (b as Button).get_meta("role", "") == "close":
					close_btn = b
					break
			check(close_btn != null, "sheet exposes a close button")
			if close_btn == null:
				_next()
				return false
			_click_at(close_btn.get_global_rect().get_center(), "sheet X")
			_next()
		5:
			if _phase_t >= 0.35:  # close tween is 0.18 s (wall time)
				check(not _sheet.visible, "sheet closes via its X button")
				_next()
		6:  # Re-open ticket, fund the museum, click the real UPGRADE button.
			_click_room(Vector2(350, 620), "ticket hall")
			_next()
		7:
			if _phase_t >= 0.4:  # wait out the sheet open tween before aiming
				check(_vv._open_dept == "ticket", "ticket sheet re-opened for purchase")
				root.get_node("GameState").add_cash(BigNumber.from_float(1000))
				var panel: Node = _find_visible_panel()
				check(panel != null and panel.dept_id == "ticket", "visible panel is ticket")
				if panel == null:
					_next()
					return false
				var btn: Button = panel._row_btn["staff"]
				check(not btn.disabled, "staff upgrade button is tappable when affordable")
				_level_before = root.get_node("GameState").dept_level(
					root.get_node("GameState").current_venue, "ticket", "staff")
				_cash_before = root.get_node("GameState").cash
				_click_at(btn.get_global_rect().get_center(), "staff upgrade")
				_next()
		8:
			if _phase_t >= 0.1:
				var gs: Node = root.get_node("GameState")
				var level_after: int = gs.dept_level(gs.current_venue, "ticket", "staff")
				check(level_after == _level_before + 1,
					"real upgrade click buys: ticket staff %d -> %d" % [_level_before, level_after])
				check(gs.cash.lt(_cash_before),
					"cash decreased by the purchase (%s -> %s)" % [
						_cash_before.to_notation(), gs.cash.to_notation()])
				_next()
		9:  # Drain cash, click an upgrade we cannot afford -> toast.
			var gs: Node = root.get_node("GameState")
			gs.spend_cash(gs.cash)  # drain to zero
			var panel: Node = _find_visible_panel()
			var btn: Button = panel._row_btn["speed"] if panel else null
			if btn == null:
				check(false, "ticket panel available for unaffordable click")
				_next()
				return false
			_click_at(btn.get_global_rect().get_center(), "speed upgrade (broke)")
			_next()
		10:
			if _phase_t >= 0.1:
				var need_toast: bool = false
				for t in _toasts:
					if str(t).begins_with("Need $"):
						need_toast = true
				check(need_toast, "unaffordable upgrade tap toasts 'Need $X more' (got %s)" % [_toasts])
				var gs: Node = root.get_node("GameState")
				check(gs.dept_level(gs.current_venue, "ticket", "speed") == 1,
					"unaffordable upgrade did not buy")
				_next()
		11:  # Dead carpet: no dept, no toast, no sheet change.
			_vv._close_sheet()
			_taps.clear()
			_toasts.clear()
			_next()
		12:
			if _phase_t >= 0.35:
				check(not _sheet.visible, "sheet closed before carpet tap")
				_click_room(Vector2(400, 740), "dead carpet")
				_next()
		13:
			if _phase_t >= 0.1:
				check(_taps.is_empty(), "dead carpet tap emits no dept_selected (got %s)" % [_taps])
				check(_toasts.is_empty(), "dead carpet tap requests no toast (got %s)" % [_toasts])
				check(not _sheet.visible, "dead carpet tap opens nothing")
				_next()
		14:
			print("---")
			if _fail == 0:
				print("ALL INTERACTION CHECKS PASSED")
			quit(0 if _fail == 0 else 1)
			return true
	return false

func _next() -> void:
	_phase += 1
	_phase_t = 0.0

func _find_visible_panel() -> Node:
	for p in _vv.find_children("*", "PanelContainer", true, false):
		if p.name == "DeptPanel" and p.visible:
			return p
	return null

## Synthesize a press+release over the CENTER of a floor room (canvas coords).
func _click_room(canvas_pos: Vector2, label: String) -> void:
	var local: Vector2 = _canvas.position + canvas_pos * _canvas.scale.x
	_click_at(_floor.get_global_transform() * local, label)

## Synthesize a real left-click at a logical viewport position.
func _click_at(logical_pos: Vector2, label: String) -> void:
	var win: Vector2 = root.get_final_transform() * logical_pos
	print("click %s @logical %s" % [label, logical_pos])
	for pressed in [true, false]:
		var ev := InputEventMouseButton.new()
		ev.button_index = MOUSE_BUTTON_LEFT
		ev.pressed = pressed
		ev.position = win
		ev.global_position = win
		Input.parse_input_event(ev)
