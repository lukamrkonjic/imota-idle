extends Control
## Side-panel tab icon (combat / skills / inventory / equipment / prayer / magic),
## drawn procedurally. Extracted from osrs_hud.gd. Set `kind` + `on_press`.

const UiScale := preload("res://scripts/ui/ui_scale.gd")

var kind := ""
var active := false
var on_press: Callable


func _ready() -> void:
	custom_minimum_size = UiScale.v2(Vector2(40, 32))
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND


func set_active(a: bool) -> void:
	active = a
	queue_redraw()


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if on_press.is_valid():
			on_press.call()


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.30, 0.27, 0.22) if active else Color(0.15, 0.14, 0.13))
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.75, 0.65, 0.42) if active else Color(0.38, 0.35, 0.28), false, 2.0)
	var c := size * 0.5
	var s := minf(size.x, size.y) * 0.28
	var ink := Color(0.97, 0.9, 0.62) if active else Color(0.72, 0.7, 0.58)
	match kind:
		"combat":  # crossed swords
			draw_line(c + Vector2(-s, s), c + Vector2(s, -s), ink, 2.0)
			draw_line(c + Vector2(-s, -s), c + Vector2(s, s), ink, 2.0)
		"skills":  # rising bars
			for i: int in 3:
				var bh := s * (0.6 + 0.6 * float(i))
				draw_rect(Rect2(c + Vector2(-s + float(i) * s * 0.8, s - bh), Vector2(s * 0.55, bh)), ink)
		"inventory":  # backpack 2x2 grid
			for ox: float in [-s * 0.62, s * 0.08]:
				for oy: float in [-s * 0.62, s * 0.08]:
					draw_rect(Rect2(c + Vector2(ox, oy), Vector2(s * 0.54, s * 0.54)), ink)
		"equipment":  # shield
			draw_colored_polygon(PackedVector2Array([
				c + Vector2(-s, -s), c + Vector2(s, -s), c + Vector2(s, s * 0.3),
				c + Vector2(0, s * 1.1), c + Vector2(-s, s * 0.3)]), ink)
		"prayer":  # teardrop diamond
			draw_colored_polygon(PackedVector2Array([
				c + Vector2(0, -s * 1.1), c + Vector2(s * 0.8, 0),
				c + Vector2(0, s * 1.1), c + Vector2(-s * 0.8, 0)]), ink)
		"magic":  # six-point star
			for a: float in [0.0, PI / 3.0, 2.0 * PI / 3.0]:
				draw_line(c - Vector2(cos(a), sin(a)) * s, c + Vector2(cos(a), sin(a)) * s, ink, 2.0)
