extends RefCounted
class_name HudSkillsTab
## Skills side-panel tab: an OSRS-style level grid (one cell per skill) plus the hover
## card that shows a skill's name + XP-to-next-level bar. Owns its cells, the hover
## widgets and its refresh; the HUD drives refresh()/update_cell() from its central
## EventBus dispatch (level_up, xp_gained, game_loaded) and handles the click (skill guide).

const UiScale := preload("res://scripts/ui/ui_scale.gd")
const ItemIcon := preload("res://scripts/ui/item_icon.gd")

var hud  # the OSRS HUD (untyped — the WorldFx3D `_ctx` pattern)
var _cells: Dictionary = {}     # skill -> level Label
var _hover: PanelContainer      # shared hover card (skill name + XP-to-next bar)
var _hover_name: Label
var _hover_bar: ProgressBar
var _hover_xp: Label


func _init(h) -> void:
	hud = h


## OSRS-style grid. Clicking a cell opens the skill guide; hovering shows the XP card.
func build() -> Control:
	var skills_grid := GridContainer.new()
	skills_grid.name = "Skills"
	skills_grid.columns = 3
	for skill: String in GameState.SKILLS:
		var cell := PanelContainer.new()
		cell.add_theme_stylebox_override("panel", hud._style(hud.STONE_DARK))
		cell.custom_minimum_size = UiScale.v2(Vector2(84, 40))
		var skill_copy := skill
		var locked := GameState.is_skill_locked(skill)
		cell.mouse_default_cursor_shape = Control.CURSOR_ARROW if locked else Control.CURSOR_POINTING_HAND
		cell.gui_input.connect(func(event: InputEvent) -> void:
			if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
				hud.show_ui_click_marker(event.global_position)
				if GameState.is_skill_locked(skill_copy):
					return   # locked skills are faded + don't open the skill guide
				hud.open_skill_guide(skill_copy))
		cell.mouse_entered.connect(func() -> void: _show_hover(skill_copy, cell))
		cell.mouse_exited.connect(func() -> void: _hide_hover())
		var hb := HBoxContainer.new()
		hb.alignment = BoxContainer.ALIGNMENT_CENTER
		hb.add_theme_constant_override("separation", UiScale.i(5))
		hb.mouse_filter = Control.MOUSE_FILTER_IGNORE
		hb.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
		var icon := ItemIcon.new()
		icon.kind = SkillRegistry.icon(skill)
		icon.tint = SkillRegistry.color(skill)
		icon.custom_minimum_size = UiScale.v2(Vector2(26, 26))
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		hb.add_child(icon)
		var lbl := Label.new()
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		lbl.add_theme_font_size_override("font_size", UiScale.i(14))
		lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		hb.add_child(lbl)
		cell.add_child(hb)
		if locked:
			# Fade the skill icon + level, then float a lock glyph centred over the cell.
			hb.modulate.a = 0.32
			var lockwrap := CenterContainer.new()
			lockwrap.mouse_filter = Control.MOUSE_FILTER_IGNORE
			var lockicon := ItemIcon.new()
			lockicon.kind = "lock"
			lockicon.tint = Color(0.82, 0.80, 0.74)
			lockicon.custom_minimum_size = UiScale.v2(Vector2(20, 20))
			lockicon.mouse_filter = Control.MOUSE_FILTER_IGNORE
			lockwrap.add_child(lockicon)
			cell.add_child(lockwrap)   # added after hb -> drawn on top
		skills_grid.add_child(cell)
		_cells[skill] = lbl
	return skills_grid


func refresh() -> void:
	for skill: String in _cells:
		update_cell(skill)


