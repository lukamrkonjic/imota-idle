extends RefCounted
class_name GrassTuftDecorArt

const PixelPalette := preload("res://scripts/world/art/core/pixel_palette.gd")
const PixelDraw := preload("res://scripts/world/art/core/pixel_draw.gd")
const H := preload("res://scripts/world/art/decor/nature/nature_decor_helpers.gd")


static func draw(canvas: CanvasItem, variant: int, _tint: Color) -> void:
	for i: int in range(7):
		var x := -6.0 + float(i) * 2.0
		var h := 4.0 + float((i + variant) % 4)
		H.r(canvas, x, -h, 1.0, h, H.leaf_dark(), 0.75, _tint)
		H.r(canvas, x + 1.0, -h + 1.0, 1.0, h - 1.0, H.leaf_mid(), 0.62, _tint)
