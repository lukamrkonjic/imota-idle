extends RefCounted
class_name LichenDecorArt

const PixelPalette := preload("res://scripts/world/art/core/pixel_palette.gd")
const PixelDraw := preload("res://scripts/world/art/core/pixel_draw.gd")


static func draw(canvas: CanvasItem, variant: int, _tint: Color) -> void:
	var px := float(PixelPalette.PX)
	var base := PixelPalette.pal("snow_a").lerp(PixelPalette.pal("grass_b"), 0.35)
	var spot := PixelPalette.pal("dirt_a").lerp(base, 0.5)
	var rx := (float(variant % 5) - 2.0) * px * 0.4
	PixelDraw.px_blob(canvas, rx, -px * 0.5, px * 2.0, px * 1.0, base, 0.65)
	PixelDraw.px_rect(canvas, rx, -px, px, px, spot, 0.55)
