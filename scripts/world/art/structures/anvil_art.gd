extends RefCounted
class_name AnvilArt

const PixelPalette := preload("res://scripts/world/art/core/pixel_palette.gd")
const PixelDraw := preload("res://scripts/world/art/core/pixel_draw.gd")


static func draw(canvas: CanvasItem, t: float) -> void:
	PixelDraw.draw_foot_shadow(canvas, 20.0, 3.0)
	var iron := Color(0.30, 0.30, 0.34)
	var iron_hi := Color(0.42, 0.42, 0.47)
	PixelDraw.px_rect(canvas, -10.0, -10.0, 20.0, 10.0, PixelPalette.pal("stone_b"))
	PixelDraw.px_rect(canvas, -16.0, -20.0, 32.0, 10.0, iron)
	PixelDraw.px_rect(canvas, -16.0, -20.0, 32.0, 3.0, iron_hi)
	PixelDraw.px_rect(canvas, 16.0, -18.0, 8.0, 5.0, iron)
	var glow := 0.5 + sin(t * 5.0) * 0.25
	PixelDraw.px_rect(canvas, -4.0, -24.0, 6.0, 4.0, Color8(0xff, 0x66, 0x22), glow)


