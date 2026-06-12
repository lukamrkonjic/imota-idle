extends RefCounted
class_name ShrubDecorArt

const PixelPalette := preload("res://scripts/world/art/core/pixel_palette.gd")
const PixelDraw := preload("res://scripts/world/art/core/pixel_draw.gd")


static func draw(canvas: CanvasItem, variant: int, _tint: Color) -> void:
	var px := float(PixelPalette.PX)
	var a := PixelPalette.pal("grass_c").lerp(PixelPalette.pal("grass_a"), 0.22)
	var b := PixelPalette.pal("grass_a").lerp(PixelPalette.pal("grass_b"), 0.18)
	PixelDraw.draw_foot_shadow(canvas, px * 3.0, px * 0.9, 0.18)
	PixelDraw.px_blob(canvas, -px * 0.9, -px * 1.7, px * 2.0, px * 1.4, a, 0.92)
	PixelDraw.px_blob(canvas, px * 1.0, -px * 1.9, px * 2.1, px * 1.5, b, 0.86)
	PixelDraw.px_rect(canvas, -px * 2.0, -px * 2.4, px, px, PixelPalette.shade(b, 1.06), 0.75)
	if variant % 5 == 0:
		PixelDraw.px_rect(canvas, px, -px * 2.2, px, px, PixelPalette.pal("dirt_b"), 0.80)
