extends RefCounted
class_name GrassDecorArt

const PixelPalette := preload("res://scripts/world/art/core/pixel_palette.gd")
const PixelDraw := preload("res://scripts/world/art/core/pixel_draw.gd")


static func draw(canvas: CanvasItem, variant: int, tint: Color) -> void:
	var a := PixelPalette.pal("grass_c").lerp(PixelPalette.pal("grass_a"), 0.55).lerp(tint, 0.10)
	var b := PixelPalette.pal("grass_a").lerp(PixelPalette.pal("grass_b"), 0.35).lerp(tint, 0.08)
	var px := float(PixelPalette.PX)
	PixelDraw.px_rect(canvas, -px, -px * 2.0, px, px * 2.0, a, 0.70)
	PixelDraw.px_rect(canvas, px, -px * 1.5, px, px * 1.5, b, 0.62)
	if variant % 3 == 0:
		PixelDraw.px_rect(canvas, -px * 2.0, -px, px, px, b, 0.55)
