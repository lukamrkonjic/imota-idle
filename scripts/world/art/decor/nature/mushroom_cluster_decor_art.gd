extends RefCounted
class_name MushroomClusterDecorArt

const PixelPalette := preload("res://scripts/world/art/core/pixel_palette.gd")
const PixelDraw := preload("res://scripts/world/art/core/pixel_draw.gd")
const H := preload("res://scripts/world/art/decor/nature/nature_decor_helpers.gd")


static func draw(canvas: CanvasItem, variant: int, _tint: Color) -> void:
	H.shadow(canvas, 16.0, 0.08, _tint)
	H.mushroom(canvas, -5.0, 0.0, Color8(186, 62, 52), 1.0, _tint)
	H.mushroom(canvas, 1.0, 0.0, Color8(221, 178, 55), 1.15, _tint)
	H.mushroom(canvas, 7.0, 0.0, Color8(120, 68, 126), 0.75, _tint)
