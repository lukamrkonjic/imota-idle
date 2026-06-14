extends RefCounted
class_name RootTreeDecorArt

const PixelPalette := preload("res://scripts/world/art/core/pixel_palette.gd")
const PixelDraw := preload("res://scripts/world/art/core/pixel_draw.gd")
const H := preload("res://scripts/world/art/decor/nature/nature_decor_helpers.gd")


static func draw(canvas: CanvasItem, variant: int, _tint: Color) -> void:
	H.shadow(canvas, 26.0, 0.12, _tint)
	H.trunk(canvas, 0.0, -26.0, -6.0, 6.0, _tint)
	for i: int in range(5):
		var side := -1.0 if i % 2 == 0 else 1.0
		var x0 := side * float(i + 2)
		if side < 0.0:
			H.r(canvas, x0 - 5.0, -6.0 + float(i), 5.0, 1.0, H.bark_dark(), 0.72, _tint)
		else:
			H.r(canvas, x0, -6.0 + float(i), 5.0, 1.0, H.bark_dark(), 0.72, _tint)
	H.blob(canvas, 0.0, -33.0, 12.0, 9.0, H.leaf_mid(), 0.85, _tint)
