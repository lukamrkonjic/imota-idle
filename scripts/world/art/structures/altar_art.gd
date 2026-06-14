extends RefCounted
class_name AltarArt

const PixelPalette := preload("res://scripts/world/art/core/pixel_palette.gd")
const PixelDraw := preload("res://scripts/world/art/core/pixel_draw.gd")


static func draw(canvas: CanvasItem, t: float, glow_color: Color) -> void:
	PixelDraw.draw_foot_shadow(canvas, 22.0, 4.0, 0.3, 26.0)
	var stone := PixelPalette.pal("stone_b")
	var stone_hi := PixelPalette.pal("stone_a")
	PixelDraw.px_rect(canvas, -18.0, -10.0, 36.0, 10.0, stone)
	PixelDraw.px_rect(canvas, -14.0, -22.0, 28.0, 12.0, stone_hi)
	PixelDraw.px_rect(canvas, -14.0, -22.0, 28.0, 3.0, PixelPalette.shade(stone_hi, 1.18))
	var pulse := 0.55 + sin(t * 2.2) * 0.25
	PixelDraw.px_rect(canvas, -8.0, -28.0, 16.0, 6.0, glow_color, pulse)
	PixelDraw.px_rect(canvas, -3.0, -32.0, 6.0, 4.0, glow_color.lightened(0.3), pulse * 0.8)


