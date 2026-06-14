extends RefCounted
class_name StumpDecorArt

const PixelPalette := preload("res://scripts/world/art/core/pixel_palette.gd")
const PixelDraw := preload("res://scripts/world/art/core/pixel_draw.gd")
const H := preload("res://scripts/world/art/decor/nature/nature_decor_helpers.gd")


static func draw(canvas: CanvasItem, variant: int, _tint: Color) -> void:
	H.shadow(canvas, 17.0, 0.10, _tint)
	H.r(canvas, -7.0, -13.0, 14.0, 12.0, H.bark_dark(), 0.96, _tint)
	H.r(canvas, -5.0, -12.0, 10.0, 9.0, H.bark_mid(), 0.88, _tint)
	H.r(canvas, -6.0, -15.0, 12.0, 4.0, H.bark_hi(), 0.62, _tint)
	H.r(canvas, -2.0, -14.0, 4.0, 1.0, H.bark_dark(), 0.42, _tint)
	H.blob(canvas, -5.0, -15.0, 5.0, 2.0, H.leaf_mid(), 0.48, _tint)
