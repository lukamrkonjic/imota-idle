extends RefCounted
class_name LogDecorArt
## Fallen mossy log lying across the forest floor.

const PixelPalette := preload("res://scripts/world/art/core/pixel_palette.gd")
const PixelDraw := preload("res://scripts/world/art/core/pixel_draw.gd")


static func draw(canvas: CanvasItem, variant: int, _tint: Color) -> void:
	var px := float(PixelPalette.PX)
	var bark := PixelPalette.pal("trunk_b")
	var bark_lit := PixelPalette.pal("trunk_a")
	var len := px * (4.0 + float(variant % 3))
	var flip := -1.0 if variant % 2 == 0 else 1.0
	PixelDraw.draw_foot_shadow(canvas, len * 0.7, 3.0, 0.22)
	# Trunk lying at a slight diagonal: stepped pixel runs.
	var steps := int(len / px)
	for i: int in steps:
		var x := (-len * 0.5 + float(i) * px) * flip
		var y := -px - floorf(float(i) * 0.25) * px * 0.5 * flip
		PixelDraw.px_rect(canvas, x, y, px, px * 2.0, bark if i % 3 != 0 else bark_lit)
	# Cut end ring + moss strip.
	PixelDraw.px_rect(canvas, -len * 0.5 * flip - px * 0.5, -px * 1.5, px, px * 2.0, PixelPalette.shade(bark_lit, 1.12))
	PixelDraw.px_row(canvas, len * 0.12 * flip, -px * 2.0, len * 0.28, PixelPalette.pal("moss"), 0.6)
