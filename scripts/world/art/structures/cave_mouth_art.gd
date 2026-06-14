extends RefCounted
class_name CaveMouthArt
## Earthy animal burrow / cave mouth. It reads as a dug-in mound with roots and
## stones instead of a flat grey low-poly block.

const PixelPalette := preload("res://scripts/world/art/core/pixel_palette.gd")
const PixelDraw := preload("res://scripts/world/art/core/pixel_draw.gd")


static func draw(canvas: CanvasItem) -> void:
	PixelDraw.draw_foot_shadow(canvas, 25.0, 8.0, 0.3, 22.0)
	PixelDraw.draw_ground_collar(canvas, 23.0, true, 8)
	var dirt := PixelPalette.pal("dirt_a")
	var dirt_d := PixelPalette.pal("dirt_b")
	var root := PixelPalette.pal("trunk_b")
	var stone := PixelPalette.pal("stone_b")
	var moss := PixelPalette.pal("grass_a").lerp(dirt, 0.35)
	var dark := PixelPalette.hex(0x111018)

	PixelDraw.px_blob(canvas, 0.0, -10.0, 30.0, 19.0, dirt_d)
	PixelDraw.px_blob(canvas, -6.0, -17.0, 21.0, 12.0, dirt)
	PixelDraw.px_blob(canvas, 8.0, -15.0, 18.0, 10.0, PixelPalette.shade(dirt, 0.92))

	# Arched dug-out opening with a chunky earthen rim.
	PixelDraw.px_blob(canvas, 0.0, -10.0, 15.0, 11.0, dark)
	PixelDraw.px_rect(canvas, -12.0, -11.0, 24.0, 13.0, dark)
	PixelDraw.px_blob(canvas, 0.0, -15.0, 20.0, 8.0, PixelPalette.shade(dirt, 0.78), 0.72)
	PixelDraw.px_blob(canvas, 0.0, -12.0, 15.0, 7.0, dark)

	# Roots, moss and stones tie the burrow to the same pixel language as trees.
	PixelDraw.px_rect(canvas, -18.0, -17.0, 10.0, 3.0, root, 0.75)
	PixelDraw.px_rect(canvas, 11.0, -18.0, 9.0, 3.0, root, 0.65)
	PixelDraw.px_rect(canvas, -14.0, -21.0, 4.0, 12.0, root, 0.5)
	PixelDraw.px_rect(canvas, -22.0, -5.0, 7.0, 5.0, stone, 0.9)
	PixelDraw.px_rect(canvas, 15.0, -7.0, 8.0, 5.0, PixelPalette.shade(stone, 1.08), 0.85)
	PixelDraw.px_rect(canvas, -10.0, -25.0, 15.0, 4.0, moss, 0.58)
	PixelDraw.px_rect(canvas, 5.0, -23.0, 9.0, 4.0, moss, 0.46)
