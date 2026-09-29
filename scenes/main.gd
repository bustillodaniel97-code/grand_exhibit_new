extends Control
## Boot root — real game shell (venue-ui branch).
## Boot sequence: DataLoader -> SaveSystem/GameState -> offline earnings -> Analytics
## -> build HUD + nav + VenueView -> Welcome Back popup when warranted.

const UI := preload("res://scripts/ui/ui_kit.gd")
const Popups := preload("res://scripts/ui/popup_manager.gd")
const HudScene := preload("res://scenes/ui/hud.tscn")
const NavScene := preload("res://scenes/ui/bottom_nav.tscn")
const BoostDockScene := preload("res://scenes/ui/boost_dock.tscn")
const SideRailScene := preload("res://scenes/ui/side_rail.tscn")
const VenueScene := preload("res://scenes/venue/venue_view.tscn")
const PopupLayerScene := preload("res://scenes/ui/popup_layer.tscn")
const AdaptiveMusic := preload("res://scenes/audio/adaptive_music.gd")

const Consent := preload("res://scripts/monetization/consent.gd")
const VisitorSystem := preload("res://scripts/meta/visitor_system.gd")
const Interstitials := preload("res://scripts/monetization/interstitials.gd")

const WELCOME_BACK_PATH := "res://scenes/ui/welcome_back.tscn"

var _toast_panel: PanelContainer
var _toast_lbl: Label
var _toast_tween: Tween

func _ready() -> void:
	UI.install_default_font()
	DataLoader.reload_all()
	if not SaveSystem.load_game():
		GameState.reset_to_new_game()
	GameState.ready_flag = true
	var offline: Dictionary = SaveSystem.compute_offline_and_apply()
	# Privacy first: Analytics writes nothing to disk and ads stay non-personalized
	# until the choice is resolved, so this has to run before the first event.
	Consent.resolve_at_boot()
	Interstitials.note_session_start()
	Analytics.session_start()
	_build_shell()
	add_child(AdaptiveMusic.new())
	if int(offline.get("seconds", 0)) > 30:
		Popups.open(WELCOME_BACK_PATH, offline)
	print("BOOT OK — cash=", GameState.cash.to_notation(), " rep=", GameState.rep_level())

func _build_shell() -> void:
	var bg := ColorRect.new()
	bg.color = preload("res://scripts/ui/museum_chrome.gd").BG
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	var layout := VBoxContainer.new()
	layout.set_anchors_preset(Control.PRESET_FULL_RECT)
	layout.add_theme_constant_override("separation", 0)
	add_child(layout)

	layout.add_child(HudScene.instantiate())

	var venue: Control = VenueScene.instantiate()
	venue.size_flags_vertical = Control.SIZE_EXPAND_FILL
	layout.add_child(venue)

	# Rewarded-video dock: a real layout row between the world and the nav bar, so
	# it can never overlap the HUD, the nav or the venue's department sheet.
	layout.add_child(BoostDockScene.instantiate())

	layout.add_child(NavScene.instantiate())

	# Vertical meta rail. NOT a row in `layout`: the whole point is that it costs
	# no vertical space, so it floats over the world as a sibling of the layout
	# and positions itself against the right edge under the venue strip. Added
	# after the layout so it draws over the world, before the popup layer
	# (CanvasLayer 10) so every screen still covers it.
	add_child(SideRailScene.instantiate())
	# First-run walkthrough; ignores the mouse, so it can never block play.
	add_child(preload("res://scenes/ui/tutorial.gd").new())

	add_child(PopupLayerScene.instantiate())
	_build_toast()
	_build_grade()

	EventBus.toast_requested.connect(show_toast)
	EventBus.reputation_level_up.connect(_on_reputation_level_up)

## Full-screen finishing pass. Sits above the world, the popups and the toast so
## the whole frame is graded as one image — grading only the world would make the
## UI look like it was composited in from somewhere else.
func _build_grade() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 90          # above popups (10) and toasts (30), below nothing
	add_child(layer)
	# Refresh after world smoothing and UI; screen-reading passes otherwise share
	# the earlier world-only snapshot and erase subsequently drawn controls.
	var copy := BackBufferCopy.new()
	copy.copy_mode = BackBufferCopy.COPY_MODE_VIEWPORT
	layer.add_child(copy)
	var rect := ColorRect.new()
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE   # must never eat a tap
	var mat := ShaderMaterial.new()
	mat.shader = load("res://scenes/ui/grade.gdshader")
	rect.material = mat
	layer.add_child(rect)


# --- Toasts (SPEC §9: bottom-center, 2s) --------------------------------------

func _build_toast() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 30
	add_child(layer)

	var holder := Control.new()
	holder.set_anchors_preset(Control.PRESET_FULL_RECT)
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(holder)

	_toast_panel = PanelContainer.new()
	_toast_panel.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_toast_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_toast_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_toast_panel.offset_top -= 160.0
	_toast_panel.offset_bottom -= 110.0
	_toast_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_toast_panel.add_theme_stylebox_override("panel", UI.make_panel(UI.INK, 10, 0))
	_toast_panel.modulate.a = 0.0
	_toast_panel.visible = false
	holder.add_child(_toast_panel)

	_toast_lbl = UI.make_label("", 22)
	_toast_lbl.add_theme_color_override("font_color", Color.WHITE)
	_toast_panel.add_child(_toast_lbl)

func show_toast(text: String) -> void:
	if _toast_tween and _toast_tween.is_valid():
		_toast_tween.kill()
	_toast_lbl.text = text
	_toast_panel.visible = true
	_toast_panel.modulate.a = 1.0
	_toast_tween = create_tween()
	_toast_tween.tween_interval(1.4)
	_toast_tween.tween_property(_toast_panel, "modulate:a", 0.0, 0.6)
	_toast_tween.tween_callback(func() -> void: _toast_panel.visible = false)

func _on_reputation_level_up(level: int, rewards: Dictionary) -> void:
	var gems: int = int(rewards.get("gems", 0))
	var text := "Reputation %d! +%d gems" % [level, gems]
	var names: Array = []
	for t in VisitorSystem.unlocked_at(level):
		names.append(str(t.get("name", "")))
	if not names.is_empty():
		text += "\nNew visitors: " + ", ".join(PackedStringArray(names))
	show_toast(text)
