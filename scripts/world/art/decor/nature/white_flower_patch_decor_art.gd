extends RefCounted
class_name WhiteFlowerPatchDecorArt

const PixelPalette := preload("res://scripts/world/art/core/pixel_palette.gd")
const PixelDraw := preload("res://scripts/world/art/core/pixel_draw.gd")
const H := preload("res://scripts/world/art/decor/nature/nature_decor_helpers.gd")


static func draw(canvas: CanvasItem, variant: int, _tint: Color) -> void:
	for i: int in range(5):
		var x := -8.0 + float(i) * 4.0
		H.flower(canvas, x, 0.0, Color8(238, 246, 230), _tint)
