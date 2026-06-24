extends RefCounted
class_name UprightLogDecorArt

const PixelPalette := preload("res://scripts/world/art/core/pixel_palette.gd")
const PixelDraw := preload("res://scripts/world/art/core/pixel_draw.gd")
const H := preload("res://scripts/world/art/decor/nature/nature_decor_helpers.gd")


static func draw(canvas: CanvasItem, variant: int, _tint: Color) -> void:
	H.shadow(canvas, 10.0, 0.08, _tint)
	# standing log stump as an iso block, lighter cut face on top
	H.iso(canvas, 0.0, 0.0, 4.0, 2.0, 24.0, H.bark_mid(), _tint)
	H.r(canvas, -4.0, -27.0, 8.0, 3.0, H.bark_hi(), 0.60, _tint)
