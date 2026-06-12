extends Node2D
## @deprecated Unused — replaced by `unexplored_backdrop.gd` (see world.gd).
## Soft world-space fog at the edge of explored/generated chunks.

const WG := preload("res://scripts/worldgen/wg.gd")

var chunk_manager: Node2D
var steps := 10
var fade_width := WG.CHUNK_SIZE * 0.75
var max_alpha := 0.50
var _last_count := -1


func _ready() -> void:
	z_index = -45


func _process(_delta: float) -> void:
	if chunk_manager == null:
		return
	var count: int = chunk_manager.call("loaded_chunks").size()
	if count != _last_count:
		_last_count = count
		queue_redraw()


func _draw() -> void:
	if chunk_manager == null:
		return
	var chunks: Array = chunk_manager.call("loaded_chunks")
	if chunks.is_empty():
		return
	var rect := _bounds(chunks)
	var dark := Color(0.133, 0.133, 0.157, 1.0)
	var far := WG.CHUNK_SIZE * 12.0
	# Outside wash. The backdrop still shows through, but no clear-color slab can.
	_draw_rect_alpha(Rect2(rect.position - Vector2(far, far), Vector2(far, rect.size.y + far * 2.0)), dark, 0.30)
	_draw_rect_alpha(Rect2(Vector2(rect.end.x, rect.position.y - far), Vector2(far, rect.size.y + far * 2.0)), dark, 0.30)
	_draw_rect_alpha(Rect2(Vector2(rect.position.x, rect.position.y - far), Vector2(rect.size.x, far)), dark, 0.30)
	_draw_rect_alpha(Rect2(Vector2(rect.position.x, rect.end.y), Vector2(rect.size.x, far)), dark, 0.30)
	# Inward feather, cave-vignette style but aligned to the explored map edge.
	for i: int in range(steps):
		var t := float(i) / float(maxi(steps - 1, 1))
		var a := max_alpha * pow(1.0 - t, 1.9)
		var w := fade_width / float(steps)
		_draw_rect_alpha(Rect2(rect.position.x + t * fade_width, rect.position.y, w, rect.size.y), dark, a)
		_draw_rect_alpha(Rect2(rect.end.x - (t + 1.0) * w, rect.position.y, w, rect.size.y), dark, a)
		_draw_rect_alpha(Rect2(rect.position.x, rect.position.y + t * fade_width, rect.size.x, w), dark, a)
		_draw_rect_alpha(Rect2(rect.position.x, rect.end.y - (t + 1.0) * w, rect.size.x, w), dark, a)


func _draw_rect_alpha(rect: Rect2, color: Color, alpha: float) -> void:
	var c := color
	c.a = alpha
	draw_rect(rect, c)


func _bounds(chunks: Array) -> Rect2:
	var min_x := INF
	var min_y := INF
	var max_x := -INF
	var max_y := -INF
	for chunk: RefCounted in chunks:
		var o: Vector2 = chunk.origin()
		min_x = minf(min_x, o.x)
		min_y = minf(min_y, o.y)
		max_x = maxf(max_x, o.x + WG.CHUNK_SIZE)
		max_y = maxf(max_y, o.y + WG.CHUNK_SIZE)
	return Rect2(Vector2(min_x, min_y), Vector2(max_x - min_x, max_y - min_y))
