extends RefCounted
class_name SignArt
## A roadside signpost: an isometric wooden post block carrying a painted board.
## The board itself is a thin plane facing the reader (correct for signage); the
## post is built as an iso block so its foot sits in the world.

const PixelPalette := preload("res://scripts/world/art/core/pixel_palette.gd")
const PixelDraw := preload("res://scripts/world/art/core/pixel_draw.gd")


static func draw(canvas: CanvasItem) -> void:
	PixelDraw.draw_foot_shadow(canvas, 11.0, 4.0, 0.3, 22.0)
	var wood_a := PixelPalette.hex(0x8A6848)
	var wood_b := PixelPalette.hex(0x6A4830)
	var sand_a := PixelPalette.hex(0xC4A060)
	# post (iso block)
	PixelDraw.iso_block_tex(canvas, 0.0, 0.0, 2.5, 1.25, 16.0, wood_b)
	# board frame + face
	PixelDraw.px_rect(canvas, -18.0, -22.0, 36.0, 12.0, wood_a)
	PixelDraw.px_rect(canvas, -16.0, -20.0, 32.0, 8.0, sand_a)
	PixelDraw.px_rect(canvas, -14.0, -18.0, 28.0, 2.0, PixelPalette.pal("trunk_b"), 0.6)
	PixelDraw.px_rect(canvas, -14.0, -14.0, 28.0, 2.0, PixelPalette.pal("trunk_b"), 0.6)
	PixelDraw.px_rect(canvas, -15.0, -19.0, 2.0, 2.0, PixelPalette.pal("stone_b"))
	PixelDraw.px_rect(canvas, 13.0, -19.0, 2.0, 2.0, PixelPalette.pal("stone_b"))
