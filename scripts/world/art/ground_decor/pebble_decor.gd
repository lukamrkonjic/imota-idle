extends RefCounted
class_name PebbleDecorArt

const PixelPalette := preload("res://scripts/world/art/core/pixel_palette.gd")
const PixelDraw := preload("res://scripts/world/art/core/pixel_draw.gd")


static func draw(canvas: CanvasItem, variant: int, _tint: Color) -> void:
	var px := float(PixelPalette.PX)
	var a := PixelPalette.pal("stone_b").lerp(PixelPalette.pal("grass_a"), 0.28)
	var b := PixelPalette.pal("stone_a").lerp(PixelPalette.pal("grass_a"), 0.35)
	PixelDraw.px_blob(canvas, -px, -px * 0.6, px * 1.6, px, a, 0.82)
	if variant % 3 != 0:
		PixelDraw.px_rect(canvas, px, -px, px, px, b, 0.68)
