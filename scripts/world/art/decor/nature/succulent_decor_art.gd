extends RefCounted
class_name SucculentDecorArt

const PixelPalette := preload("res://scripts/world/art/core/pixel_palette.gd")
const PixelDraw := preload("res://scripts/world/art/core/pixel_draw.gd")
const H := preload("res://scripts/world/art/decor/nature/nature_decor_helpers.gd")


static func draw(canvas: CanvasItem, variant: int, _tint: Color) -> void:
	H.shadow(canvas, 16.0, 0.08, _tint)
	for i: int in range(8):
		var side := -1.0 if i < 4 else 1.0
		var x := side * float(i % 4) * 2.5
		H.blob(canvas, x, -3.0 - float(i % 3), 4.0, 2.0, Color8(102, 172, 117), 0.72, _tint)
	H.blob(canvas, 0.0, -6.0, 4.0, 3.0, Color8(163, 213, 139), 0.75, _tint)
