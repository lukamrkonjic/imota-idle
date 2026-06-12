extends RefCounted
class_name FlowerDecorArt

const PixelPalette := preload("res://scripts/world/art/core/pixel_palette.gd")
const PixelDraw := preload("res://scripts/world/art/core/pixel_draw.gd")
const GrassDecorArt := preload("res://scripts/world/art/ground_decor/grass_decor.gd")


static func draw(canvas: CanvasItem, variant: int, tint: Color) -> void:
	GrassDecorArt.draw(canvas, variant, tint)
	var px := float(PixelPalette.PX)
	PixelDraw.px_rect(canvas, -px * 0.5, -px * 4.0, px, px, PixelPalette.pal("snow_a"), 0.86)
	if variant % 2 == 0:
		PixelDraw.px_rect(canvas, px * 0.5, -px * 3.0, px, px, PixelPalette.pal("gold"), 0.76)
