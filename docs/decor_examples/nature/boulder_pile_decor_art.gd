extends RefCounted
class_name BoulderPileDecorArt

const PixelPalette := preload("res://scripts/world/art/core/pixel_palette.gd")
const PixelDraw := preload("res://scripts/world/art/core/pixel_draw.gd")
const H := preload("res://scripts/world/art/decor/nature/nature_decor_helpers.gd")


static func draw(canvas: CanvasItem, variant: int, _tint: Color) -> void:
	H.rock(canvas, variant, 23.0, 12.0, false, _tint)
	H.rock(canvas, variant + 1, 16.0, 9.0, false, _tint)
	H.r(canvas, -19.0, -6.0, 8.0, 4.0, H.stone_mid(), 0.75, _tint)
