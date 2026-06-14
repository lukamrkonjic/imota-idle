extends RefCounted
class_name DriftwoodDecorArt

const PixelPalette := preload("res://scripts/world/art/core/pixel_palette.gd")
const PixelDraw := preload("res://scripts/world/art/core/pixel_draw.gd")


static func draw(canvas: CanvasItem, variant: int, _tint: Color) -> void:
	var wood := PixelPalette.pal("trunk_b")
	var hi := PixelPalette.shade(wood, 1.12)
	var px := float(PixelPalette.PX)
	var ang := (float(variant % 8) - 4.0) * 0.18
	canvas.draw_set_transform(Vector2.ZERO, ang, Vector2.ONE)
	PixelDraw.px_rect(canvas, -px * 3.0, -px, px * 6.0, px * 1.2, wood, 0.78)
	PixelDraw.px_rect(canvas, px * 1.5, -px * 0.5, px * 2.0, px, hi, 0.55)
	canvas.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
