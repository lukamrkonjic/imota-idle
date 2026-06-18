extends RefCounted
class_name ClickMarkerArt
## Thin OSRS click X — yellow walk, red interact.

const ClickMarkerAnim := preload("res://scripts/ui/click_marker_anim.gd")
const UNIT := 4.6   # 2x the old size — a bolder, easier-to-see click X
const BLACK := Color(0.02, 0.02, 0.02)
const WALK := Color(1.0, 0.78, 0.0)
const INTERACT := Color(0.95, 0.05, 0.04)


static func fill_color(interactable: bool) -> Color:
	return INTERACT if interactable else WALK


static func art_size() -> Vector2:
	var span := ClickMarkerAnim.MAX_ARM * 2 + 1
	return Vector2(UNIT * float(span), UNIT * float(span))


static func draw(canvas: CanvasItem, center: Vector2, interactable: bool, arm: int, gap: int = -1) -> void:
	var fill := fill_color(interactable)
	var cells := _cells_for_arm(arm, gap)
	if cells.is_empty():
		return
	var outline: Dictionary = {}
	for c: Vector2i in cells:
		for d: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var n: Vector2i = c + d
			if not cells.has(n):
				outline[n] = true
	for c: Vector2i in outline:
		_pixel(canvas, center, c, BLACK)
	for c: Vector2i in cells:
		_pixel(canvas, center, c, fill)


static func _cells_for_arm(arm: int, gap: int) -> Dictionary:
	var cells: Dictionary = {}
	if arm < 0:
		return cells
	for i: int in range(-arm, arm + 1):
		if gap >= 0 and absi(i) <= gap:
			continue
		cells[Vector2i(i, i)] = true
		cells[Vector2i(i, -i)] = true
	return cells


static func _pixel(canvas: CanvasItem, center: Vector2, cell: Vector2i, color: Color) -> void:
	var p := center + Vector2(cell) * UNIT - Vector2(UNIT * 0.5, UNIT * 0.5)
	canvas.draw_rect(Rect2(p, Vector2(UNIT, UNIT)), color)
