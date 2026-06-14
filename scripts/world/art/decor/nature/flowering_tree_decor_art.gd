extends RefCounted
class_name FloweringTreeDecorArt

const PixelPalette := preload("res://scripts/world/art/core/pixel_palette.gd")
const PixelDraw := preload("res://scripts/world/art/core/pixel_draw.gd")
const H := preload("res://scripts/world/art/decor/nature/nature_decor_helpers.gd")


static func draw(canvas: CanvasItem, variant: int, _tint: Color) -> void:
	H.broadleaf_tree(canvas, variant, 28.0, 18.0, 14.0, 0, _tint)
	for i: int in range(9):
		var x := -14.0 + float((i * 5 + variant) % 28)
		var y := -47.0 + float((i * 7) % 18)
		H.r(canvas, x, y, 2.0, 2.0, Color8(235, 244, 222), 0.82, _tint)
