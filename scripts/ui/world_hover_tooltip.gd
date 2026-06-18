extends PanelContainer
class_name WorldHoverTooltip
## One styled hover tooltip, shared by every hover surface so they all look the same:
## world entities (via show_for / the HUD) AND inventory items, equipment slots,
## prayers and spells (via attach()).
##
## It does NOT follow the mouse. It pins ABOVE the hovered thing with a margin and
## stays there: above a world model's top (tracking the model if it walks), or above
## a UI control's rect. Ownership (_entity vs _ui_owner) arbitrates so the per-frame
## world-hover poll can't yank a UI tooltip away, or vice-versa.

const UiScaleScript := preload("res://scripts/ui/ui_scale.gd")

# Old 2D-pixels -> world-Y factor (one elevation step = 8 iso px = 0.25 world units);
# mirrors world_input_controller so we can lift the projection to a model's top.
const PX_TO_WORLD_Y := 0.25 / 8.0

const STONE := Color(0.24, 0.22, 0.20)
const STONE_DARK := Color(0.16, 0.15, 0.14)
const COLOR_TITLE := "#d9b84d"
const COLOR_ACTION := "#ffff66"
const COLOR_BODY := "#d1d1c2"

var _body: RichTextLabel
var _margin: float
var _world: Node2D
var _entity: Node2D       # world-entity anchor; non-null => world-owned
var _ui_owner: Control    # UI-control anchor; non-null => UI-owned


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


func _process(_delta: float) -> void:
	# Re-pin every frame so the tooltip tracks a walking model / a camera ease / a
	# scrolled panel. The anchor is the model or control, never the cursor.
	if visible:
		_update_position()


## World-entity hover (called by the HUD).
func show_for(world: Node2D, entity: Node2D, content: Dictionary) -> void:
	_world = world
	_entity = entity
	_ui_owner = null
	_apply_content(content)
	if visible:
		_update_position()


## Wire a Control so hovering it shows this tooltip, pinned above the control.
## `content` is a Dictionary or a Callable returning one (evaluated per hover).
func attach(control: Control, content: Variant) -> void:
	control.mouse_entered.connect(func() -> void:
		if not GameSettings.show_hover_tooltip:
			return
		_world = null
		_entity = null
		_ui_owner = control
		_apply_content(content.call() if content is Callable else content)
		if visible:
			_update_position())
	control.mouse_exited.connect(func() -> void:
		if _ui_owner == control:
			hide_tooltip())


## True while a UI control (set via attach) is hovered. The world-hover poll checks
## this and stands down, so the world picker — which still finds geometry behind the
## HUD — can't override an inventory/equipment/spell tooltip.
func is_ui_owned() -> bool:
	if _ui_owner != null and not is_instance_valid(_ui_owner):
		_ui_owner = null   # owner was freed (e.g. inventory rebuilt) without an exit event
	return _ui_owner != null


## Hide only if a world entity (not a UI control) owns the tooltip. The world-hover
## poll calls this when the cursor leaves world geometry, so it must never close a
## tooltip that an inventory/equipment/spell hover is currently showing.
func hide_for_world() -> void:
	if _ui_owner == null:
		hide_tooltip()


func hide_tooltip() -> void:
	visible = false
	_entity = null
	_world = null
	_ui_owner = null


## Back-compat shim (the HUD still calls this); positioning is driven by _process.
func follow_entity() -> void:
	if visible:
		_update_position()


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
	visible = true


func _esc(text: String) -> String:
	return text.replace("[", "[lb]")


func _update_position() -> void:
	# Screen point at the TOP of whatever is hovered; the tooltip sits above it.
	var top: Vector2
	if _ui_owner != null and is_instance_valid(_ui_owner):
		var rect := _ui_owner.get_global_rect()
		top = Vector2(rect.position.x + rect.size.x * 0.5, rect.position.y)
	elif _entity != null and is_instance_valid(_entity):
		var r3: Variant = _world.get("render_3d") if _world != null else null
		if r3 != null and r3.is_active():
			# Lift the projection to roughly the model's crown so the tooltip clears it.
			var lift: float = clampf(_entity.icon_height() * PX_TO_WORLD_Y, 0.6, 4.0)
			top = r3.iso_to_screen(_entity.position, lift)
		else:
			var head := _entity.global_position + Vector2(0.0, -_entity.icon_height())
			top = _world.get_viewport().get_canvas_transform() * head
	else:
		return

	var vp := get_viewport().get_visible_rect().size
	var gap := UiScaleScript.f(10.0)
	var edge := UiScaleScript.f(4.0)
	# Centred above the anchor's top with a margin; flip below if it would clip the top.
	var pos := Vector2(top.x - size.x * 0.5, top.y - size.y - gap)
	if pos.y < edge:
		pos.y = top.y + gap
	pos.x = clampf(pos.x, edge, maxf(edge, vp.x - size.x - edge))
	pos.y = clampf(pos.y, edge, maxf(edge, vp.y - size.y - edge))
	position = pos
