extends RefCounted
class_name FishArt

const PixelPalette := preload("res://scripts/world/art/core/pixel_palette.gd")
const PixelDraw := preload("res://scripts/world/art/core/pixel_draw.gd")


static func draw(canvas: CanvasItem, size: float, t: float) -> void:
	var rip: float = fmod(t * 0.7, 1.0)
	PixelDraw.draw_foot_shadow(canvas, size * 0.38, 3.0, 0.5)
	PixelDraw.px_diamond(canvas, 0.0, -size * 0.06, size * 0.22 + rip * size * 0.25, size * 0.08 + rip * size * 0.06, PixelPalette.pal("water_foam"), 0.2 * (1.0 - rip))
	PixelDraw.px_rect(canvas, -2.0, -size * 0.2, 4.0, 4.0, PixelPalette.pal("water_foam"), 0.45)
