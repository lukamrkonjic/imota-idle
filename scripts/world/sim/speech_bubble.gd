extends Node2D
## A lightweight speech bubble that floats above a sim-player's head (the Erenshor social feel).
## Same recipe as the hit splat: it lives on the 3D screen-space overlay (render_3d.fx_layer) and
## re-projects the anchor entity's head through the live 3D camera each frame, so it rides along as
## the sim walks. Word-wrapped, lifetime scaled to text length, pops in / holds / fades / frees.

const MAX_WIDTH := 168.0
const PAD := Vector2(8.0, 5.0)
const TAIL := 7.0
const FADE := 0.35
const POP := 0.12

var text := ""
var anchor: Node2D = null         # the sim entity this bubble tracks
var projector: Node = null        # WorldRender3D — projects anchor -> screen px
var lift := 2.4                   # world-Y above the sim's feet (its head height)

var _t := 0.0
var _life := 2.5
var _label: Label
var _bg := Color(0.1, 0.11, 0.14, 0.86)
var _border := Color(0.85, 0.86, 0.9, 0.9)


func _ready() -> void:
	z_index = 720   # above hitsplats
	_life = clampf(1.6 + float(text.length()) * 0.055, 2.0, 6.0)
	_label = Label.new()
	_label.text = text
	_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_label.custom_minimum_size = Vector2(0, 0)
	_label.add_theme_font_size_override("font_size", 13)
	_label.add_theme_color_override("font_color", Color(0.96, 0.97, 1.0))
	_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.85))
	_label.add_theme_constant_override("shadow_offset_x", 1)
	_label.add_theme_constant_override("shadow_offset_y", 1)
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	# Cap width so long lines wrap; short lines shrink to fit.
	var measured: float = ThemeDB.fallback_font.get_string_size(
		text, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x
	_label.size.x = minf(measured + 2.0, MAX_WIDTH)
	_label.position = Vector2.ZERO
	add_child(_label)
	set_process(true)
	queue_redraw()


func _process(delta: float) -> void:
	_t += delta
	if _t >= _life or not is_instance_valid(anchor):
		queue_free()
		return
	if projector != null and projector.is_active():
		position = projector.iso_to_screen(anchor.position, lift)
	else:
		position = anchor.position - Vector2(0, 64)
	# Re-centre the label above the anchor point each frame (its size settles after the first
	# layout pass), then draw the bubble behind it.
	var w: float = maxf(_label.size.x, 16.0)
	var h: float = maxf(_label.size.y, 16.0)
	_label.position = Vector2(-w * 0.5, -(h + TAIL + PAD.y * 2.0))
	queue_redraw()


func _draw() -> void:
	if _label == null:
		return
	var a := 1.0
	if _t < POP:
		a = _t / POP
	elif _t > _life - FADE:
		a = clampf((_life - _t) / FADE, 0.0, 1.0)
	var w: float = maxf(_label.size.x, 16.0)
	var h: float = maxf(_label.size.y, 16.0)
	var rect := Rect2(
		Vector2(-w * 0.5 - PAD.x, -(h + TAIL + PAD.y * 2.0) - PAD.y),
		Vector2(w + PAD.x * 2.0, h + PAD.y * 2.0))
	var bg := Color(_bg.r, _bg.g, _bg.b, _bg.a * a)
	var br := Color(_border.r, _border.g, _border.b, _border.a * a)
	draw_rect(rect, bg, true)
	draw_rect(rect, br, false, 1.0)
	# Little downward tail pointing at the head.
	var tip := Vector2(0, -TAIL)
	var pts := PackedVector2Array([Vector2(-5, rect.end.y), Vector2(5, rect.end.y), tip])
	draw_colored_polygon(pts, bg)
	_label.modulate.a = a
