extends RefCounted
class_name CactusDecorArt

const PixelPalette := preload("res://scripts/world/art/core/pixel_palette.gd")
const PixelDraw := preload("res://scripts/world/art/core/pixel_draw.gd")


static func draw(canvas: CanvasItem, variant: int, _tint: Color) -> void:
	var px := float(PixelPalette.PX)
	var green := PixelPalette.pal("grass_c").lerp(PixelPalette.pal("grass_a"), 0.25)
	var hi := PixelPalette.pal("grass_b")
	var tall := variant % 3 == 0
	var h := px * (5.0 if tall else 3.5)
	PixelDraw.px_rect(canvas, -px * 0.5, -h, px, h, green, 0.82)
	if tall:
		PixelDraw.px_rect(canvas, px * 0.8, -h * 0.55, px * 1.6, px, green, 0.75)
		PixelDraw.px_rect(canvas, px * 0.8, -h * 0.55 - px * 1.2, px, px * 1.2, hi, 0.65)
	PixelDraw.px_rect(canvas, -px * 0.5, -h - px, px * 1.2, px, hi, 0.55)
