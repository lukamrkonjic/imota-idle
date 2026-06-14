extends RefCounted
class_name LadderArt

const PixelPalette := preload("res://scripts/world/art/core/pixel_palette.gd")
const PixelDraw := preload("res://scripts/world/art/core/pixel_draw.gd")


static func draw(canvas: CanvasItem, up: bool) -> void:
	var wood := PixelPalette.hex(0x8A6848)
	var dark := PixelPalette.pal("trunk_b")
	if up:
		PixelDraw.draw_foot_shadow(canvas, 12.0, 3.0, 0.3, 30.0)
		PixelDraw.px_rect(canvas, -8.0, -34.0, 3.0, 34.0, wood)
		PixelDraw.px_rect(canvas, 5.0, -34.0, 3.0, 34.0, wood)
		var y := -30.0
		while y < -2.0:
			PixelDraw.px_rect(canvas, -8.0, y, 16.0, 2.0, dark)
			y += 8.0
	else:
		PixelDraw.px_blob(canvas, 0.0, 0.0, 16.0, 9.0, Color(0.06, 0.05, 0.08))
		PixelDraw.px_rect(canvas, -7.0, -10.0, 3.0, 12.0, wood)
		PixelDraw.px_rect(canvas, 4.0, -10.0, 3.0, 12.0, wood)
		PixelDraw.px_rect(canvas, -7.0, -8.0, 14.0, 2.0, dark)
		PixelDraw.px_rect(canvas, -7.0, -2.0, 14.0, 2.0, dark)


