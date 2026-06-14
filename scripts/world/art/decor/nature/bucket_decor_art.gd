extends RefCounted
class_name BucketDecorArt

const PixelPalette := preload("res://scripts/world/art/core/pixel_palette.gd")
const PixelDraw := preload("res://scripts/world/art/core/pixel_draw.gd")
const H := preload("res://scripts/world/art/decor/nature/nature_decor_helpers.gd")


static func draw(canvas: CanvasItem, variant: int, _tint: Color) -> void:
	H.shadow(canvas, 13.0, 0.08, _tint)
	H.r(canvas, -6.0, -13.0, 12.0, 12.0, H.bark_dark(), 0.95, _tint)
	H.r(canvas, -4.0, -11.0, 8.0, 9.0, H.bark_mid(), 0.85, _tint)
	H.r(canvas, -5.0, -15.0, 10.0, 3.0, H.bark_hi(), 0.55, _tint)
