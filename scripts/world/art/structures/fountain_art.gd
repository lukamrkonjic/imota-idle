extends RefCounted
class_name FountainArt
## A grand tiered stone fountain — twin basins with a central spout and animated
## jets and shimmer. The civic centrepiece of a city plaza.

const PixelPalette := preload("res://scripts/world/art/core/pixel_palette.gd")
const PixelDraw := preload("res://scripts/world/art/core/pixel_draw.gd")


static func draw(canvas: CanvasItem, t: float) -> void:
	PixelDraw.draw_foot_shadow(canvas, 30.0, 8.0, 0.3, 20.0)
	var stone := PixelPalette.pal("stone_b")
	var stone_hi := PixelPalette.pal("stone_a")
	var water := PixelPalette.pal("water_a")
	var water_hi := PixelPalette.pal("water_foam")
	# lower basin rim
	PixelDraw.px_diamond(canvas, 0.0, 0.0, 30.0, 15.0, PixelPalette.shade(stone, 0.85))
	PixelDraw.px_diamond(canvas, 0.0, -2.0, 28.0, 14.0, stone_hi)
	# lower pool
	var shimmer := sin(t * 2.4) * 0.06
	PixelDraw.px_diamond(canvas, 0.0, -3.0, 23.0, 11.0, water.lerp(water_hi, 0.2 + shimmer))
	PixelDraw.px_diamond(canvas, -3.0, -5.0, 9.0, 4.0, water_hi, 0.5 + shimmer * 2.0)
	# pedestal
	PixelDraw.px_rect(canvas, -6.0, -26.0, 12.0, 24.0, stone)
	PixelDraw.px_rect(canvas, -6.0, -26.0, 4.0, 24.0, stone_hi)
	# upper basin
	PixelDraw.px_diamond(canvas, 0.0, -26.0, 14.0, 7.0, PixelPalette.shade(stone, 0.9))
	PixelDraw.px_diamond(canvas, 0.0, -27.0, 11.0, 5.0, water.lerp(water_hi, 0.3))
	# central spout + animated jets
	PixelDraw.px_rect(canvas, -2.0, -34.0, 4.0, 8.0, stone_hi)
	for i: int in 5:
		var ph := t * 4.0 + float(i) * 1.25
		var spread := float(i - 2) * 3.2
		var rise := 6.0 + (sin(ph) * 0.5 + 0.5) * 9.0
		PixelDraw.px_rect(canvas, spread - 1.0, -34.0 - rise, 2.0, rise, water_hi, 0.8)
		# droplets falling into the lower basin
		var dy := fmod(t * 26.0 + float(i) * 7.0, 28.0)
		PixelDraw.px_rect(canvas, spread * 2.2 - 1.0, -28.0 + dy, 2.0, 2.0, water_hi, 0.6)
