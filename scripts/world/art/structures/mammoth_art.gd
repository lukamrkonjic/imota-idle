extends RefCounted
class_name MammothArt

const PixelPalette := preload("res://scripts/world/art/core/pixel_palette.gd")
const PixelDraw := preload("res://scripts/world/art/core/pixel_draw.gd")


static func draw(canvas: CanvasItem) -> void:
	PixelDraw.draw_tight_character_shadow(canvas, 24.0, 5.0)
	var ice := Color8(0xa8, 0xd0, 0xe8)
	var ice_hi := Color8(0xd0, 0xec, 0xf8)
	PixelDraw.px_rect(canvas, -26.0, -40.0, 52.0, 40.0, ice, 0.92)
	PixelDraw.px_rect(canvas, -26.0, -40.0, 6.0, 40.0, ice_hi, 0.9)
	PixelDraw.px_rect(canvas, -26.0, -40.0, 52.0, 4.0, ice_hi, 0.9)
	PixelDraw.px_blob(canvas, 2.0, -22.0, 16.0, 11.0, Color(0.28, 0.2, 0.16), 0.85)
	PixelDraw.px_blob(canvas, 14.0, -30.0, 8.0, 6.0, Color(0.28, 0.2, 0.16), 0.85)
	PixelDraw.px_rect(canvas, 16.0, -22.0, 8.0, 3.0, Color8(0xf0, 0xea, 0xd8), 0.9)
	PixelDraw.px_rect(canvas, 20.0, -19.0, 4.0, 3.0, Color8(0xf0, 0xea, 0xd8), 0.9)
	PixelDraw.px_rect(canvas, -12.0, -10.0, 3.0, 10.0, Color(0.28, 0.2, 0.16), 0.7)
	PixelDraw.px_rect(canvas, 6.0, -10.0, 3.0, 10.0, Color(0.28, 0.2, 0.16), 0.7)
