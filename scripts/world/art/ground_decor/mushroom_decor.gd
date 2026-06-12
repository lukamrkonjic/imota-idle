extends RefCounted
class_name MushroomDecorArt

const PixelPalette := preload("res://scripts/world/art/core/pixel_palette.gd")
const PixelDraw := preload("res://scripts/world/art/core/pixel_draw.gd")


static func draw(canvas: CanvasItem, _variant: int, _tint: Color) -> void:
	var px := float(PixelPalette.PX)
	PixelDraw.px_rect(canvas, -px * 0.5, -px * 2.0, px, px * 2.0, PixelPalette.pal("snow_a"), 0.70)
	PixelDraw.px_blob(canvas, 0.0, -px * 2.3, px * 2.0, px, PixelPalette.pal("dirt_b"), 0.88)
	PixelDraw.px_rect(canvas, -px, -px * 2.6, px, px, PixelPalette.pal("snow_a"), 0.55)
