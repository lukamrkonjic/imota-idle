extends RefCounted
class_name StickDecorArt

const PixelPalette := preload("res://scripts/world/art/core/pixel_palette.gd")
const PixelDraw := preload("res://scripts/world/art/core/pixel_draw.gd")


static func draw(canvas: CanvasItem, variant: int, _tint: Color) -> void:
	var px := float(PixelPalette.PX)
	var a := PixelPalette.pal("trunk_b")
	var b := PixelPalette.pal("trunk_a")
	PixelDraw.px_rect(canvas, -px * 2.0, -px * 0.5, px * 5.0, px, a, 0.72)
	PixelDraw.px_rect(canvas, px, -px * 1.5, px * 3.0, px, b, 0.54)
	if variant % 2 == 0:
		PixelDraw.px_rect(canvas, -px * 3.0, -px * 1.0, px, px, a, 0.58)
