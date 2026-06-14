extends RefCounted
class_name ObeliskArt

const PixelPalette := preload("res://scripts/world/art/core/pixel_palette.gd")
const PixelDraw := preload("res://scripts/world/art/core/pixel_draw.gd")


static func draw(canvas: CanvasItem, t: float, attuned: bool) -> void:
	PixelDraw.draw_foot_shadow(canvas, 16.0, 4.0, 0.3, 62.0)
	var stone := Color(0.36, 0.34, 0.44)
	var edge := Color(0.48, 0.46, 0.58)
	PixelDraw.px_rect(canvas, -12.0, -8.0, 24.0, 8.0, PixelPalette.shade(stone, 0.8))
	PixelDraw.px_rect(canvas, -8.0, -52.0, 16.0, 44.0, stone)
	PixelDraw.px_rect(canvas, -8.0, -52.0, 4.0, 44.0, edge)
	PixelDraw.px_rect(canvas, -4.0, -60.0, 8.0, 8.0, stone)
	var glow := Color(0.85, 0.4, 0.9) if attuned else Color(0.4, 0.5, 0.6)
	var pulse := 0.5 + sin(t * 3.0) * 0.3
	PixelDraw.px_rect(canvas, -2.0, -46.0 + sin(t * 2.0) * 3.0, 4.0, 4.0, glow, pulse)
	PixelDraw.px_rect(canvas, -2.0, -34.0 + sin(t * 2.0 + 1.7) * 3.0, 4.0, 4.0, glow, pulse * 0.8)


