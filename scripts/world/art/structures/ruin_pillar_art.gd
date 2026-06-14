extends RefCounted
class_name RuinPillarArt
## A weathered, broken stone column — fluted shaft snapped at a jagged crown,
## moss-streaked with a trailing vine. Variant drives height tier, width, and
## whether the capital block survived, so a scatter of these reads as varied.

const PixelPalette := preload("res://scripts/world/art/core/pixel_palette.gd")
const PixelDraw := preload("res://scripts/world/art/core/pixel_draw.gd")

const HEIGHTS := [42.0, 60.0, 78.0, 30.0]


static func draw(canvas: CanvasItem, variant: int = 0) -> void:
	PixelDraw.draw_foot_shadow(canvas, 16.0, 4.0, 0.3, 60.0)
	var stone := PixelPalette.pal("stone_b")
	var stone_hi := PixelPalette.pal("stone_a")
	var moss := PixelPalette.pal("grass_a").lerp(stone, 0.35)
	var vine := PixelPalette.pal("grass_c")
	var h: float = HEIGHTS[variant % HEIGHTS.size()]
	var w := 9.0 if variant % 2 == 0 else 11.0
	# wide base plinth
	PixelDraw.px_rect(canvas, -w - 5.0, -10.0, (w + 5.0) * 2.0, 10.0, PixelPalette.shade(stone, 0.76))
	PixelDraw.px_rect(canvas, -w - 7.0, -13.0, (w + 7.0) * 2.0, 4.0, stone_hi)
	# shaft + lit / shaded edges
	PixelDraw.px_rect(canvas, -w, -h, w * 2.0, h - 10.0, stone)
	PixelDraw.px_rect(canvas, -w, -h, 4.0, h - 10.0, stone_hi)
	PixelDraw.px_rect(canvas, w - 4.0, -h + 6.0, 4.0, h - 16.0, PixelPalette.shade(stone, 0.8))
	# carved flutes
	PixelDraw.px_rect(canvas, -2.0, -h + 8.0, 2.0, h - 20.0, PixelPalette.shade(stone, 0.88), 0.6)
	PixelDraw.px_rect(canvas, 3.0, -h + 8.0, 2.0, h - 20.0, PixelPalette.shade(stone, 0.88), 0.5)
	# jagged broken crown
	PixelDraw.px_rect(canvas, -w, -h, 6.0, 6.0, PixelPalette.shade(stone, 0.7))
	PixelDraw.px_rect(canvas, 1.0, -h - 5.0, 7.0, 5.0, stone)
	if variant % 3 == 0:
		# surviving capital block
		PixelDraw.px_rect(canvas, -w - 3.0, -h - 7.0, (w + 3.0) * 2.0, 7.0, stone)
		PixelDraw.px_rect(canvas, -w - 3.0, -h - 7.0, (w + 3.0) * 2.0, 2.0, stone_hi)
	# moss + hanging vines
	PixelDraw.px_rect(canvas, -w, -h * 0.45, 5.0, 10.0, moss, 0.55)
	PixelDraw.px_rect(canvas, w - 5.0, -h + 8.0, 4.0, 14.0, vine, 0.5)
	PixelDraw.px_rect(canvas, w - 4.0, -h + 20.0, 2.0, 10.0, vine, 0.45)
