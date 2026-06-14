extends RefCounted
class_name BrokenStatueArt
## A headless robed statue on a plinth — a fallen city monument. Variant drives
## height and whether one arm stub remains, with moss creeping up the stone.

const PixelPalette := preload("res://scripts/world/art/core/pixel_palette.gd")
const PixelDraw := preload("res://scripts/world/art/core/pixel_draw.gd")


static func draw(canvas: CanvasItem, variant: int = 0) -> void:
	PixelDraw.draw_foot_shadow(canvas, 17.0, 5.0, 0.3, 56.0)
	var stone := PixelPalette.pal("stone_b")
	var stone_hi := PixelPalette.pal("stone_a")
	var moss := PixelPalette.pal("grass_a").lerp(stone, 0.32)
	var h := 48.0 + float(variant % 3) * 12.0
	# plinth
	PixelDraw.px_rect(canvas, -14.0, -12.0, 28.0, 12.0, PixelPalette.shade(stone, 0.74))
	PixelDraw.px_rect(canvas, -16.0, -15.0, 32.0, 4.0, stone_hi)
	# robed torso (broken at the neck)
	PixelDraw.px_rect(canvas, -9.0, -h, 18.0, h - 12.0, stone)
	PixelDraw.px_rect(canvas, -9.0, -h, 5.0, h - 12.0, stone_hi)
	PixelDraw.px_rect(canvas, -12.0, -h, 24.0, 7.0, stone)              # shoulders
	PixelDraw.px_rect(canvas, -4.0, -h - 3.0, 8.0, 4.0, PixelPalette.shade(stone, 0.7))  # snapped neck
	# robe folds
	PixelDraw.px_rect(canvas, -2.0, -h + 10.0, 2.0, h - 24.0, PixelPalette.shade(stone, 0.86), 0.55)
	if variant % 2 == 0:
		PixelDraw.px_rect(canvas, 9.0, -h + 9.0, 5.0, 13.0, PixelPalette.shade(stone, 0.86))  # arm stub
	# moss creep
	PixelDraw.px_rect(canvas, -9.0, -18.0, 6.0, 12.0, moss, 0.5)
