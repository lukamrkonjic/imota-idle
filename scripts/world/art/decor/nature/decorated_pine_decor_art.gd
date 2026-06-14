extends RefCounted
class_name DecoratedPineDecorArt

const PixelPalette := preload("res://scripts/world/art/core/pixel_palette.gd")
const PixelDraw := preload("res://scripts/world/art/core/pixel_draw.gd")
const H := preload("res://scripts/world/art/decor/nature/nature_decor_helpers.gd")


static func draw(canvas: CanvasItem, variant: int, _tint: Color) -> void:
	H.conifer_tree(canvas, variant, 46.0, 26.0, 5, _tint)
	for i: int in range(6):
		var x := -9.0 + float((i * 4 + variant) % 18)
		var y := -38.0 + float(i) * 5.0
		H.r(canvas, x, y, 2.0, 2.0, Color8(185, 74, 174), 0.85, _tint)
