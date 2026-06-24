extends RefCounted
class_name LeafyPlantDecorArt

const PixelPalette := preload("res://scripts/world/art/core/pixel_palette.gd")
const PixelDraw := preload("res://scripts/world/art/core/pixel_draw.gd")
const H := preload("res://scripts/world/art/decor/nature/nature_decor_helpers.gd")


static func draw(canvas: CanvasItem, variant: int, _tint: Color) -> void:
	H.dense_bush(canvas, variant, 10.0, 9.0, Color(0, 0, 0, 0), _tint)
	for i: int in range(4):
		H.r(canvas, -7.0 + float(i) * 5.0, -6.0 - float((i + variant) % 3), 4.0, 2.0, H.leaf_hi(), 0.52, _tint)
