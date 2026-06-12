extends RefCounted
class_name FernDecorArt

const PixelPalette := preload("res://scripts/world/art/core/pixel_palette.gd")
const PixelDraw := preload("res://scripts/world/art/core/pixel_draw.gd")


static func draw(canvas: CanvasItem, variant: int, _tint: Color) -> void:
	var dark := PixelPalette.pal("grass_c").lerp(PixelPalette.pal("grass_a"), 0.35)
	var mid := PixelPalette.pal("grass_a")
	var hi := PixelPalette.pal("grass_b").lerp(PixelPalette.pal("grass_a"), 0.30)
	var px := float(PixelPalette.PX)
	PixelDraw.px_rect(canvas, -px * 0.5, -px * 4.0, px, px * 4.0, dark, 0.72)
	for i: int in range(4):
		var y := -px * float(i + 1)
		PixelDraw.px_rect(canvas, -px * float(i + 1), y, px * float(i + 1), px, mid, 0.72)
		PixelDraw.px_rect(canvas, px, y - px * 0.5, px * float(i + 1), px, hi, 0.55)
