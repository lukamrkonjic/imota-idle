extends Control
## Screen-space white highlight around interactable entities + enemies. While the player
## holds Alt (world_visual_controller flags each visible interactable's highlight_outline)
## or hovers one, this draws a white bracket box around it so what's interactable is
## temporarily visible. Lives on the 3D fx overlay and projects each entity through the 3D
## camera (iso_to_screen), so it tracks the orbiting/zooming view.

# iso-pixel sprite height -> world height (matches WorldInputController.ISO_PX_TO_WORLD).
const ISO_PX_TO_WORLD := 0.25 / 8.0

var world: Node2D
var r3: Node   # world_render_3d


func _process(_dt: float) -> void:
	queue_redraw()


func _draw() -> void:
	if world == null or r3 == null or not r3.is_active():
		return
	for e: Node2D in world.entities:
		if not is_instance_valid(e):
			continue
		if not (e.highlight_outline or e.hovered):
			continue
		_draw_box(e, e.hovered)


func _draw_box(e: Node2D, strong: bool) -> void:
	var ppu: float = r3.world_px_per_unit()
	var h_world: float = clampf(e.icon_height() * ISO_PX_TO_WORLD, 0.6, 3.2)
	var base: Vector2 = r3.iso_to_screen(e.position, 0.0)
	var top: Vector2 = r3.iso_to_screen(e.position, h_world)
	var hw: float = maxf(10.0, e.click_radius * ISO_PX_TO_WORLD * ppu * 0.7)
	var x0 := base.x - hw
	var x1 := base.x + hw
	var y0 := top.y - 2.0
	var y1 := base.y + 2.0
	var col := Color(1.0, 1.0, 1.0, 0.95 if strong else 0.7)
	var w := 2.0 if strong else 1.5
	# Corner brackets read as a clean selection highlight without boxing the whole sprite in.
	var arm := clampf((x1 - x0) * 0.32, 5.0, 14.0)
	_bracket(Vector2(x0, y0), Vector2(1, 0), Vector2(0, 1), arm, col, w)    # top-left
	_bracket(Vector2(x1, y0), Vector2(-1, 0), Vector2(0, 1), arm, col, w)   # top-right
	_bracket(Vector2(x0, y1), Vector2(1, 0), Vector2(0, -1), arm, col, w)   # bottom-left
	_bracket(Vector2(x1, y1), Vector2(-1, 0), Vector2(0, -1), arm, col, w)  # bottom-right


func _bracket(corner: Vector2, ax: Vector2, ay: Vector2, arm: float, col: Color, w: float) -> void:
	draw_line(corner, corner + ax * arm, col, w)
	draw_line(corner, corner + ay * arm, col, w)
