extends RefCounted
class_name MeteorArt

const PixelPalette := preload("res://scripts/world/art/core/pixel_palette.gd")
const PixelDraw := preload("res://scripts/world/art/core/pixel_draw.gd")


static func draw(canvas: CanvasItem, t: float) -> void:
	var rim := PixelPalette.pal("dirt_b")
	PixelDraw.px_blob(canvas, 0.0, 0.0, 34.0, 16.0, PixelPalette.shade(rim, 0.7))
	PixelDraw.px_blob(canvas, 0.0, -2.0, 26.0, 11.0, Color(0.12, 0.1, 0.12))
	PixelDraw.px_blob(canvas, 0.0, -4.0, 14.0, 8.0, Color(0.22, 0.18, 0.24))
	var pulse := 0.5 + sin(t * 1.6) * 0.3
	PixelDraw.px_rect(canvas, -6.0, -8.0, 8.0, 5.0, Color8(0x66, 0xe0, 0xc8), pulse)
	PixelDraw.px_rect(canvas, 2.0, -5.0, 4.0, 3.0, Color8(0xa0, 0xff, 0xe0), pulse * 0.8)
	PixelDraw.px_rect(canvas, -30.0, -4.0, 6.0, 4.0, rim, 0.8)
	PixelDraw.px_rect(canvas, 24.0, -2.0, 7.0, 4.0, rim, 0.8)


