extends RefCounted
class_name BridgeArt
## A short stone footbridge deck with low parapets — drawn over a carved canal
## tile so the city road crosses the water.

const PixelPalette := preload("res://scripts/world/art/core/pixel_palette.gd")
const PixelDraw := preload("res://scripts/world/art/core/pixel_draw.gd")


static func draw(canvas: CanvasItem) -> void:
	var stone := PixelPalette.pal("stone_b")
	var stone_hi := PixelPalette.pal("stone_a")
	var deck := PixelPalette.shade(stone, 1.05)
	# deck slab spanning the tile
	PixelDraw.px_diamond(canvas, 0.0, 0.0, 22.0, 11.0, PixelPalette.shade(stone, 0.9))
	PixelDraw.px_diamond(canvas, 0.0, -1.0, 19.0, 9.0, deck)
	# low parapets along both edges
	PixelDraw.px_rect(canvas, -20.0, -8.0, 6.0, 8.0, stone)
	PixelDraw.px_rect(canvas, -20.0, -8.0, 6.0, 2.0, stone_hi)
	PixelDraw.px_rect(canvas, 14.0, -8.0, 6.0, 8.0, stone)
	PixelDraw.px_rect(canvas, 14.0, -8.0, 6.0, 2.0, stone_hi)
