extends RefCounted
class_name RubbleDecorArt
## Scattered broken masonry — small moss-streaked stone fragments. Sells the
## "old ruins reclaimed by the land" feel when sprinkled across stony biomes.

const PixelPalette := preload("res://scripts/world/art/core/pixel_palette.gd")
const PixelDraw := preload("res://scripts/world/art/core/pixel_draw.gd")


static func draw(canvas: CanvasItem, variant: int, _tint: Color) -> void:
	var px := float(PixelPalette.PX)
	var stone := PixelPalette.pal("stone_b")
	var stone_hi := PixelPalette.pal("stone_a")
	var moss := PixelPalette.pal("grass_a").lerp(PixelPalette.pal("water_a"), 0.2)
	PixelDraw.px_rect(canvas, -px * 1.5, -px, px * 2.0, px * 1.2, stone, 0.85)
	PixelDraw.px_rect(canvas, -px * 1.5, -px, px * 2.0, px * 0.4, moss, 0.5)
	if variant % 3 != 0:
		PixelDraw.px_rect(canvas, px * 0.6, -px * 0.6, px * 1.4, px, stone_hi, 0.8)
	if variant % 2 == 0:
		PixelDraw.px_rect(canvas, -px * 0.4, -px * 1.8, px, px, stone_hi, 0.75)
