extends RefCounted
class_name LanternArt

const PixelPalette := preload("res://scripts/world/art/core/pixel_palette.gd")
const PixelDraw := preload("res://scripts/world/art/core/pixel_draw.gd")


static func draw(canvas: CanvasItem) -> void:
	PixelDraw.draw_foot_shadow(canvas, 7.0, 2.0)
	var lantern := PixelPalette.hex(0xF0C848)
	PixelDraw.px_rect(canvas, -1.0, -2.0, 2.0, 10.0, PixelPalette.pal("stone_b"))
	PixelDraw.px_rect(canvas, -6.0, -14.0, 12.0, 12.0, PixelPalette.pal("trunk_b"))
	PixelDraw.px_rect(canvas, -5.0, -13.0, 10.0, 10.0, lantern, 0.9)
	PixelDraw.px_rect(canvas, -3.0, -11.0, 6.0, 6.0, Color8(0xff, 0xf0, 0xa0), 0.55)
	PixelDraw.px_rect(canvas, -1.0, -9.0, 2.0, 2.0, Color.WHITE, 0.7)
	PixelDraw.px_rect(canvas, -8.0, -12.0, 2.0, 2.0, lantern, 0.25)
	PixelDraw.px_rect(canvas, 6.0, -10.0, 2.0, 2.0, lantern, 0.2)


