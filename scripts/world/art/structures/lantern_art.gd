extends RefCounted
class_name LanternArt
## A small standing lantern: a stone foot, an iron housing built as a tiny iso
## block, and a glowing glass pane that casts a soft halo.

const PixelPalette := preload("res://scripts/world/art/core/pixel_palette.gd")
const PixelDraw := preload("res://scripts/world/art/core/pixel_draw.gd")


static func draw(canvas: CanvasItem) -> void:
	PixelDraw.draw_foot_shadow(canvas, 6.0, 3.0, 0.3, 16.0)
	var iron := PixelPalette.pal("trunk_b")
	var lantern := PixelPalette.hex(0xF0C848)
	# stone foot
	PixelDraw.iso_block_tex(canvas, 0.0, 0.0, 3.0, 1.5, 3.0, PixelPalette.pal("stone_b"))
	# iron housing
	PixelDraw.iso_block_tex(canvas, 0.0, -3.0, 5.0, 2.5, 11.0, iron)
	# glowing glass pane on the lit face + flame core
	PixelDraw.px_rect(canvas, -3.0, -13.0, 6.0, 8.0, lantern, 0.9)
	PixelDraw.px_rect(canvas, -1.0, -11.0, 2.0, 4.0, Color.WHITE, 0.7)
	# soft halo
	PixelDraw.px_blob(canvas, 0.0, -9.0, 11.0, 8.0, lantern, 0.12)
