extends PanelContainer
class_name WorldHoverTooltip
## One styled hover tooltip, shared by every hover surface in the game so they all
## look identical: world entities (via show_for / the HUD) AND inventory items,
## equipment slots, prayers and spells (via attach()). It floats just above the
## mouse cursor with a margin — the cursor is always over whatever is hovered, so
## "over the hovered thing" and "follows the mouse" are the same placement, and it
## needs no per-surface projection math.

const UiScaleScript := preload("res://scripts/ui/ui_scale.gd")

const STONE := Color(0.24, 0.22, 0.20)
const STONE_DARK := Color(0.16, 0.15, 0.14)
const COLOR_TITLE := "#d9b84d"
const COLOR_ACTION := "#ffff66"
const COLOR_BODY := "#d1d1c2"

var _body: RichTextLabel
var _margin: float


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
	# Track the cursor every frame while shown so the tooltip never lags behind a
	# moving mouse or a panel that scrolled under it.
	if visible:
		_update_position()


## World-entity hover (called by the HUD). The entity args are kept for API
## compatibility; positioning is cursor-relative like every other surface.
func show_for(_world: Node2D, _entity: Node2D, content: Dictionary) -> void:
	show_text(content)


## Show the tooltip for any hover source (UI items, prayers, spells, …).
func show_text(content: Variant) -> void:
	_apply_content(content)
	if not visible:
		return
	_update_position()


## Wire a Control so hovering it shows this tooltip and leaving it hides it.
## `content` is either a Dictionary (see _apply_content) or a Callable returning
## one, evaluated on each hover so dynamic state stays fresh.
func attach(control: Control, content: Variant) -> void:
	control.mouse_entered.connect(func() -> void:
		if not GameSettings.show_hover_tooltip:
			return
		show_text(content.call() if content is Callable else content))
	control.mouse_exited.connect(hide_tooltip)


func hide_tooltip() -> void:
	visible = false


## Back-compat shim: the HUD calls this after show_for; positioning is now driven
## by _process, so it only needs to keep the tooltip current.
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
	var vp := get_viewport().get_visible_rect().size
	var m := get_viewport().get_mouse_position()
	var gap := UiScaleScript.f(18.0)
	var edge := UiScaleScript.f(4.0)
	# Centered above the cursor, a margin above it; flip below if it'd clip the top.
	var pos := Vector2(m.x - size.x * 0.5, m.y - size.y - gap)
	if pos.y < edge:
		pos.y = m.y + gap
	pos.x = clampf(pos.x, edge, maxf(edge, vp.x - size.x - edge))
	pos.y = clampf(pos.y, edge, maxf(edge, vp.y - size.y - edge))
	position = pos
