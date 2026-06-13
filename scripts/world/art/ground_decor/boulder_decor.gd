extends RefCounted
class_name BoulderDecorArt
## Half-buried boulder — bigger than a pebble, smaller than a rock node.

const PixelPalette := preload("res://scripts/world/art/core/pixel_palette.gd")
const PixelDraw := preload("res://scripts/world/art/core/pixel_draw.gd")


static func draw(canvas: CanvasItem, variant: int, _tint: Color) -> void:
	var px := float(PixelPalette.PX)
	var lit := PixelPalette.pal("stone_a")
	var dark := PixelPalette.pal("stone_b")
	var w := px * (2.6 + float(variant % 3) * 0.5)
	PixelDraw.draw_foot_shadow(canvas, w * 1.1, 3.0, 0.25)
	PixelDraw.px_blob(canvas, 0.0, -px * 0.8, w, px * 1.6, dark, 0.95)
	PixelDraw.px_blob(canvas, -w * 0.18, -px * 1.2, w * 0.62, px * 1.0, lit, 0.9)
	if variant % 2 == 0:
		PixelDraw.px_row(canvas, w * 0.1, -px * 0.4, w * 0.4, PixelPalette.pal("moss"), 0.55)
