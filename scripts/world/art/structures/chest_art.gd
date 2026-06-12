extends RefCounted
class_name ChestArt

const PixelPalette := preload("res://scripts/world/art/core/pixel_palette.gd")
const PixelDraw := preload("res://scripts/world/art/core/pixel_draw.gd")


static func draw(canvas: CanvasItem, size: float, color: Color, depleted: bool) -> void:
	PixelDraw.draw_foot_shadow(canvas, size * 0.52, 4.0)
	var w := PixelPalette.snap(size * 0.72)
	var h := PixelPalette.snap(size * 0.48)
	var c := PixelPalette.pal("stone_b") if depleted else color
	var px := float(PixelPalette.PX)
	PixelDraw.px_rect(canvas, -w, -h, w * 2.0, h, c)
	PixelDraw.px_rect(canvas, w - px * 2.0, -h + px, px * 2.0, h - px, PixelPalette.shade(c, 0.72))
	PixelDraw.px_rect(canvas, -w, -h, px * 2.0, h, PixelPalette.shade(c, 1.1))
	PixelDraw.px_rect(canvas, -w, -h, w * 2.0, px * 3.0, PixelPalette.shade(c, 1.08))
	PixelDraw.px_rect(canvas, -w, -h * 0.55, w * 2.0, px * 2.0, PixelPalette.pal("trunk_b"))
	PixelDraw.px_rect(canvas, -w, -h * 0.15, w * 2.0, px * 2.0, PixelPalette.pal("trunk_b"))
	if not depleted:
		PixelDraw.px_rect(canvas, -px * 3.0, -h * 0.42, px * 6.0, px * 4.0, PixelPalette.pal("gold"))
		PixelDraw.px_rect(canvas, -px, -h * 0.38, px * 2.0, px * 2.0, PixelPalette.pal("trunk_b"))


