extends Control
## A drawn icon action button beside the minimap (Bank / Slayer / World map).
## Extracted from osrs_hud.gd. Set `kind`, `label`, `on_press`.

const UiScale := preload("res://scripts/ui/ui_scale.gd")

var kind := "bank"
var label := ""
var on_press: Callable


func _ready() -> void:
	custom_minimum_size = UiScale.v2(Vector2(50, 40))
	size = custom_minimum_size
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if on_press.is_valid():
			on_press.call()


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.18, 0.16, 0.14))
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.55, 0.5, 0.35), false, 2.0)
	var c := Vector2(size.x * 0.5, size.y * 0.38)
	var s := minf(size.x, size.y) * 0.26
	var ink := Color(0.93, 0.88, 0.72)
	match kind:
		"bank":  # building: roof + body
			draw_colored_polygon(PackedVector2Array([
				c + Vector2(-s * 1.2, -s * 0.2), c + Vector2(s * 1.2, -s * 0.2), c + Vector2(0, -s * 1.1)]), ink)
			draw_rect(Rect2(c + Vector2(-s, -s * 0.2), Vector2(s * 2.0, s * 1.2)), ink, false, 1.5)
		"slayer":  # skull
			draw_circle(c, s, ink)
			draw_circle(c + Vector2(-s * 0.42, -s * 0.05), s * 0.24, Color.BLACK)
			draw_circle(c + Vector2(s * 0.42, -s * 0.05), s * 0.24, Color.BLACK)
			draw_rect(Rect2(c + Vector2(-s * 0.4, s * 0.5), Vector2(s * 0.8, s * 0.5)), ink)
		"map":  # globe
			draw_arc(c, s, 0.0, TAU, 22, ink, 1.5)
			draw_line(c + Vector2(0, -s), c + Vector2(0, s), ink, 1.0)
			draw_line(c + Vector2(-s, 0), c + Vector2(s, 0), ink, 1.0)
	var font := ThemeDB.fallback_font
	var fs := UiScale.i(10)
	var tw := font.get_string_size(label, HORIZONTAL_ALIGNMENT_CENTER, -1, fs).x
	draw_string(font, Vector2(size.x * 0.5 - tw / 2.0, size.y - UiScale.f(3.0)), label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(0.85, 0.82, 0.66))
