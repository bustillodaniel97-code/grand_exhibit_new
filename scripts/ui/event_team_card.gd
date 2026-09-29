extends RefCounted
## The same authored manager portrait and selection language in both events.
const UI := preload("res://scripts/ui/ui_kit.gd")
const Chrome := preload("res://scripts/ui/museum_chrome.gd")
const Portrait := preload("res://scenes/managers/manager_portrait.gd")
const BattleMath := preload("res://scripts/events/battle_math.gd")
const ManagerBadge := preload("res://scenes/managers/manager_badge.gd")

static func make(pair: Dictionary, selected: bool) -> Button:
	var definition: Dictionary = pair["def"]
	var state: Dictionary = pair["state"]
	var specialty := str(definition.get("specialty", ""))
	var tint: Color = UI.DEPT_COLORS.get(specialty, Chrome.BRASS)
	var button := Button.new()
	button.custom_minimum_size = Vector2(326, 148)
	button.text = str(definition.get("name", pair["id"]))
	button.tooltip_text = button.text + str(TranslationServer.translate(" · Remove from team") if selected else TranslationServer.translate(" · Add to team"))
	Chrome.button(button, selected)
	for style in ["normal", "hover", "pressed"]:
		var surface := Chrome.panel(14, Chrome.RAISED if selected else Chrome.PANEL)
		surface.border_color = Chrome.TEAL if selected else Chrome.BORDER
		if style == "hover": surface.bg_color = surface.bg_color.lightened(0.06)
		if style == "pressed": surface.bg_color = Chrome.BG
		button.add_theme_stylebox_override(style, surface)
	for key in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		button.add_theme_color_override(key, Color.TRANSPARENT)
	var row := HBoxContainer.new()
	row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	row.offset_left = 12; row.offset_right = -12
	row.offset_top = 12; row.offset_bottom = -12
	row.add_theme_constant_override("separation", 12)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	button.add_child(row)
	var portrait := Portrait.new()
	portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(portrait)
	portrait.setup(definition, 104, true)
	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.alignment = BoxContainer.ALIGNMENT_CENTER
	info.add_theme_constant_override("separation", 5)
	info.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(info)
	var name_label := UI.make_display_label(button.text, 17, Chrome.INK)
	name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info.add_child(name_label)
	info.add_child(UI.make_label("%s · %s" % [ManagerBadge.specialty_name(specialty),
		ManagerBadge.rarity_name(str(definition.get("rarity", "common"))).capitalize()], 14, tint.lerp(Chrome.INK, 0.28)))
	info.add_child(UI.make_label(TranslationServer.translate("Lv %d · Rank %d · Power %d") % [int(state.get("level", 1)),
		int(state.get("rank", 1)),
		int(round(BattleMath.manager_attack(definition, state)))], 14, Chrome.DIM))
	info.add_child(UI.make_display_label(TranslationServer.translate("IN TEAM  ✓") if selected else TranslationServer.translate("+ Add to team"), 14,
		Chrome.TEAL if selected else Chrome.DIM))
	for child in info.get_children(): child.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return button
