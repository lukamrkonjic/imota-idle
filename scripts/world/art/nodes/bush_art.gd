extends RefCounted
class_name BushArt

const PixelPalette := preload("res://scripts/world/art/core/pixel_palette.gd")
const PixelDraw := preload("res://scripts/world/art/core/pixel_draw.gd")


static func draw(canvas: CanvasItem, size: float, berry_color: Color, depleted: bool) -> void:
	if depleted:
		return
	PixelDraw.draw_foot_shadow(canvas, size * 0.38, 3.0)
	PixelDraw.draw_foliage_clump(canvas, 0.0, -size * 0.22, size * 0.42, size * 0.28, PixelPalette.pal("foliage_b"))
	PixelDraw.draw_foliage_clump(canvas, -size * 0.18, -size * 0.1, size * 0.28, size * 0.2, PixelPalette.pal("moss"))
	PixelDraw.draw_foliage_clump(canvas, size * 0.16, -size * 0.14, size * 0.26, size * 0.18, PixelPalette.pal("foliage_a"))
	PixelDraw.px_rect(canvas, -PixelPalette.PX, -size * 0.28, PixelPalette.PX, PixelPalette.PX, berry_color)
	PixelDraw.px_rect(canvas, PixelPalette.PX * 2.0, -size * 0.18, PixelPalette.PX, PixelPalette.PX, berry_color)
	PixelDraw.px_rect(canvas, 0.0, -size * 0.34, PixelPalette.PX, PixelPalette.PX, PixelPalette.shade(berry_color, 1.15))
