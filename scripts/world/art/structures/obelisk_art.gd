extends RefCounted
class_name ObeliskArt
## A tall tapering monolith built from a stack of narrowing isometric blocks —
## plinth, three shaft segments and a pyramidion cap — with floating glyph glows
## up the lit face (animated by `t`; brighter and violet when `attuned`).

const PixelPalette := preload("res://scripts/world/art/core/pixel_palette.gd")
const PixelDraw := preload("res://scripts/world/art/core/pixel_draw.gd")


static func draw(canvas: CanvasItem, t: float, attuned: bool) -> void:
	PixelDraw.draw_foot_shadow(canvas, 14.0, 7.0, 0.3, 64.0)
	PixelDraw.draw_ground_collar(canvas, 13.0, true)
	var stone := PixelPalette.hex(0x4E4A5C)
	# plinth
	PixelDraw.iso_block_tex(canvas, 0.0, 0.0, 12.0, 6.0, 8.0, PixelPalette.shade(stone, 0.85))
	# tapering shaft in three segments
	PixelDraw.iso_block_tex(canvas, 0.0, -8.0, 8.0, 4.0, 18.0, stone)
	PixelDraw.iso_block_tex(canvas, 0.0, -26.0, 6.5, 3.25, 16.0, PixelPalette.shade(stone, 1.02))
	PixelDraw.iso_block_tex(canvas, 0.0, -42.0, 5.0, 2.5, 14.0, stone)
	# pyramidion cap
	PixelDraw.iso_block_tex(canvas, 0.0, -56.0, 3.5, 1.75, 6.0, PixelPalette.shade(stone, 1.12))
	# glyph glows drifting up the lit face
	var glow := Color(0.85, 0.4, 0.9) if attuned else Color(0.4, 0.5, 0.6)
	var pulse := 0.5 + sin(t * 3.0) * 0.3
	PixelDraw.px_rect(canvas, -2.0, -44.0 + sin(t * 2.0) * 3.0, 4.0, 4.0, glow, pulse)
	PixelDraw.px_rect(canvas, -2.0, -30.0 + sin(t * 2.0 + 1.7) * 3.0, 4.0, 4.0, glow, pulse * 0.8)
