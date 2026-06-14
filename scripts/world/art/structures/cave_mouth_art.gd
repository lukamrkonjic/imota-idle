extends RefCounted
class_name CaveMouthArt

const PixelPalette := preload("res://scripts/world/art/core/pixel_palette.gd")
const PixelDraw := preload("res://scripts/world/art/core/pixel_draw.gd")


static func draw(canvas: CanvasItem) -> void:
	PixelDraw.draw_foot_shadow(canvas, 26.0, 5.0, 0.3, 12.0)
	var rock_a := PixelPalette.pal("stone_a")
	var rock_b := PixelPalette.pal("stone_b")
	PixelDraw.px_blob(canvas, 0.0, -14.0, 28.0, 18.0, rock_b)
	PixelDraw.px_blob(canvas, -6.0, -20.0, 18.0, 12.0, rock_a)
	PixelDraw.px_rect(canvas, -10.0, -16.0, 20.0, 16.0, Color(0.06, 0.05, 0.08))
	PixelDraw.px_rect(canvas, -6.0, -20.0, 12.0, 4.0, Color(0.06, 0.05, 0.08))
	PixelDraw.px_rect(canvas, 12.0, -8.0, 6.0, 6.0, rock_a, 0.8)
	PixelDraw.px_rect(canvas, -18.0, -6.0, 5.0, 5.0, rock_a, 0.7)


