extends RefCounted
class_name BrokenStatueArt
## A headless robed statue on a plinth — a fallen city monument — built from
## isometric blocks: a stepped plinth, a robed torso prism snapped at the neck,
## and an optional arm stub, with moss creeping up the stone. Variant drives the
## height and whether the arm remains.

const PixelPalette := preload("res://scripts/world/art/core/pixel_palette.gd")
const PixelDraw := preload("res://scripts/world/art/core/pixel_draw.gd")


static func draw(canvas: CanvasItem, variant: int = 0) -> void:
	PixelDraw.draw_foot_shadow(canvas, 16.0, 6.0, 0.3, 56.0)
	var stone := PixelPalette.pal("stone_b")
	var moss := PixelPalette.pal("grass_a").lerp(stone, 0.32)
	var h := 48.0 + float(variant % 3) * 12.0
	# stepped plinth (two blocks)
	PixelDraw.iso_block_tex(canvas, 0.0, 0.0, 13.0, 6.5, 8.0, PixelPalette.shade(stone, 0.86))
	PixelDraw.iso_block_tex(canvas, 0.0, -8.0, 10.0, 5.0, 5.0, PixelPalette.shade(stone, 0.96))
	# robed torso prism, broken at the neck
	var th := h - 13.0
	PixelDraw.iso_block_tex(canvas, 0.0, -13.0, 8.0, 4.0, th, stone)
	# shoulders — a slightly wider block near the top
	PixelDraw.iso_block_tex(canvas, 0.0, -13.0 - (th - 7.0), 9.5, 4.75, 7.0, PixelPalette.shade(stone, 1.04))
	# snapped neck stub
	PixelDraw.iso_block_tex(canvas, 0.0, -h, 3.5, 1.8, 4.0, PixelPalette.shade(stone, 0.72))
	# robe fold seam down the lit face
	PixelDraw.px_rect(canvas, 1.0, -h + 12.0, 1.5, th - 16.0, PixelPalette.shade(stone, 0.84), 0.5)
	if variant % 2 == 0:
		# arm stub jutting from the lit (SE) side
		PixelDraw.iso_block_tex(canvas, 9.0, -13.0 - (th - 20.0), 3.0, 1.8, 12.0, PixelPalette.shade(stone, 0.92))
	# moss creep up the base of the torso
	PixelDraw.px_rect(canvas, -7.0, -22.0, 6.0, 11.0, moss, 0.45)
