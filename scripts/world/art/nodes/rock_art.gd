extends RefCounted
class_name RockArt

const PixelPalette := preload("res://scripts/world/art/core/pixel_palette.gd")
const PixelDraw := preload("res://scripts/world/art/core/pixel_draw.gd")


static func draw(canvas: CanvasItem, size: float, ore_color: Color, depleted: bool) -> void:
	if depleted:
		PixelDraw.draw_foot_shadow(canvas, size * 0.28, 3.0, 0.22)
		_draw_pixel_boulder(canvas, -size * 0.12, 0.0, size * 0.18, size * 0.1, PixelPalette.pal("stone_b"))
		_draw_pixel_boulder(canvas, size * 0.14, 0.0, size * 0.14, size * 0.08, PixelPalette.shade(PixelPalette.pal("stone_b"), 0.9))
		return
	PixelDraw.draw_foot_shadow(canvas, size * 0.5)
	_draw_pixel_boulder(canvas, PixelPalette.snap(size * 0.3), 0.0, size * 0.26, size * 0.17, PixelPalette.shade(PixelPalette.pal("stone_b"), 0.94))
	_draw_pixel_boulder(canvas, PixelPalette.snap(-size * 0.28), 0.0, size * 0.24, size * 0.15, PixelPalette.pal("stone_b"))
	_draw_pixel_boulder(canvas, 0.0, 0.0, size * 0.46, size * 0.32, PixelPalette.pal("stone_a"))
	var oy := PixelPalette.snap(-size * 0.2)
	var ore := PixelPalette.enrich_entity(ore_color if ore_color.a > 0.01 else PixelPalette.pal("ore"))
	PixelDraw.px_rect(canvas, PixelPalette.snap(-size * 0.05), oy, PixelPalette.PX * 2.0, PixelPalette.PX * 2.0, ore)
	PixelDraw.px_rect(canvas, PixelPalette.snap(size * 0.1), PixelPalette.snap(oy + size * 0.1), PixelPalette.PX * 2.0, PixelPalette.PX * 2.0, PixelPalette.shade(ore, 1.18))
	PixelDraw.px_rect(canvas, PixelPalette.snap(-size * 0.28), PixelPalette.snap(size * 0.02), PixelPalette.PX * 2.0, PixelPalette.PX, PixelPalette.pal("moss"), 0.65)


static func _draw_pixel_boulder(canvas: CanvasItem, cx: float, base_y: float, rx: float, ry: float, color: Color) -> void:
	var hi := PixelPalette.shade(color, 1.2)
	var lo := PixelPalette.shade(color, 0.72)
	var cy := PixelPalette.snap(base_y - ry * 0.55)
	PixelDraw.px_blob(canvas, cx, cy, rx, ry, color)
	PixelDraw.px_blob(canvas, cx - rx * 0.3, cy - ry * 0.28, rx * 0.55, ry * 0.48, hi, 0.78)
	PixelDraw.px_blob(canvas, cx + rx * 0.24, cy + ry * 0.1, rx * 0.5, ry * 0.38, lo, 0.52)
	PixelDraw.px_rect(canvas, PixelPalette.snap(cx - rx * 0.34), PixelPalette.snap(cy - ry * 0.42), PixelPalette.PX * 2.0, PixelPalette.PX * 2.0, hi, 0.88)
	PixelDraw.px_rect(canvas, PixelPalette.snap(cx + rx * 0.12), PixelPalette.snap(cy + ry * 0.08), PixelPalette.PX * 2.0, PixelPalette.PX, lo, 0.65)
	PixelDraw.px_rect(canvas, PixelPalette.snap(cx - rx), base_y - PixelPalette.PX, PixelPalette.snap(rx * 2.0), PixelPalette.PX, PixelPalette.shade(lo, 0.88))
