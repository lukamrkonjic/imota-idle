extends RefCounted
class_name RuinArchArt
## A grand, half-collapsed ceremonial gateway — the centrepiece of a ruined
## city. Tall columns carry a snapped lintel; the variant decides whether the
## far column still stands (closed arch) or has toppled, and the overall height.

const PixelPalette := preload("res://scripts/world/art/core/pixel_palette.gd")
const PixelDraw := preload("res://scripts/world/art/core/pixel_draw.gd")


static func draw(canvas: CanvasItem, variant: int = 0) -> void:
	PixelDraw.draw_foot_shadow(canvas, 32.0, 7.0, 0.3, 92.0)
	var stone := PixelPalette.pal("stone_b")
	var stone_hi := PixelPalette.pal("stone_a")
	var moss := PixelPalette.pal("grass_a").lerp(stone, 0.32)
	var vine := PixelPalette.pal("grass_c")
	var h := 84.0 + float(variant % 2) * 14.0
	var closed := variant % 3 == 0
	# left column (always tall)
	_column(canvas, -24.0, h, stone, stone_hi)
	# lintel cantilevered off the left column
	PixelDraw.px_rect(canvas, -28.0, -h - 9.0, 40.0, 10.0, stone)
	PixelDraw.px_rect(canvas, -28.0, -h - 9.0, 40.0, 3.0, stone_hi)
	if closed:
		# far column intact — completes the arch crown
		_column(canvas, 12.0, h, stone, stone_hi)
		PixelDraw.px_rect(canvas, 8.0, -h - 9.0, 20.0, 10.0, stone)
		PixelDraw.px_rect(canvas, 8.0, -h - 9.0, 20.0, 3.0, stone_hi)
	else:
		# far column snapped short, lintel breaks off in mid-air
		_column(canvas, 12.0, 42.0, stone, stone_hi)
		PixelDraw.px_rect(canvas, 12.0, -42.0, 14.0, 6.0, PixelPalette.shade(stone, 0.7))
		PixelDraw.px_rect(canvas, 8.0, -h - 7.0, 8.0, 8.0, PixelPalette.shade(stone, 0.72))
	# overgrowth: moss bands + hanging vines down the tall column
	PixelDraw.px_rect(canvas, -24.0, -h * 0.55, 14.0, 7.0, moss, 0.55)
	PixelDraw.px_rect(canvas, -22.0, -h + 8.0, 4.0, 20.0, vine, 0.5)
	PixelDraw.px_rect(canvas, -12.0, -h - 4.0, 3.0, 24.0, vine, 0.5)


static func _column(canvas: CanvasItem, x: float, h: float, stone: Color, stone_hi: Color) -> void:
	PixelDraw.px_rect(canvas, x - 3.0, -10.0, 18.0, 10.0, PixelPalette.shade(stone, 0.76))  # base
	PixelDraw.px_rect(canvas, x - 4.0, -13.0, 20.0, 4.0, stone_hi)
	PixelDraw.px_rect(canvas, x, -h, 12.0, h - 10.0, stone)                                 # shaft
	PixelDraw.px_rect(canvas, x, -h, 4.0, h - 10.0, stone_hi)                               # lit edge
	PixelDraw.px_rect(canvas, x + 8.0, -h + 6.0, 4.0, h - 16.0, PixelPalette.shade(stone, 0.8))
