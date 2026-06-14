extends RefCounted
class_name SmallSproutDecorArt

const PixelPalette := preload("res://scripts/world/art/core/pixel_palette.gd")
const PixelDraw := preload("res://scripts/world/art/core/pixel_draw.gd")
const H := preload("res://scripts/world/art/decor/nature/nature_decor_helpers.gd")


static func draw(canvas: CanvasItem, variant: int, _tint: Color) -> void:
	H.r(canvas, -0.5, -9.0, 1.0, 9.0, H.leaf_dark(), 0.75, _tint)
	H.blob(canvas, -3.0, -5.0, 3.0, 2.0, H.leaf_mid(), 0.75, _tint)
	H.blob(canvas, 3.0, -7.0, 3.0, 2.0, H.leaf_hi(), 0.65, _tint)
