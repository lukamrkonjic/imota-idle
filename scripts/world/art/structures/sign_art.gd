extends RefCounted
class_name SignArt

const PixelPalette := preload("res://scripts/world/art/core/pixel_palette.gd")
const PixelDraw := preload("res://scripts/world/art/core/pixel_draw.gd")


static func draw(canvas: CanvasItem) -> void:
	PixelDraw.draw_foot_shadow(canvas, 12.0, 3.0)
	var wood_a := PixelPalette.hex(0x8A6848)
	var wood_b := PixelPalette.hex(0x6A4830)
	var sand_a := PixelPalette.hex(0xC4A060)
	PixelDraw.px_rect(canvas, -2.0, -16.0, 4.0, 16.0, wood_b)
	PixelDraw.px_rect(canvas, -18.0, -22.0, 36.0, 12.0, wood_a)
	PixelDraw.px_rect(canvas, -16.0, -20.0, 32.0, 8.0, sand_a)
	PixelDraw.px_rect(canvas, -14.0, -18.0, 28.0, 2.0, PixelPalette.pal("trunk_b"), 0.6)
	PixelDraw.px_rect(canvas, -14.0, -14.0, 28.0, 2.0, PixelPalette.pal("trunk_b"), 0.6)
	PixelDraw.px_rect(canvas, -15.0, -19.0, 2.0, 2.0, PixelPalette.pal("stone_b"))
	PixelDraw.px_rect(canvas, 13.0, -19.0, 2.0, 2.0, PixelPalette.pal("stone_b"))


