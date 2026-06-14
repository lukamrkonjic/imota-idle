extends RefCounted
class_name RubblePileArt
## A heap of collapsed masonry — stacked broken blocks reclaimed by moss.
## Variant scales the mound so scattered piles vary in bulk.

const PixelPalette := preload("res://scripts/world/art/core/pixel_palette.gd")
const PixelDraw := preload("res://scripts/world/art/core/pixel_draw.gd")


static func draw(canvas: CanvasItem, variant: int = 0) -> void:
	var stone := PixelPalette.pal("stone_b")
	var stone_hi := PixelPalette.pal("stone_a")
	var moss := PixelPalette.pal("grass_a").lerp(stone, 0.3)
	var s := 0.85 + float(variant % 3) * 0.28
	PixelDraw.draw_foot_shadow(canvas, 15.0 * s, 4.0)
	# stacked broken blocks
	PixelDraw.px_rect(canvas, -14.0 * s, -8.0 * s, 28.0 * s, 8.0 * s, PixelPalette.shade(stone, 0.8))
	PixelDraw.px_rect(canvas, -10.0 * s, -15.0 * s, 14.0 * s, 8.0 * s, stone)
	PixelDraw.px_rect(canvas, 2.0 * s, -12.0 * s, 10.0 * s, 6.0 * s, PixelPalette.shade(stone, 0.9))
	PixelDraw.px_rect(canvas, -6.0 * s, -19.0 * s, 8.0 * s, 6.0 * s, stone_hi)
	# moss crest + a few loose chips
	PixelDraw.px_rect(canvas, -10.0 * s, -15.0 * s, 14.0 * s, 2.0, moss, 0.5)
	PixelDraw.px_rect(canvas, 9.0 * s, -5.0 * s, 4.0, 4.0, PixelPalette.shade(stone, 0.85), 0.85)
	if variant % 2 == 0:
		PixelDraw.px_rect(canvas, -13.0 * s, -4.0 * s, 4.0, 4.0, PixelPalette.shade(stone, 0.85), 0.8)
