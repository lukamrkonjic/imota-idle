extends RefCounted
class_name ReedDecorArt

const PixelPalette := preload("res://scripts/world/art/core/pixel_palette.gd")
const PixelDraw := preload("res://scripts/world/art/core/pixel_draw.gd")


static func draw(canvas: CanvasItem, variant: int, _tint: Color) -> void:
	var px := float(PixelPalette.PX)
	var stem := PixelPalette.pal("grass_c").lerp(PixelPalette.pal("grass_b"), 0.35)
	var seed := PixelPalette.pal("dirt_b")
	for i: int in range(3):
		var x := px * float(i - 1)
		var h := px * float(4 + ((variant + i) % 3))
		PixelDraw.px_rect(canvas, x, -h, px, h, stem, 0.78)
		if (variant + i) % 2 == 0:
			PixelDraw.px_rect(canvas, x - px * 0.5, -h - px, px * 2.0, px, seed, 0.68)
