extends RefCounted
class_name MatureOakTreeDecorArt

const PixelPalette := preload("res://scripts/world/art/core/pixel_palette.gd")
const PixelDraw := preload("res://scripts/world/art/core/pixel_draw.gd")
const H := preload("res://scripts/world/art/decor/nature/nature_decor_helpers.gd")


static func draw(canvas: CanvasItem, variant: int, _tint: Color) -> void:
	H.broadleaf_tree(canvas, variant, 42.0, 30.0, 20.0, 0, _tint)
	H.blob(canvas, -20.0, -54.0, 14.0, 11.0, H.leaf_mid(), 0.70, _tint)
	H.blob(canvas, 20.0, -55.0, 13.0, 10.0, H.leaf_dark(), 0.55, _tint)