func update_cell(skill: String) -> void:
	if not _cells.has(skill):
		return
	var lbl: Label = _cells[skill]
	var lvl := GameState.level(skill)
	lbl.text = str(lvl)
	if GameState.is_skill_locked(skill):
		lbl.tooltip_text = "%s — locked (coming soon)" % skill.capitalize()
		return
	var cur := float(DataRegistry.xp_for_level(lvl))
	var next := float(DataRegistry.xp_for_level(lvl + 1))
	var frac := clampf((GameState.xp(skill) - cur) / maxf(next - cur, 1.0), 0.0, 1.0)
	lbl.tooltip_text = "%s — level %d\n%.0f XP (%.0f%% to next)" % [skill.capitalize(), lvl, GameState.xp(skill), frac * 100.0]


## Hover card over a skill cell: the skill's name + a bar of progress to the next level.
func _show_hover(skill: String, cell: Control) -> void:
	if _hover == null or not is_instance_valid(_hover):
		_hover = PanelContainer.new()
		_hover.add_theme_stylebox_override("panel", hud._style(Color(0.12, 0.12, 0.14, 0.97), Color(0.55, 0.5, 0.35)))
		_hover.z_index = 200
		_hover.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var vb := VBoxContainer.new()
		vb.add_theme_constant_override("separation", UiScale.i(3))
		_hover_name = Label.new()
		_hover_name.add_theme_font_size_override("font_size", UiScale.i(13))
		_hover_name.add_theme_color_override("font_color", Color(0.95, 0.92, 0.75))
		vb.add_child(_hover_name)
		_hover_bar = ProgressBar.new()
		_hover_bar.show_percentage = false
		_hover_bar.custom_minimum_size = UiScale.v2(Vector2(150, 10))
		_hover_bar.max_value = 1.0
		vb.add_child(_hover_bar)
		_hover_xp = Label.new()
		_hover_xp.add_theme_font_size_override("font_size", UiScale.i(10))
		_hover_xp.add_theme_color_override("font_color", Color(0.78, 0.82, 0.7))
		vb.add_child(_hover_xp)
		_hover.add_child(vb)
		hud.hud_root.add_child(_hover)
	var lvl := GameState.level(skill)
	var cur := GameState.xp(skill)
	if GameState.is_skill_locked(skill):
		_hover_name.text = "%s — locked" % skill.capitalize()
		_hover_bar.value = 0.0
		_hover_xp.text = "Coming soon"
		_hover.reset_size()
		var lpos := cell.global_position + Vector2(-_hover.size.x - UiScale.f(6.0), 0.0)
		lpos.x = maxf(lpos.x, UiScale.f(4.0))
		_hover.global_position = lpos
		_hover.visible = true
		return
	_hover_name.text = "%s — Level %d" % [skill.capitalize(), lvl]
	if lvl >= DataRegistry.max_level:
		_hover_bar.value = 1.0
		_hover_xp.text = "%s XP · MAX level" % _fmt_int(int(cur))
	else:
		var xp_lvl := float(DataRegistry.xp_for_level(lvl))
		var xp_next := float(DataRegistry.xp_for_level(lvl + 1))
		var span := maxf(xp_next - xp_lvl, 1.0)
		_hover_bar.value = clampf((cur - xp_lvl) / span, 0.0, 1.0)
		_hover_xp.text = "%s / %s XP · %s to level %d" % [
			_fmt_int(int(cur - xp_lvl)), _fmt_int(int(span)), _fmt_int(int(ceil(xp_next - cur))), lvl + 1]
	_hover.reset_size()
	# Sit the card just left of the cell (the skills panel hugs the right edge).
	var pos := cell.global_position + Vector2(-_hover.size.x - UiScale.f(6.0), 0.0)
	pos.x = maxf(pos.x, UiScale.f(4.0))
	_hover.global_position = pos
	_hover.visible = true


func _hide_hover() -> void:
	if _hover != null and is_instance_valid(_hover):
		_hover.visible = false


## Thousands-separated integer, e.g. 1234567 -> "1,234,567".
static func _fmt_int(n: int) -> String:
	var s := str(n)
	var out := ""
	var c := 0
	for i: int in range(s.length() - 1, -1, -1):
		out = s[i] + out
		c += 1
		if c % 3 == 0 and i > 0:
			out = "," + out
	return out
