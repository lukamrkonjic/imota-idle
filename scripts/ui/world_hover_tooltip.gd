extends PanelContainer
class_name WorldHoverTooltip
## Floating tooltip anchored above a world entity; sizes to its text.

const UiScaleScript := preload("res://scripts/ui/ui_scale.gd")

const STONE := Color(0.24, 0.22, 0.20)
const STONE_DARK := Color(0.16, 0.15, 0.14)
const COLOR_TITLE := "#d9b84d"
const COLOR_ACTION := "#ffff66"
const COLOR_BODY := "#d1d1c2"

var _body: RichTextLabel
var _margin: float
var _world: Node2D
var _entity: Node2D
var _ui_owner: Control   # set via attach(): a hovered UI control owns the tooltip


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	z_index = 50
	size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	size_flags_vertical = Control.SIZE_SHRINK_BEGIN

	_margin = UiScaleScript.f(12.0)
	var sb := StyleBoxFlat.new()
	sb.bg_color = STONE
	sb.set_corner_radius_all(UiScaleScript.i(3))
	sb.set_border_width_all(1)
	sb.border_color = STONE_DARK
	sb.content_margin_left = _margin
	sb.content_margin_right = _margin
	sb.content_margin_top = _margin
	sb.content_margin_bottom = _margin
	add_theme_stylebox_override("panel", sb)

	_body = RichTextLabel.new()
	_body.bbcode_enabled = true
	_body.fit_content = true
	_body.scroll_active = false
	_body.autowrap_mode = TextServer.AUTOWRAP_OFF
	_body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_body.add_theme_font_size_override("normal_font_size", UiScaleScript.i(13))
	add_child(_body)

	hide()


func show_for(world: Node2D, entity: Node2D, content: Dictionary) -> void:
	_world = world
	_entity = entity
	_apply_content(content)
	visible = true
	_update_position()


func hide_tooltip() -> void:
	visible = false
	_entity = null
	_world = null
	_ui_owner = null


func follow_entity() -> void:
	if visible and _entity != null and is_instance_valid(_entity):
		_update_position()


func _process(_delta: float) -> void:
	# Keep a UI-owned tooltip pinned over its control (e.g. if a panel scrolls). The
	# world tooltip is repositioned separately via follow_entity() from the HUD.
	if visible and _ui_owner != null and is_instance_valid(_ui_owner):
		_position_over_control()


## Same styled tooltip, but for any UI Control (inventory item, equipment slot,
## prayer/spell row). `content` is a Dictionary or a Callable returning one.
func attach(control: Control, content: Variant) -> void:
	control.mouse_entered.connect(func() -> void:
		if not GameSettings.show_hover_tooltip:
			return
		_world = null
		_entity = null
		_ui_owner = control
		_apply_content(content.call() if content is Callable else content)
		if _body.text == "":
			return
		visible = true
		_position_over_control())
	control.mouse_exited.connect(func() -> void:
		if _ui_owner == control:
			hide_tooltip())


## True while a UI control is hovered. The world-hover poll checks this and stands
## down so the world picker (which still finds geometry behind the HUD) can't yank a
## UI tooltip away.
func is_ui_owned() -> bool:
	if _ui_owner != null and not is_instance_valid(_ui_owner):
		_ui_owner = null
	return _ui_owner != null


## Hide only when a world entity (not a UI control) owns the tooltip.
func hide_for_world() -> void:
	if _ui_owner == null:
		hide_tooltip()


func _position_over_control() -> void:
	var rect := _ui_owner.get_global_rect()
	var vp := get_viewport().get_visible_rect().size
	var gap := UiScaleScript.f(8.0)
	var edge := UiScaleScript.f(4.0)
	# Centred above the control with a margin; flip below if it would clip the top.
	var pos := Vector2(rect.position.x + rect.size.x * 0.5 - size.x * 0.5, rect.position.y - size.y - gap)
	if pos.y < edge:
		pos.y = rect.position.y + rect.size.y + gap
	pos.x = clampf(pos.x, edge, maxf(edge, vp.x - size.x - edge))
	pos.y = clampf(pos.y, edge, maxf(edge, vp.y - size.y - edge))
	position = pos


func _apply_content(content: Variant) -> void:
	if typeof(content) != TYPE_DICTIONARY:
		_body.text = ""
		hide()
		return
	var title: String = str(content.get("title", ""))
	var subtitle: String = str(content.get("subtitle", ""))
	var action: String = str(content.get("action", ""))
	var details: Array = content.get("details", [])

	var lines: PackedStringArray = []
	var header := ""
	if not title.is_empty() and not subtitle.is_empty():
		header = "%s  ·  %s" % [title, subtitle]
	elif not title.is_empty():
		header = title
	elif not subtitle.is_empty():
		header = subtitle
	if not header.is_empty():
		lines.append("[color=%s]%s[/color]" % [COLOR_TITLE, _esc(header)])
	if not action.is_empty():
		lines.append("[color=%s]%s[/color]" % [COLOR_ACTION, _esc(action)])
	for line: Variant in details:
		lines.append("[color=%s]%s[/color]" % [COLOR_BODY, _esc(str(line))])

	if lines.is_empty():
		_body.text = ""
		hide()
		return
	_body.text = "\n".join(lines)
	_body.reset_size()
	reset_size()
	custom_minimum_size = Vector2.ZERO
	size = get_minimum_size()


func _esc(text: String) -> String:
	return text.replace("[", "[lb]")


func _update_position() -> void:
	if _world == null or _entity == null:
		return
	var screen: Vector2
	var r3: Variant = _world.get("render_3d")
	if r3 != null and r3.is_active():
		# 3D renderer is on: the entity is drawn at its CAMERA projection, not its flat 2D
		# iso position — so project the same way the hover/picking does, otherwise the
		# tooltip lands at the old 2D spot while the cursor hovers the 3D one. Lift matches
		# the pick's body-centre so the tooltip tracks where the cursor actually is.
		var lift: float = clampf(_entity.icon_height() * (0.25 / 8.0) * 0.5, 0.35, 1.6)
		screen = r3.iso_to_screen(_entity.position, lift) - Vector2(0.0, UiScaleScript.f(14.0))
	else:
		var head := _entity.global_position + Vector2(0.0, -_entity.icon_height() - UiScaleScript.f(14.0))
		screen = _world.get_viewport().get_canvas_transform() * head
	var vp := _world.get_viewport().get_visible_rect().size
	var pos := screen - Vector2(size.x * 0.5, size.y + UiScaleScript.f(5.0))
	pos.x = clampf(pos.x, UiScaleScript.f(4.0), vp.x - size.x - UiScaleScript.f(4.0))
	pos.y = clampf(pos.y, UiScaleScript.f(4.0), vp.y - size.y - UiScaleScript.f(4.0))
	position = pos
