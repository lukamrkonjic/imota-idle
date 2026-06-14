extends RefCounted
class_name PricklyPearDecorArt

const PixelPalette := preload("res://scripts/world/art/core/pixel_palette.gd")
const PixelDraw := preload("res://scripts/world/art/core/pixel_draw.gd")
const H := preload("res://scripts/world/art/decor/nature/nature_decor_helpers.gd")


static func draw(canvas: CanvasItem, variant: int, _tint: Color) -> void:
	H.cactus(canvas, variant + 1, 18.0, _tint)
	H.blob(canvas, -7.0, -9.0, 5.0, 6.0, Color8(75, 158, 86), 0.90, _tint)
	H.blob(canvas, 8.0, -12.0, 5.0, 6.0, Color8(75, 158, 86), 0.90, _tint)
	H.r(canvas, -8.0, -14.0, 2.0, 2.0, Color8(220, 78, 80), 0.80, _tint)
