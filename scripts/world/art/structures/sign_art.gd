extends RefCounted
class_name SignArt
## A roadside signpost redrawn chunky and low-res to match the chest/barrel set:
## a fat iso post block carrying a thick blocky board built from a few bold value
## bands — no thin trim, reads instantly at a glance.

const PixelPalette := preload("res://scripts/world/art/core/pixel_palette.gd")
const PixelDraw := preload("res://scripts/world/art/core/pixel_draw.gd")


static func draw(canvas: CanvasItem) -> void:
	PixelDraw.draw_foot_shadow(canvas, 12.0, 5.0, 0.3, 26.0)
	PixelDraw.draw_ground_collar(canvas, 8.0, true)
	var wood := PixelPalette.hex(0x7A5436)
	var wood_d := PixelPalette.shade(wood, 0.66)
	var wood_l := PixelPalette.shade(wood, 1.16)
	var board := PixelPalette.hex(0xB8945A)
	var board_d := PixelPalette.shade(board, 0.72)
	var board_l := PixelPalette.shade(board, 1.12)

	# Fat post built as a chunky iso block so its foot sits in the world.
	PixelDraw.iso_block_tex(canvas, 0.0, 0.0, 4.0, 2.0, 20.0, wood)

	# Thick board: a bold dark frame mass, then a lighter inset face. Two broad
	# value bands across the face read as a low-res painted plank, not thin lines.
	PixelDraw.px_rect(canvas, -20.0, -36.0, 40.0, 18.0, wood_d)
	PixelDraw.px_rect(canvas, -20.0, -36.0, 40.0, 4.0, wood_l, 0.9)
	PixelDraw.px_rect(canvas, -16.0, -33.0, 32.0, 12.0, board)
	PixelDraw.px_rect(canvas, -16.0, -33.0, 32.0, 5.0, board_l, 0.85)
	PixelDraw.px_rect(canvas, -16.0, -25.0, 32.0, 4.0, board_d, 0.7)
	# Two chunky carved pegs anchoring the board to the post.
	PixelDraw.px_rect(canvas, -6.0, -18.0, 12.0, 4.0, wood_d)
