extends RefCounted
class_name AltarArt
## A ceremonial stone altar built as a stack of isometric blocks: a stepped base,
## a tall offering table and a capstone, with a pulsing glow / offering flame
## hovering over the slab (animated by `t`, tinted by `glow_color`).

const PixelPalette := preload("res://scripts/world/art/core/pixel_palette.gd")
const PixelDraw := preload("res://scripts/world/art/core/pixel_draw.gd")


static func draw(canvas: CanvasItem, t: float, glow_color: Color) -> void:
	PixelDraw.draw_foot_shadow(canvas, 22.0, 9.0, 0.3, 30.0)
	PixelDraw.draw_ground_collar(canvas, 18.0, true)
	var stone := PixelPalette.pal("stone_b")
	# stepped base
	PixelDraw.iso_block_tex(canvas, 0.0, 0.0, 18.0, 9.0, 7.0, PixelPalette.shade(stone, 0.86))
	# offering table
	PixelDraw.iso_block_tex(canvas, 0.0, -7.0, 13.0, 6.5, 14.0, stone)
	# capstone slab, slightly overhanging
	PixelDraw.iso_block_tex(canvas, 0.0, -21.0, 15.0, 7.5, 4.0, PixelPalette.shade(stone, 1.06))
	# carved seam down the lit face
	PixelDraw.px_rect(canvas, 3.0, -19.0, 1.5, 11.0, PixelPalette.shade(stone, 0.8), 0.5)
	# pulsing offering glow above the slab
	var pulse := 0.55 + sin(t * 2.2) * 0.25
	PixelDraw.px_rect(canvas, -8.0, -31.0, 16.0, 6.0, glow_color, pulse)
	PixelDraw.px_rect(canvas, -3.0, -35.0, 6.0, 4.0, glow_color.lightened(0.3), pulse * 0.8)
