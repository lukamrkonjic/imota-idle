extends Node2D
## A ranged arrow: flies from the player's bow to the combat target over a short
## arc, then triggers the damage splat on arrival (so the hit reads as landing in
## sync with the attack tick that loosed it). Pure draw, no assets.

const FLIGHT := 0.20

var start := Vector2.ZERO
var end := Vector2.ZERO
var amount: int = 0
var miss: bool = false

var _t := 0.0
var _done := false


func _ready() -> void:
	z_index = 690
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	position = start
	set_process(true)
	queue_redraw()


func _process(delta: float) -> void:
	_t += delta
	var f := clampf(_t / FLIGHT, 0.0, 1.0)
	var p := start.lerp(end, f)
	p.y -= sin(f * PI) * 10.0   # gentle lob
	position = p
	queue_redraw()
	if f >= 1.0 and not _done:
		_done = true
		EventBus.combat_hit_splat.emit(amount, miss, false)  # splat on the target now
		queue_free()


func _draw() -> void:
	var d := end - start
	if d.length() < 0.001:
		return
	d = d.normalized()
	var perp := Vector2(-d.y, d.x)
	var tail := -d * 9.0
	var tip := d * 5.0
	draw_line(tail, tip, Color(0.42, 0.30, 0.17), 2.0)                    # shaft
	draw_colored_polygon(PackedVector2Array([
		tip + d * 3.0, tip + perp * 2.6, tip - perp * 2.6]),
		Color(0.74, 0.76, 0.79))                                          # head
	draw_line(tail, tail + d * 3.0 + perp * 3.0, Color(0.87, 0.87, 0.9), 1.5)  # fletch
	draw_line(tail, tail + d * 3.0 - perp * 3.0, Color(0.87, 0.87, 0.9), 1.5)
