extends RefCounted
class_name VineDecorArt

const PixelPalette := preload("res://scripts/world/art/core/pixel_palette.gd")
const PixelDraw := preload("res://scripts/world/art/core/pixel_draw.gd")


static func draw(canvas: CanvasItem, variant: int, _tint: Color) -> void:
	var px := float(PixelPalette.PX)
	var dark := PixelPalette.pal("grass_c")
	var mid := PixelPalette.pal("grass_a")
	var off := float(variant % 5) * px * 0.3 - px
	for i: int in 4:
		var y := -px * float(i + 1)
		PixelDraw.px_rect(canvas, off + px * float(i) * 0.4, y, px * 2.0, px, mid if i % 2 == 0 else dark, 0.68)
