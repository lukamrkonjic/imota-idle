extends RefCounted
class_name SpikyPalmDecorArt

const PixelPalette := preload("res://scripts/world/art/core/pixel_palette.gd")
const PixelDraw := preload("res://scripts/world/art/core/pixel_draw.gd")
const H := preload("res://scripts/world/art/decor/nature/nature_decor_helpers.gd")


static func draw(canvas: CanvasItem, variant: int, _tint: Color) -> void:
	H.shadow(canvas, 24.0, 0.11, _tint)
	H.trunk(canvas, 0.0, -24.0, 0.0, 5.0, _tint)
	for i: int in range(12):
		var side := -1.0 if i < 6 else 1.0
		var len := 7.0 + float(i % 4)
		for j: int in range(int(len)):
			H.r(canvas, side * float(j), -24.0 + float(i % 6) - float(j) * 0.65, 2.0, 1.0, H.leaf_mid(), 0.82, _tint)
