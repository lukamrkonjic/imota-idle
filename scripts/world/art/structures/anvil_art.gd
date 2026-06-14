extends RefCounted
class_name AnvilArt
## A blacksmith's anvil simplified into a bold, chunky silhouette to match the
## chest/barrel family: a fat wooden stump, one solid iron body, a wide flared
## face and a stubby horn. A glowing hot spot pulses on top (animated by `t`).

const PixelPalette := preload("res://scripts/world/art/core/pixel_palette.gd")
const PixelDraw := preload("res://scripts/world/art/core/pixel_draw.gd")


static func draw(canvas: CanvasItem, t: float) -> void:
	PixelDraw.draw_foot_shadow(canvas, 18.0, 7.0, 0.3, 26.0)
	PixelDraw.draw_ground_collar(canvas, 12.0, true)
	var wood := PixelPalette.pal("trunk_b")
	var iron := PixelPalette.hex(0x4A4A52)
	# Fat wooden stump base — one chunky block.
	PixelDraw.iso_block_tex(canvas, 0.0, 0.0, 12.0, 6.0, 12.0, wood)
	# One solid iron body — no fiddly waist, just a single bold mass.
	PixelDraw.iso_block_tex(canvas, 0.0, -12.0, 7.0, 3.5, 8.0, iron)
	# Wide flared face overhanging the body.
	PixelDraw.iso_block_tex(canvas, 0.0, -20.0, 12.0, 6.0, 5.0, PixelPalette.shade(iron, 1.08))
	# Stubby horn jutting off the lit (SE) side as one chunky block.
	PixelDraw.iso_block_tex(canvas, 12.0, -22.0, 5.0, 2.5, 4.0, PixelPalette.shade(iron, 1.12))
	# Glowing hot metal on the face.
	var glow := 0.5 + sin(t * 5.0) * 0.25
	PixelDraw.px_rect(canvas, -5.0, -28.0, 8.0, 4.0, Color8(0xff, 0x66, 0x22), glow)
