extends RefCounted
# (no class_name: the existing ground_decor/fern_decor.gd already owns
# FernDecorArt; this file is referenced via the catalog's preload const.)

const PixelPalette := preload("res://scripts/world/art/core/pixel_palette.gd")
const PixelDraw := preload("res://scripts/world/art/core/pixel_draw.gd")


static func draw(canvas: CanvasItem, variant: int, _tint: Color) -> void:
	var dark := PixelPalette.pal("grass_c").lerp(PixelPalette.pal("grass_a"), 0.35)
	var mid := PixelPalette.pal("grass_a")
	var hi := PixelPalette.pal("grass_b").lerp(PixelPalette.pal("grass_a"), 0.30)
	if _tint.a > 0.0:
		dark = dark.lerp(Color(_tint.r, _tint.g, _tint.b, 1.0), clamp(_tint.a, 0.0, 0.70))
		mid = mid.lerp(Color(_tint.r, _tint.g, _tint.b, 1.0), clamp(_tint.a, 0.0, 0.70))
		hi = hi.lerp(Color(_tint.r, _tint.g, _tint.b, 1.0), clamp(_tint.a, 0.0, 0.70))
	var px := float(PixelPalette.PX)
	var lean := -1.0 if variant % 2 == 0 else 1.0
	PixelDraw.px_rect(canvas, -px * 0.5, -px * 4.0, px, px * 4.0, dark, 0.72)
	for i: int in range(4):
		var y := -px * float(i + 1)
		var spread := float(i + 1)
		PixelDraw.px_rect(canvas, -px * (spread + lean * 0.25), y, px * spread, px, mid, 0.72)
		PixelDraw.px_rect(canvas, px * (lean * 0.25), y - px * 0.5, px * spread, px, hi, 0.55)
	PixelDraw.px_rect(canvas, -px * 2.0, -px, px * 4.0, px, dark, 0.20)
