extends RefCounted
class_name FountainArt
## A grand tiered stone fountain — a diamond lower basin, an isometric pedestal
## column carrying an upper basin, and animated jets/shimmer. The civic
## centrepiece of a city plaza. Pools stay 2:1 diamonds (water reads flat); the
## solid stone is built as iso blocks so it sits in the world.

const PixelPalette := preload("res://scripts/world/art/core/pixel_palette.gd")
const PixelDraw := preload("res://scripts/world/art/core/pixel_draw.gd")


static func draw(canvas: CanvasItem, t: float) -> void:
	PixelDraw.draw_foot_shadow(canvas, 30.0, 12.0, 0.3, 34.0)
	PixelDraw.draw_ground_collar(canvas, 30.0, false)
	var stone := PixelPalette.pal("stone_b")
	var stone_hi := PixelPalette.pal("stone_a")
	var water := PixelPalette.pal("water_a")
	var water_hi := PixelPalette.pal("water_foam")
	# lower basin rim as a low iso ring block, then the pool diamond on top
	PixelDraw.iso_block_tex(canvas, 0.0, 0.0, 30.0, 15.0, 5.0, PixelPalette.shade(stone, 0.9))
	var shimmer := sin(t * 2.4) * 0.06
	PixelDraw.px_diamond(canvas, 0.0, -5.0, 24.0, 12.0, water.lerp(water_hi, 0.2 + shimmer))
	PixelDraw.px_diamond(canvas, -3.0, -7.0, 9.0, 4.0, water_hi, 0.5 + shimmer * 2.0)
	# pedestal column (iso block rising from the pool)
	PixelDraw.iso_block_tex(canvas, 0.0, -5.0, 6.0, 3.0, 22.0, stone)
	# upper basin
	PixelDraw.iso_block_tex(canvas, 0.0, -27.0, 14.0, 7.0, 4.0, PixelPalette.shade(stone, 0.95))
	PixelDraw.px_diamond(canvas, 0.0, -31.0, 11.0, 5.0, water.lerp(water_hi, 0.3))
	# central spout + animated jets
	PixelDraw.px_rect(canvas, -2.0, -39.0, 4.0, 8.0, stone_hi)
	for i: int in 5:
		var ph := t * 4.0 + float(i) * 1.25
		var spread := float(i - 2) * 3.2
		var rise := 6.0 + (sin(ph) * 0.5 + 0.5) * 9.0
		PixelDraw.px_rect(canvas, spread - 1.0, -39.0 - rise, 2.0, rise, water_hi, 0.8)
		# droplets falling into the lower basin
		var dy := fmod(t * 26.0 + float(i) * 7.0, 28.0)
		PixelDraw.px_rect(canvas, spread * 2.2 - 1.0, -31.0 + dy, 2.0, 2.0, water_hi, 0.6)
