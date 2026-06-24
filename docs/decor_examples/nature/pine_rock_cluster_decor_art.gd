extends RefCounted
class_name PineRockClusterDecorArt

const PixelPalette := preload("res://scripts/world/art/core/pixel_palette.gd")
const PixelDraw := preload("res://scripts/world/art/core/pixel_draw.gd")
const H := preload("res://scripts/world/art/decor/nature/nature_decor_helpers.gd")


static func draw(canvas: CanvasItem, variant: int, _tint: Color) -> void:
	H.conifer_tree(canvas, variant, 38.0, 24.0, 4, _tint)
	H.rock(canvas, variant, 16.0, 9.0, true, _tint)
	H.r(canvas, -20.0, -5.0, 8.0, 4.0, H.stone_mid(), 0.72, _tint)
