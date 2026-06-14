extends RefCounted
class_name MossDecorArt

const PixelPalette := preload("res://scripts/world/art/core/pixel_palette.gd")
const PixelDraw := preload("res://scripts/world/art/core/pixel_draw.gd")


static func draw(canvas: CanvasItem, variant: int, _tint: Color) -> void:
	var px := float(PixelPalette.PX)
	var moss := PixelPalette.pal("grass_a").lerp(PixelPalette.pal("water_a"), 0.18)
	var hi := PixelPalette.pal("grass_b")
	var rx := (float(variant % 7) - 3.0) * px * 0.35
	PixelDraw.px_blob(canvas, rx, -px, px * 2.4, px * 1.2, moss, 0.72)
	PixelDraw.px_rect(canvas, rx - px, -px * 0.5, px, px, hi, 0.45)
