extends RefCounted
class_name BridgeArt
## A short stone footbridge reduced to a few bold, toy-like masses: one chunky
## raised deck slab, a lighter walking diamond on top, and four fat corner posts.
## No thin rails or construction detail — it reads as a sturdy low-res crossing.

const PixelPalette := preload("res://scripts/world/art/core/pixel_palette.gd")
const PixelDraw := preload("res://scripts/world/art/core/pixel_draw.gd")


static func draw(canvas: CanvasItem) -> void:
	PixelDraw.draw_foot_shadow(canvas, 24.0, 12.0, 0.3, 14.0)
	var stone := PixelPalette.pal("stone_b")
	var deck := PixelPalette.shade(stone, 1.08)
	# Raised deck: one thick iso slab carrying the walking surface.
	PixelDraw.iso_block_tex(canvas, 0.0, 0.0, 22.0, 11.0, 7.0, PixelPalette.shade(stone, 0.86))
	PixelDraw.px_diamond(canvas, 0.0, -7.0, 19.0, 9.0, deck)
	# A single broad darker band across the deck for a low-res walking strip.
	PixelDraw.px_diamond(canvas, 0.0, -7.0, 10.0, 5.0, PixelPalette.shade(deck, 0.84), 0.55)
	# Four fat corner posts — bold chunky blocks, not narrow rails.
	for p: Vector2 in [Vector2(-19.0, 0.0), Vector2(19.0, 0.0), Vector2(0.0, -9.0), Vector2(0.0, 9.0)]:
		PixelDraw.iso_block_tex(canvas, p.x, p.y - 7.0, 4.5, 2.25, 10.0, stone)
