extends RefCounted
class_name ShellDecorArt

const PixelPalette := preload("res://scripts/world/art/core/pixel_palette.gd")
const PixelDraw := preload("res://scripts/world/art/core/pixel_draw.gd")


static func draw(canvas: CanvasItem, _variant: int, _tint: Color) -> void:
	var px := float(PixelPalette.PX)
	var shell := PixelPalette.pal("dirt_a").lerp(PixelPalette.pal("snow_a"), 0.45)
	PixelDraw.px_blob(canvas, 0.0, -px * 0.5, px * 2.2, px * 1.4, shell, 0.72)
	PixelDraw.px_rect(canvas, -px * 0.5, -px, px, px, PixelPalette.shade(shell, 0.88), 0.55)
