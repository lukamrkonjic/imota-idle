extends RefCounted
class_name RuinPillarArt
## A weathered, broken stone column drawn as a true isometric stack: a square
## plinth block, a fluted shaft prism, and either a surviving capital block or a
## jagged snapped crown — moss-streaked with a trailing vine. Variant drives the
## height tier, width and whether the capital survived.

const PixelPalette := preload("res://scripts/world/art/core/pixel_palette.gd")
const PixelDraw := preload("res://scripts/world/art/core/pixel_draw.gd")

const HEIGHTS := [42.0, 60.0, 78.0, 30.0]


static func draw(canvas: CanvasItem, variant: int = 0) -> void:
	PixelDraw.draw_foot_shadow(canvas, 15.0, 5.0, 0.3, 60.0)
	var stone := PixelPalette.pal("stone_b")
	var moss := PixelPalette.pal("grass_a").lerp(stone, 0.35)
	var vine := PixelPalette.pal("grass_c")
	var h: float = HEIGHTS[variant % HEIGHTS.size()]
	var hw := 6.0 if variant % 2 == 0 else 7.5
	var hh := hw * 0.5
	# plinth block
	PixelDraw.iso_block(canvas, 0.0, 0.0, hw + 4.0, (hw + 4.0) * 0.5, 9.0, PixelPalette.shade(stone, 0.9))
	# fluted shaft prism on top of the plinth
	var sh := h - 9.0
	PixelDraw.iso_block(canvas, 0.0, -9.0, hw, hh, sh, stone)
	# carved flute: a thin shaded seam down the lit SE face
	PixelDraw.px_rect(canvas, 2.0, -h + 8.0, 1.5, sh - 12.0, PixelPalette.shade(stone, 0.78), 0.5)
	var top_y := -9.0 - sh
	if variant % 3 == 0:
		# surviving capital block, slightly oversized
		PixelDraw.iso_block(canvas, 0.0, top_y, hw + 2.5, (hw + 2.5) * 0.5, 6.0, PixelPalette.shade(stone, 1.02))
	else:
		# jagged broken crown — a smaller block knocked off-centre
		PixelDraw.iso_block(canvas, 1.5, top_y, hw * 0.72, hw * 0.36, 5.0, PixelPalette.shade(stone, 0.84))
	# moss band across the front + hanging vines down the lit edge
	PixelDraw.px_rect(canvas, -hw + 1.0, -h * 0.5, hw + 2.0, 5.0, moss, 0.5)
	PixelDraw.px_rect(canvas, hw - 1.0, -h + 8.0, 2.0, 16.0, vine, 0.5)
	PixelDraw.px_rect(canvas, hw - 3.0, -h + 22.0, 2.0, 9.0, vine, 0.45)
