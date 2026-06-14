extends RefCounted
class_name BoneDecorArt

const PixelPalette := preload("res://scripts/world/art/core/pixel_palette.gd")
const PixelDraw := preload("res://scripts/world/art/core/pixel_draw.gd")


static func draw(canvas: CanvasItem, variant: int, _tint: Color) -> void:
	var px := float(PixelPalette.PX)
	var bone := PixelPalette.pal("snow_a").lerp(PixelPalette.pal("dirt_a"), 0.25)
	var rot := -0.35 if variant % 2 == 0 else 0.25
	canvas.draw_set_transform(Vector2.ZERO, rot, Vector2.ONE)
	PixelDraw.px_rect(canvas, -px * 2.0, -px * 0.5, px * 4.0, px, bone, 0.70)
	PixelDraw.px_blob(canvas, -px * 2.2, -px * 0.5, px * 1.2, px * 1.2, bone, 0.65)
	PixelDraw.px_blob(canvas, px * 2.2, -px * 0.5, px * 1.2, px * 1.2, bone, 0.65)
	canvas.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
