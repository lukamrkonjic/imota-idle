extends RefCounted
class_name AutumnTreeDecorArt

const PixelPalette := preload("res://scripts/world/art/core/pixel_palette.gd")
const PixelDraw := preload("res://scripts/world/art/core/pixel_draw.gd")
const H := preload("res://scripts/world/art/decor/nature/nature_decor_helpers.gd")


static func draw(canvas: CanvasItem, variant: int, _tint: Color) -> void:
	H.broadleaf_tree(canvas, variant, 30.0, 18.0, 14.0, 1, _tint)
	H.blob(canvas, 8.0, -45.0, 8.0, 6.0, H.leaf_autumn(), 0.55, _tint)
