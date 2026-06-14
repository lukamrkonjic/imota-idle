extends RefCounted
class_name BrokenWallArt
## A toppled, gap-toothed stone wall — uneven brick courses with a moss-lined
## crumbled crest. Variant rotates the height pattern and segment count, so
## walls vary in length and silhouette across a ruined site.

const PixelPalette := preload("res://scripts/world/art/core/pixel_palette.gd")
const PixelDraw := preload("res://scripts/world/art/core/pixel_draw.gd")

const HEIGHTS := [24.0, 34.0, 14.0, 30.0, 10.0, 32.0, 18.0, 28.0]


static func draw(canvas: CanvasItem, variant: int = 0) -> void:
	var stone := PixelPalette.pal("stone_b")
	var stone_hi := PixelPalette.pal("stone_a")
	var moss := PixelPalette.pal("grass_a").lerp(stone, 0.3)
	var bw := 9.0
	var n := 5 + variant % 3
	PixelDraw.draw_foot_shadow(canvas, float(n) * bw * 0.5 + 2.0, 5.0)
	var x := -float(n) * bw * 0.5
	for i: int in n:
		var bh: float = HEIGHTS[(i + variant) % HEIGHTS.size()]
		PixelDraw.px_rect(canvas, x, -bh, bw, bh, stone if i % 2 == 0 else PixelPalette.shade(stone, 0.88))
		PixelDraw.px_rect(canvas, x, -bh, bw, 3.0, stone_hi)            # lit top
		PixelDraw.px_rect(canvas, x, -bh, bw, 2.0, moss, 0.55)          # moss crest
		PixelDraw.px_rect(canvas, x, -5.0, 2.0, 5.0, PixelPalette.shade(stone, 0.7))  # mortar seam
		x += bw
