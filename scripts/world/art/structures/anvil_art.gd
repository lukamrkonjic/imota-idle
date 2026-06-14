extends RefCounted
class_name AnvilArt
## A blacksmith's anvil built from isometric blocks: a wooden stump base carries
## an iron body that necks in at the waist and flares to the face, with a horn
## jutting off the lit side and a glowing hot spot on top (animated by `t`).

const PixelPalette := preload("res://scripts/world/art/core/pixel_palette.gd")
const PixelDraw := preload("res://scripts/world/art/core/pixel_draw.gd")


static func draw(canvas: CanvasItem, t: float) -> void:
	PixelDraw.draw_foot_shadow(canvas, 18.0, 7.0, 0.3, 26.0)
	var wood := PixelPalette.pal("trunk_b")
	var iron := PixelPalette.hex(0x4A4A52)
	# wooden stump base
	PixelDraw.iso_block_tex(canvas, 0.0, 0.0, 11.0, 5.5, 11.0, wood)
	# iron foot of the anvil
	PixelDraw.iso_block_tex(canvas, 0.0, -11.0, 9.0, 4.5, 4.0, iron)
	# necked-in waist
	PixelDraw.iso_block_tex(canvas, 0.0, -15.0, 5.0, 2.5, 4.0, PixelPalette.shade(iron, 0.9))
	# flared face
	PixelDraw.iso_block_tex(canvas, 0.0, -19.0, 11.0, 5.5, 5.0, iron)
	# horn jutting off the lit (SE) side
	PixelDraw.iso_block_tex(canvas, 11.0, -20.0, 4.5, 2.25, 3.0, PixelPalette.shade(iron, 1.06))
	# glowing hot metal on the face
	var glow := 0.5 + sin(t * 5.0) * 0.25
	PixelDraw.px_rect(canvas, -4.0, -26.0, 6.0, 4.0, Color8(0xff, 0x66, 0x22), glow)
