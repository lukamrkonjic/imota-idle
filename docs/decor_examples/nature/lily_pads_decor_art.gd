extends RefCounted
class_name LilyPadsDecorArt

const PixelPalette := preload("res://scripts/world/art/core/pixel_palette.gd")
const PixelDraw := preload("res://scripts/world/art/core/pixel_draw.gd")
const H := preload("res://scripts/world/art/decor/nature/nature_decor_helpers.gd")


static func draw(canvas: CanvasItem, variant: int, _tint: Color) -> void:
	H.blob(canvas, -7.0, -1.0, 6.0, 3.0, Color8(63, 162, 98), 0.70, _tint)
	H.blob(canvas, 5.0, -3.0, 7.0, 4.0, Color8(78, 176, 108), 0.72, _tint)
	H.r(canvas, 4.0, -4.0, 3.0, 1.0, Color8(26, 86, 76), 0.32, _tint)
