extends RefCounted
class_name GiantLeafTreeDecorArt

const PixelPalette := preload("res://scripts/world/art/core/pixel_palette.gd")
const PixelDraw := preload("res://scripts/world/art/core/pixel_draw.gd")
const H := preload("res://scripts/world/art/decor/nature/nature_decor_helpers.gd")


static func draw(canvas: CanvasItem, variant: int, _tint: Color) -> void:
	H.trunk(canvas, 0.0, -28.0, 0.0, 8.0, _tint)
	H.root_feet(canvas, 0.0, 0.0, 7.0, _tint)
	for i: int in range(7):
		var x := -24.0 + float(i) * 8.0
		H.blob(canvas, x, -39.0 - float(i % 2) * 5.0, 11.0, 18.0, H.leaf_blue(), 0.82, _tint)
		H.r(canvas, x, -54.0, 2.0, 18.0, H.leaf_dark(), 0.36, _tint)
