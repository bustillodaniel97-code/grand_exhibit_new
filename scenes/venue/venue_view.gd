extends Control
## VenueView (SPEC §9): vertical scroll of the 4 department panels
## (promotions, ticket, archive, gallery) with quests bar embedded on top
## when the meta branch's quests_bar scene exists (loaded by path only).
## Polls Economy.venue_rates every 0.5s to tag the choked department (SPEC §3.5).

const UI := preload("res://scripts/ui/ui_kit.gd")
const DeptPanel := preload("res://scenes/venue/dept_panel.gd")

const QUESTS_BAR_PATH := "res://scenes/meta/quests_bar.tscn"
const DEPT_ORDER: Array[String] = ["promotions", "ticket", "archive", "gallery"]

var _panels := {}  # dept_id -> DeptPanel
var _timer: Timer

func _ready() -> void:
	name = "VenueView"

	var scroll := ScrollContainer.new()
	scroll.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(scroll)

	var margin := MarginContainer.new()
	margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	margin.add_theme_constant_override("margin_left", 12)
	margin.add_theme_constant_override("margin_right", 12)
	margin.add_theme_constant_override("margin_top", 10)
	margin.add_theme_constant_override("margin_bottom", 10)
	scroll.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_theme_constant_override("separation", 14)
	margin.add_child(vbox)

	# Quests bar from the meta branch — embed only if it exists (no cross-branch preload).
	if ResourceLoader.exists(QUESTS_BAR_PATH):
		var qb: Node = (load(QUESTS_BAR_PATH) as PackedScene).instantiate()
		vbox.add_child(qb)

	var venue: Dictionary = DataLoader.get_venue(GameState.current_venue)
	var title := UI.make_label(str(venue.get("name", "Museum")), 28)
	vbox.add_child(title)

	for dept_id in DEPT_ORDER:
		var p := DeptPanel.new()
		p.venue_id = GameState.current_venue
		p.dept_id = dept_id
		_panels[dept_id] = p
		vbox.add_child(p)

	_timer = Timer.new()
	_timer.wait_time = 0.5
	_timer.autostart = true
	_timer.timeout.connect(_poll_rates)
	add_child(_timer)

	_poll_rates()

func _poll_rates() -> void:
	if not GameState.ready_flag:
		return
	var rates: Dictionary = Economy.venue_rates(GameState.current_venue)
	var choke: String = str(rates.get("choke_id", ""))
	for dept_id in _panels.keys():
		_panels[dept_id].set_bottleneck(dept_id == choke)
	if _panels.has("ticket"):
		_panels["ticket"].update_queue(
			float(rates.get("arrival_per_s", 0.0)), float(rates.get("serve_per_s", 0.0)))
