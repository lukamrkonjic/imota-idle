extends RefCounted
class_name StallArt

const PixelPalette := preload("res://scripts/world/art/core/pixel_palette.gd")
const PixelDraw := preload("res://scripts/world/art/core/pixel_draw.gd")


static func draw(canvas: CanvasItem) -> void:
	PixelDraw.draw_foot_shadow(canvas, 20.0, 4.0)
	var wood := PixelPalette.hex(0x8A6848)
	var red := Color8(0xc0, 0x4a, 0x3a)
	var cream := Color8(0xe8, 0xdc, 0xc0)
	PixelDraw.px_rect(canvas, -16.0, -14.0, 3.0, 14.0, wood)
	PixelDraw.px_rect(canvas, 13.0, -14.0, 3.0, 14.0, wood)
	PixelDraw.px_rect(canvas, -14.0, -12.0, 28.0, 6.0, PixelPalette.shade(wood, 1.1))
	var x := -20.0
	var i := 0
	while x < 20.0:
		PixelDraw.px_rect(canvas, x, -26.0, 5.0, 10.0, red if i % 2 == 0 else cream)
		x += 5.0
		i += 1
	PixelDraw.px_rect(canvas, -20.0, -28.0, 40.0, 3.0, PixelPalette.shade(red, 0.8))
	PixelDraw.px_rect(canvas, -10.0, -10.0, 6.0, 4.0, Color8(0xf0, 0xd0, 0x50))
	PixelDraw.px_rect(canvas, 2.0, -10.0, 5.0, 4.0, Color8(0xe0, 0x80, 0xa0))


