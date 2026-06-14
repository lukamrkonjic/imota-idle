extends RefCounted
class_name TwistedTreeDecorArt

const PixelPalette := preload("res://scripts/world/art/core/pixel_palette.gd")
const PixelDraw := preload("res://scripts/world/art/core/pixel_draw.gd")
const H := preload("res://scripts/world/art/decor/nature/nature_decor_helpers.gd")


static func draw(canvas: CanvasItem, variant: int, _tint: Color) -> void:
	H.shadow(canvas, 32.0, 0.12, _tint)
	for i: int in range(28):
		var x := sin(float(i) * 0.35) * 5.0
		H.r(canvas, x - 2.0, -float(i), 4.0, 1.0, H.bark_dark(), 0.95, _tint)
		H.r(canvas, x - 1.0, -float(i), 2.0, 1.0, H.bark_mid(), 0.85, _tint)
	H.broadleaf_tree(canvas, variant, 30.0, 14.0, 10.0, 0, _tint)
