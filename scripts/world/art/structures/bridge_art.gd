extends RefCounted
class_name BridgeArt
## A short stone footbridge — a 2:1 diamond deck spanning a carved canal tile,
## with low isometric parapet posts at the corners so the city road crosses the
## water and still reads as a solid raised crossing.

const PixelPalette := preload("res://scripts/world/art/core/pixel_palette.gd")
const PixelDraw := preload("res://scripts/world/art/core/pixel_draw.gd")


static func draw(canvas: CanvasItem) -> void:
	var stone := PixelPalette.pal("stone_b")
	var deck := PixelPalette.shade(stone, 1.05)
	# raised deck: a low iso slab carrying the walking surface diamond
	PixelDraw.iso_block_tex(canvas, 0.0, 0.0, 22.0, 11.0, 5.0, PixelPalette.shade(stone, 0.9))
	PixelDraw.px_diamond(canvas, 0.0, -5.0, 19.0, 9.0, deck)
	# low parapet posts at the four corners of the deck
	for p: Vector2 in [Vector2(-19.0, 0.0), Vector2(19.0, 0.0), Vector2(0.0, -9.0), Vector2(0.0, 9.0)]:
		PixelDraw.iso_block_tex(canvas, p.x, p.y - 5.0, 3.0, 1.5, 9.0, stone)
