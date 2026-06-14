extends RefCounted
class_name WaterSurfaceArt
## Decorative water-surface visuals — fishing schools (spots only) and lilies.

const PixelPalette := preload("res://scripts/world/art/core/pixel_palette.gd")
const PixelDraw := preload("res://scripts/world/art/core/pixel_draw.gd")

static var _anim_t := 0.0


static func advance_time(delta: float) -> void:
	_anim_t += delta


static func anim_time() -> float:
	return _anim_t


static func draw(canvas: CanvasItem, kind: String, variant: int, t: float) -> void:
	match kind:
		"lily":
			_draw_lily(canvas, variant)
		"fish_school":
			_draw_fish_school(canvas, variant, t)
		_:
			pass


static func _fish_color() -> Color:
	var c := PixelPalette.pal("shadow")
	c.a = 0.32
	return c


## Small OSRS-style school orbiting a fixed point.
static func _draw_fish_school(canvas: CanvasItem, variant: int, t: float) -> void:
	var phase := float(variant % 1000) * 0.13
	var orbit := 5.5 + float(variant % 7) * 0.35
	var col := _fish_color()
	for i: int in 4:
		var ang := t * 1.45 + phase + TAU * float(i) / 4.0
		var p := Vector2(cos(ang) * orbit, sin(ang) * orbit * 0.42)
		var tail := p + Vector2(cos(ang + PI) * 2.2, sin(ang + PI) * 1.0)
		PixelDraw.px_blob(canvas, p.x, p.y, 2.4, 1.4, col, 0.9)
		PixelDraw.px_blob(canvas, tail.x, tail.y, 1.2, 0.8, col, 0.45)


static func _draw_lily(canvas: CanvasItem, variant: int) -> void:
	var px := float(PixelPalette.PX)
	var pad := PixelPalette.shade(PixelPalette.pal("water_a"), 0.85)
	pad.a = 0.72
	var off := Vector2(
		(float(variant % 5) - 2.0) * px * 0.4,
		(float((variant / 5) % 5) - 2.0) * px * 0.25)
	PixelDraw.px_blob(canvas, off.x - px, off.y, px * 1.6, px * 0.9, pad, pad.a)
	PixelDraw.px_blob(canvas, off.x + px * 0.8, off.y + px * 0.2, px * 1.4, px * 0.8, PixelPalette.shade(pad, 0.92), pad.a * 0.85)
	var flower := PixelPalette.pal("dirt_a") if variant % 3 == 0 else PixelPalette.pal("gold")
	flower.a = 0.55
	PixelDraw.px_rect(canvas, off.x, off.y - px * 0.5, px, px, flower, flower.a)
