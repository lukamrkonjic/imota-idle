extends RefCounted
class_name BrambleDecorArt
## Tangled thorny overgrowth — crisscrossing dark twigs over a low leaf mound,
## with the odd berry. Reads as reclaiming undergrowth in forests and wastes.

const PixelPalette := preload("res://scripts/world/art/core/pixel_palette.gd")
const PixelDraw := preload("res://scripts/world/art/core/pixel_draw.gd")


static func draw(canvas: CanvasItem, variant: int, _tint: Color) -> void:
	var px := float(PixelPalette.PX)
	var twig := PixelPalette.shade(PixelPalette.pal("trunk_b"), 0.82)
	var leaf := PixelPalette.pal("grass_c")
	var berry := PixelPalette.pal("outfit_a")
	var spread := px * 2.2
	PixelDraw.px_blob(canvas, 0.0, -px * 0.6, spread, px * 1.1, leaf, 0.7)
	for i: int in 3:
		var rot := -0.7 + 0.7 * float(i) + float(variant % 3) * 0.18
		canvas.draw_set_transform(Vector2(0.0, -px * 0.6), rot, Vector2.ONE)
		PixelDraw.px_rect(canvas, -spread, -px * 0.4, spread * 2.0, px, twig, 0.78)
		canvas.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	if variant % 2 == 0:
		PixelDraw.px_rect(canvas, px * 0.6, -px * 1.6, px, px, berry, 0.8)
