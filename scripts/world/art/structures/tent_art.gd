extends RefCounted
class_name TentArt

const PixelPalette := preload("res://scripts/world/art/core/pixel_palette.gd")
const PixelDraw := preload("res://scripts/world/art/core/pixel_draw.gd")


static func draw(canvas: CanvasItem, size: float, color: Color) -> void:
	var w := PixelPalette.snap(size)
	var hgt := PixelPalette.snap(size * 0.95)
	PixelDraw.draw_foot_shadow(canvas, w * 0.85)
	var row := 0.0
	while row < hgt:
		var t := row / hgt
		var half := PixelPalette.snap(w * (1.0 - t))
		PixelDraw.px_row(canvas, 0.0, -row, half, PixelPalette.shade(color, 1.05 - t * 0.12))
		PixelDraw.px_row(canvas, 0.0, -row, half * 0.42, PixelPalette.shade(color, 0.78 - t * 0.08), 0.85)
		row += PixelPalette.PX
	var px := float(PixelPalette.PX)
	PixelDraw.px_rect(canvas, -px * 2.0, -px * 2.0, px * 4.0, px * 4.0, Color(0.16, 0.11, 0.07), 0.85)
	PixelDraw.px_rect(canvas, -w - px * 2.0, 0.0, px * 2.0, px * 3.0, PixelPalette.pal("trunk_b"))
	PixelDraw.px_rect(canvas, w, 0.0, px * 2.0, px * 3.0, PixelPalette.pal("trunk_b"))


