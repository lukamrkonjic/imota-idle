extends RefCounted
class_name RubblePileArt
## A heap of collapsed masonry — broken iso blocks tumbled and stacked at jittered
## positions and heights, reclaimed by moss. Variant scales the mound so scattered
## piles vary in bulk.

const PixelPalette := preload("res://scripts/world/art/core/pixel_palette.gd")
const PixelDraw := preload("res://scripts/world/art/core/pixel_draw.gd")

# tumbled blocks: offset (x, y) on the ground, half-width, height
const BLOCKS := [
	[-8.0, 2.0, 6.0, 7.0],
	[5.0, 3.0, 5.0, 6.0],
	[-2.0, 0.0, 5.5, 12.0],
	[8.0, -1.0, 4.0, 8.0],
	[-9.0, -2.0, 3.5, 5.0],
]


static func draw(canvas: CanvasItem, variant: int = 0) -> void:
	var stone := PixelPalette.pal("stone_b")
	var moss := PixelPalette.pal("grass_a").lerp(stone, 0.3)
	var s := 0.85 + float(variant % 3) * 0.28
	PixelDraw.draw_foot_shadow(canvas, 15.0 * s, 5.0)
	PixelDraw.draw_ground_collar(canvas, 13.0 * s, true)
	# Draw back-to-front (smaller ground-y first) so nearer blocks overlap correctly.
	var order := BLOCKS.duplicate()
	order.sort_custom(func(a: Array, b: Array) -> bool: return float(a[1]) < float(b[1]))
	for i: int in order.size():
		var b: Array = order[i]
		var shade := 0.84 + 0.12 * float(i % 3)
		PixelDraw.iso_block_tex(canvas, float(b[0]) * s, float(b[1]) * s,
			float(b[2]) * s, float(b[2]) * 0.5 * s, float(b[3]) * s, PixelPalette.shade(stone, shade))
	# moss crest on the tallest central block
	PixelDraw.px_rect(canvas, -6.0 * s, -13.0 * s, 11.0 * s, 2.0, moss, 0.5)
